#[path = "ipc/auth.rs"]
mod ipc_auth;
#[cfg(any(target_os = "linux", target_os = "macos"))]
#[path = "ipc/fs.rs"]
mod ipc_fs;
// The DRM/KMS capture producer, the `_drm` channel and its SCM_RIGHTS framing live in their own
// module, declared the same way as the other pieces of this file, so the opt-in feature adds a
// bounded, self-contained surface here instead of ~1800 lines in the middle of the shared IPC.
#[cfg(all(target_os = "linux", feature = "drm"))]
#[path = "ipc/drm.rs"]
mod ipc_drm;
// Re-exported so the paths callers already use (`crate::ipc::start_drm`, `crate::ipc::connect_drm`,
// `crate::ipc::DrmDisplayInfo`) keep working, and so the `Data` variants can name the two
// payload types.
#[cfg(all(target_os = "linux", feature = "drm"))]
pub use ipc_drm::{start_drm, DmabufDesc, DrmDisplayInfo};
#[cfg(all(target_os = "linux", feature = "drm"))]
pub(crate) use ipc_drm::DrmConn;
#[cfg(all(target_os = "linux", feature = "drm"))]
pub(crate) use ipc_drm::connect_drm;

use crate::{
    common::{is_server, CheckTestNatType},
    privacy_mode,
    privacy_mode::PrivacyModeState,
    rendezvous_mediator::RendezvousMediator,
    ui_interface::{get_local_option, set_local_option},
};
use bytes::Bytes;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub use clipboard::ClipboardFile;
#[cfg(target_os = "linux")]
use hbb_common::anyhow;
use hbb_common::{
    allow_err, bail, bytes,
    bytes_codec::BytesCodec,
    config::{self, keys, keys::OPTION_ALLOW_WEBSOCKET, Config, Config2},
    futures::StreamExt as _,
    futures_util::sink::SinkExt,
    log, password_security as password, timeout,
    tokio::{
        self,
        io::{AsyncRead, AsyncWrite},
    },
    tokio_util::codec::Framed,
    ResultType,
};
#[cfg(windows)]
pub(crate) use ipc_auth::authorize_windows_portable_service_ipc_connection;
#[cfg(windows)]
pub(crate) use ipc_auth::ensure_peer_executable_matches_current_by_pid_opt;
#[cfg(windows)]
pub(crate) use ipc_auth::log_rejected_windows_ipc_connection;
#[cfg(any(target_os = "linux", target_os = "macos"))]
use ipc_auth::{active_uid, authorize_service_scoped_ipc_connection};
#[cfg(target_os = "macos")]
use ipc_auth::authorize_user_server_process;
#[cfg(windows)]
use ipc_auth::{
    authorize_windows_main_ipc_connection, portable_service_listener_security_attributes,
    connect_pipe, is_shared_pipe_on_windows, shared_pipe_security_attributes,
};
#[cfg(target_os = "linux")]
pub(crate) use ipc_auth::{
    ensure_peer_executable_matches_current_by_fd, is_allowed_service_peer_uid,
    log_rejected_uinput_connection, peer_uid_from_fd,
};
#[cfg(target_os = "linux")]
use ipc_fs::terminal_count_candidate_uids;
#[cfg(any(target_os = "linux", target_os = "macos"))]
use ipc_fs::{
    check_pid, ensure_secure_ipc_parent_dir, scrub_secure_ipc_parent_dir,
    should_scrub_parent_entries_after_check_pid, write_pid,
};
// Gated with the module that uses it, so a `drm`-less build does not carry an unused import.
#[cfg(all(target_os = "linux", feature = "drm"))]
use ipc_fs::remove_ipc_entry_via_secure_parent_fd;
use parity_tokio_ipc::{
    Connection as Conn, ConnectionClient as ConnClient, Endpoint, Incoming, SecurityAttributes,
};
use serde_derive::{Deserialize, Serialize};
#[cfg(any(target_os = "linux", target_os = "macos"))]
use std::cell::Cell;
#[cfg(any(target_os = "linux", target_os = "macos"))]
use std::os::unix::fs::PermissionsExt;
use std::{
    collections::HashMap,
    sync::atomic::{AtomicBool, Ordering},
};

// IPC actions here.
pub const IPC_ACTION_CLOSE: &str = "close";
#[cfg(target_os = "windows")]
const PORTABLE_SERVICE_IPC_HANDSHAKE_TIMEOUT_MS: u64 = 3_000;
#[cfg(target_os = "windows")]
pub(crate) const IPC_TOKEN_LEN: usize = 64;
#[cfg(target_os = "windows")]
const IPC_TOKEN_RANDOM_BYTES: usize = IPC_TOKEN_LEN / 2;
#[cfg(target_os = "windows")]
const _: () = assert!(IPC_TOKEN_LEN % 2 == 0);
pub static EXIT_RECV_CLOSE: AtomicBool = AtomicBool::new(true);

#[cfg(any(target_os = "linux", target_os = "macos"))]
thread_local! {
    static USE_USER_MAIN_IPC: Cell<bool> = Cell::new(false);
}

#[must_use = "bind this guard to a local variable to keep the IPC scope active"]
/// Thread-local guard for routing root main IPC to the active user on Linux/macOS.
#[cfg(any(target_os = "linux", target_os = "macos"))]
pub(crate) struct UserMainIpcScope {
    previous: bool,
}

#[cfg(any(target_os = "linux", target_os = "macos"))]
impl UserMainIpcScope {
    pub(crate) fn new() -> Self {
        let previous = USE_USER_MAIN_IPC.with(|use_user_main| {
            let previous = use_user_main.get();
            use_user_main.set(true);
            previous
        });
        Self { previous }
    }
}

#[cfg(any(target_os = "linux", target_os = "macos"))]
impl Drop for UserMainIpcScope {
    fn drop(&mut self) {
        USE_USER_MAIN_IPC.with(|use_user_main| use_user_main.set(self.previous));
    }
}

#[inline]
pub async fn connect_service(ms_timeout: u64) -> ResultType<ConnectionTmpl<ConnClient>> {
    connect(ms_timeout, crate::POSTFIX_SERVICE).await
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(tag = "t", content = "c")]
pub enum FS {
    ReadEmptyDirs {
        dir: String,
        include_hidden: bool,
    },
    ReadDir {
        dir: String,
        include_hidden: bool,
    },
    RemoveDir {
        path: String,
        id: i32,
        recursive: bool,
    },
    RemoveFile {
        path: String,
        id: i32,
        file_num: i32,
    },
    CreateDir {
        path: String,
        id: i32,
    },
    NewWrite {
        path: String,
        id: i32,
        file_num: i32,
        files: Vec<(String, u64)>,
        overwrite_detection: bool,
        total_size: u64,
        conn_id: i32,
    },
    CancelWrite {
        id: i32,
    },
    WriteBlock {
        id: i32,
        file_num: i32,
        data: Bytes,
        compressed: bool,
    },
    WriteDone {
        id: i32,
        file_num: i32,
    },
    WriteError {
        id: i32,
        file_num: i32,
        err: String,
    },
    WriteOffset {
        id: i32,
        file_num: i32,
        offset_blk: u32,
    },
    CheckDigest {
        id: i32,
        file_num: i32,
        file_size: u64,
        last_modified: u64,
        is_upload: bool,
        is_resume: bool,
    },
    SendConfirm(Vec<u8>),
    Rename {
        id: i32,
        path: String,
        new_name: String,
    },
    // CM-side file reading operations (Windows only)
    // These enable Connection Manager to read files and stream them back to Connection
    ReadFile {
        path: String,
        id: i32,
        file_num: i32,
        include_hidden: bool,
        conn_id: i32,
        overwrite_detection: bool,
    },
    CancelRead {
        id: i32,
        conn_id: i32,
    },
    SendConfirmForRead {
        id: i32,
        file_num: i32,
        skip: bool,
        offset_blk: u32,
        conn_id: i32,
    },
    ReadAllFiles {
        path: String,
        id: i32,
        include_hidden: bool,
        conn_id: i32,
    },
}

#[cfg(target_os = "windows")]
#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(tag = "t")]
pub struct ClipboardNonFile {
    pub compress: bool,
    pub content: bytes::Bytes,
    pub content_len: usize,
    pub next_raw: bool,
    pub width: i32,
    pub height: i32,
    // message.proto: ClipboardFormat
    pub format: i32,
    pub special_name: String,
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(tag = "t", content = "c")]
pub enum DataKeyboard {
    Sequence(String),
    KeyDown(enigo::Key),
    KeyUp(enigo::Key),
    KeyClick(enigo::Key),
    GetKeyState(enigo::Key),
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(tag = "t", content = "c")]
pub enum DataKeyboardResponse {
    GetKeyState(bool),
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(tag = "t", content = "c")]
pub enum DataMouse {
    MoveTo(i32, i32),
    MoveRelative(i32, i32),
    Down(enigo::MouseButton),
    Up(enigo::MouseButton),
    Click(enigo::MouseButton),
    ScrollX(i32),
    ScrollY(i32),
    Refresh,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(tag = "t", content = "c")]
pub enum DataControl {
    Resolution {
        minx: i32,
        maxx: i32,
        miny: i32,
        maxy: i32,
    },
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(tag = "t", content = "c")]
pub enum DataPortableService {
    Ping,
    Pong,
    AuthToken(String),
    AuthResult(bool),
    ConnCount(Option<usize>),
    Mouse((Vec<u8>, i32, String, u32, bool, bool)),
    Pointer((Vec<u8>, i32)),
    Key(Vec<u8>),
    RequestStart,
    WillClose,
    CmShowElevation(bool),
}

/// See [`Data::SealedCall`].
#[derive(Serialize, Deserialize, Clone)]
#[serde(tag = "t", content = "c")]
pub enum SealedCall {
    /// The call: method, path with query on the API server, the account
    /// token header.
    Ask {
        method: String,
        path: String,
        authorization: String,
    },
    /// The answer as an HTTP answer (status_code, headers, body), or why
    /// the server process did not make the call.
    Answer(Result<String, String>),
}

impl std::fmt::Debug for SealedCall {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Neither the token nor the answer goes into a log line
        match self {
            Self::Ask { method, .. } => write!(f, "SealedCall::Ask({method})"),
            Self::Answer(answer) => write!(f, "SealedCall::Answer(ok: {})", answer.is_ok()),
        }
    }
}

/// See [`Data::HandOverSecrets`]. Its Debug output names no secret.
#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(tag = "t", content = "c")]
pub enum HandOver {
    /// The secrets found in the profile.
    Secrets(Box<config::ProfileSecrets>),
    /// The answer: the public key (base64) of the process that holds the
    /// device's secrets, once it holds them.
    Held(String),
}

#[cfg(feature = "flutter")]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
#[derive(Debug, Serialize, Deserialize, Clone, Copy, PartialEq, Eq)]
pub enum SwitchSidesUuidAction {
    Check,
    Consume,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(tag = "t", content = "c")]
pub enum Data {
    Login {
        id: i32,
        is_file_transfer: bool,
        is_view_camera: bool,
        is_terminal: bool,
        peer_id: String,
        name: String,
        avatar: String,
        authorized: bool,
        port_forward: String,
        keyboard: bool,
        clipboard: bool,
        audio: bool,
        file: bool,
        file_transfer_enabled: bool,
        restart: bool,
        recording: bool,
        block_input: bool,
        privacy_mode: bool,
        from_switch: bool,
        /// Quick support (A271): the server vouched that the caller is a
        /// signed-in helper of the web console, and `name` is the helper's
        /// name as the server gave it.
        #[serde(default)]
        vouched: bool,
    },
    ChatMessage {
        text: String,
    },
    SwitchPermission {
        name: String,
        enabled: bool,
    },
    SystemInfo(Option<String>),
    ClickTime(i64),
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    MouseMoveTime(i64),
    Authorize,
    Close,
    #[cfg(windows)]
    SAS,
    UserSid(Option<u32>),
    OnlineStatus(Option<(i64, bool)>),
    Config((String, Option<String>)),
    Options(Option<HashMap<String, String>>),
    NatType(Option<i32>),
    /// The path of a pairing request or a join (both POST), answered with
    /// the server process's public key and key proof for it
    /// (hbbs_http/pairing_proof.rs); None for any other path.
    PairingProof((String, Option<(String, Vec<(String, String)>)>)),
    /// A NeoDesk API call another process has the server process seal, send
    /// and open, for the calls of hbbs_http/sealed_calls.rs only (L500, L507).
    SealedCall(SealedCall),
    /// The device's secrets an older version left in the person's profile,
    /// handed to the process that holds them (L442), see
    /// [`settle_device_secrets`].
    HandOverSecrets(HandOver),
    /// The chat window's socket and files, through the process that keeps
    /// the device token (nd_chat.rs).
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    NdChat(crate::nd_chat::NdChat),
    RawMessage(Vec<u8>),
    Socks(Option<config::Socks5Server>),
    FS(FS),
    Test,
    SyncConfig(Option<Box<(Config, Config2)>>),
    #[cfg(target_os = "windows")]
    ClipboardFile(ClipboardFile),
    ClipboardFileEnabled(bool),
    #[cfg(target_os = "windows")]
    ClipboardNonFile(Option<(String, Vec<ClipboardNonFile>)>),
    PrivacyModeState((i32, PrivacyModeState, String)),
    TestRendezvousServer,
    Deployed,
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    Keyboard(DataKeyboard),
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    KeyboardResponse(DataKeyboardResponse),
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    Mouse(DataMouse),
    Control(DataControl),
    Theme(String),
    Language(String),
    ConnectionModeChanged(Option<String>),
    Empty,
    Disconnected,
    DataPortableService(DataPortableService),
    #[cfg(feature = "flutter")]
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    SwitchSidesRequest(String),
    #[cfg(feature = "flutter")]
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    SwitchSidesUuid(String, String, SwitchSidesUuidAction, Option<bool>),
    #[cfg(feature = "flutter")]
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    SwitchSidesBack,
    UrlLink(String),
    VoiceCallIncoming,
    StartVoiceCall,
    /// Connection -> connection manager: input of the peer arrived (sent at
    /// most twice a second while it arrives).
    PeerInput,
    VoiceCallResponse(bool),
    CloseVoiceCall(String),
    #[cfg(windows)]
    SyncWinCpuUsage(Option<f64>),
    FileTransferLog((String, String)),
    #[cfg(windows)]
    ControlledSessionCount(usize),
    CmErr(String),
    // CM-side file reading responses (Windows only)
    // These are sent from CM back to Connection when CM handles file reading
    /// Response to ReadFile: contains initial file list or error
    ReadJobInitResult {
        id: i32,
        file_num: i32,
        include_hidden: bool,
        conn_id: i32,
        /// Serialized protobuf bytes of FileDirectory, or error string
        result: Result<Vec<u8>, String>,
    },
    /// File data block read by CM.
    ///
    /// The actual data is sent separately via `send_raw()` after this message to avoid
    /// JSON encoding overhead for large binary data. This mirrors the `WriteBlock` pattern.
    ///
    /// **Protocol:**
    /// - Sender: `send(FileBlockFromCM{...})` then `send_raw(data)`
    /// - Receiver: `next()` returns `FileBlockFromCM`, then `next_raw()` returns data bytes
    ///
    /// **Note on empty data (e.g., empty files):**
    /// Empty data is supported. The IPC connection uses `BytesCodec` with `raw=false` (default),
    /// which prefixes each frame with a length header. So `send_raw(Bytes::new())` sends a
    /// 1-byte frame (length=0), and `next_raw()` correctly returns an empty `BytesMut`.
    /// See `libs/hbb_common/src/bytes_codec.rs` test `test_codec2` for verification.
    FileBlockFromCM {
        id: i32,
        file_num: i32,
        /// Data is sent separately via `send_raw()` to avoid JSON encoding overhead.
        /// This field is skipped during serialization; sender must call `send_raw()` after sending.
        /// Receiver must call `next_raw()` and populate this field manually.
        #[serde(skip)]
        data: bytes::Bytes,
        compressed: bool,
        conn_id: i32,
    },
    /// File read completed successfully
    FileReadDone {
        id: i32,
        file_num: i32,
        conn_id: i32,
    },
    /// File read failed with error
    FileReadError {
        id: i32,
        file_num: i32,
        err: String,
        conn_id: i32,
    },
    /// Digest info from CM for overwrite detection
    FileDigestFromCM {
        id: i32,
        file_num: i32,
        last_modified: u64,
        file_size: u64,
        is_resume: bool,
        conn_id: i32,
    },
    /// Response to ReadAllFiles: recursive directory listing
    AllFilesResult {
        id: i32,
        conn_id: i32,
        path: String,
        /// Serialized protobuf bytes of FileDirectory, or error string
        result: Result<Vec<u8>, String>,
    },
    CheckHwcodec,
    #[cfg(feature = "flutter")]
    VideoConnCount(Option<usize>),
    // Although the key is not necessary, it is used to avoid hardcoding the key.
    WaylandScreencastRestoreToken((String, String)),
    HwCodecConfig(Option<String>),
    RemoveTrustedDevices(Vec<Bytes>),
    ClearTrustedDevices,
    #[cfg(all(target_os = "windows", feature = "flutter"))]
    PrinterData(Vec<u8>),
    InstallOption(Option<(String, String)>),
    #[cfg(all(
        feature = "flutter",
        not(any(target_os = "android", target_os = "ios"))
    ))]
    ControllingSessionCount(usize),
    #[cfg(target_os = "linux")]
    TerminalSessionCount(usize),
    #[cfg(target_os = "windows")]
    PortForwardSessionCount(Option<usize>),
    SocksWs(Option<Box<(Option<config::Socks5Server>, String)>>),
    #[cfg(target_os = "macos")]
    HasNoActiveConns(Option<bool>),
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    Whiteboard((String, crate::whiteboard::CustomEvent)),
    ControlPermissionsRemoteModify(Option<bool>),
    #[cfg(target_os = "windows")]
    FileTransferEnabledState(Option<bool>),
    /// CM -> server: the connection manager's WINDOW went away, which is not the same event
    /// as the operator disconnecting a peer. Linux only, and deliberately: there a session
    /// logout closes every window, and the close arrives at the CM indistinguishable from a
    /// person clicking it - measured on KDE, the CM gets no signal and logind still reports the
    /// session active. So the ambiguous case ends the session WITHOUT the no-retry reason and
    /// the peer is allowed to reconnect (landing on the greeter after a logout), while the
    /// explicit Disconnect button keeps sending `Close` and kicking for good.
    #[cfg(target_os = "linux")]
    CmWindowClosed,
    // --- DRM/KMS capture (opt-in `drm` feature) over the `_drm` service-scoped channel ---
    // All of the following are `cfg(all(linux, drm))`, so the drm-off IPC wire is byte-identical
    // to upstream. `_drm` protocol: the client sends `DrmHello`, the service `DrmDisplayList`, the
    // client replies `DrmStart{display}`, then the service streams `DrmFrame` + send_raw(BGRA) and
    // `DrmCursor` + send_raw(RGBA). A frame/cursor header is ALWAYS immediately followed by exactly
    // one `send_raw()` payload (the same header-then-raw pairing as `FileBlockFromCM`). This keeps
    // the header extensible. The zero-copy `DrmFrameDmabuf(DmabufDesc)` sibling below carries only a
    // small JSON metadata descriptor; the scanout dma-buf fd rides an SCM_RIGHTS ancillary message on
    // the same `DrmConn` send (see `DrmConn::send_msg`), so it has NO trailing `send_raw()` body.
    /// Client -> service, first on `_drm`: whether the service may wake sleeping displays before
    /// it answers. The cache warm at every `--server` start says no: no peer is waiting for it.
    #[cfg(all(target_os = "linux", feature = "drm"))]
    DrmHello { wake: bool },
    /// Client -> service: begin streaming the chosen display.
    #[cfg(all(target_os = "linux", feature = "drm"))]
    // `need_cpu` is set by an unprivileged consumer that could not open a render-node convert context
    // (drmtap_open_render failed, e.g. no /dev/dri/renderD* access). The service then streams the
    // CPU-converted `DrmFrame` path for this connection instead of a dma-buf fd the consumer cannot
    // detile, so a render-node-less seat still captures instead of losing the stream.
    DrmStart { display: i32, need_cpu: bool },
    /// Service -> client: the enumerated DRM displays (sent once, before frames).
    #[cfg(all(target_os = "linux", feature = "drm"))]
    DrmDisplayList(Vec<DrmDisplayInfo>),
    /// Service -> client: the connector topology changed mid-stream (a monitor hotplug/unplug/modeset,
    /// observed by the service's udev DRM-uevent listener). Carries the freshly-enumerated list so the
    /// consumer can swap its sticky positive availability cache off the hot path, WITHOUT re-probing
    /// `_drm` (which would trip the enumeration restart loop). Interleaved with frames on the same
    /// stream; carries no `send_raw()` body and no fd.
    #[cfg(all(target_os = "linux", feature = "drm"))]
    DrmDisplaysChanged(Vec<DrmDisplayInfo>),
    /// Service -> client: a frame header; the packed BGRA pixels follow via `send_raw()`.
    /// CPU-fallback path (no render node, or no transferable dma-buf): pixels cross the wire.
    #[cfg(all(target_os = "linux", feature = "drm"))]
    DrmFrame {
        width: u32,
        height: u32,
        /// See `DmabufDesc::plane_rotation`; absent from a producer older than this field.
        #[serde(default)]
        plane_rotation: Option<u32>,
        /// See `DmabufDesc::cursor_pos`: the cursor plane position read right after this frame,
        /// or `None` when the cursor is hidden, the read failed or the producer predates the field.
        #[serde(default)]
        cursor_pos: Option<(i32, i32)>,
    },
    /// Service -> client: a zero-copy dma-buf frame descriptor. The scanout fd is NOT a field; when
    /// `desc.has_fd` it rides an SCM_RIGHTS ancillary message on the same `DrmConn::send_msg`, and
    /// there is NO trailing `send_raw()` body. The unprivileged `--server` imports the fd and does
    /// the EGL detile/convert itself (see `DmabufDesc`).
    #[cfg(all(target_os = "linux", feature = "drm"))]
    DrmFrameDmabuf(DmabufDesc),
    /// Service -> client: a hardware-cursor header; the RGBA pixels follow via `send_raw()`.
    #[cfg(all(target_os = "linux", feature = "drm"))]
    DrmCursor {
        id: u64,
        width: u32,
        height: u32,
        hotx: i32,
        hoty: i32,
        /// Whether the hotspot came from the driver, or was inferred from the bitmap.
        ///
        /// Absent means the producer predates the field, and the default must then be TRUE, not
        /// `bool::default()`. These messages are JSON over a unix socket between two processes
        /// that are upgraded separately: an old root service can be streaming to a freshly
        /// started `--server`, and its `{"hotx": 12, "hoty": 11}` carries no provenance. Read as
        /// `false`, the new consumer would throw that hotspot away and re-infer one from the
        /// upright bitmap, moving the cursor on a rotated display for the length of the upgrade.
        /// Defaulting to true means "no provenance available, so behave as the old protocol did"
        /// -- use the point the producer sent. It is not a claim that the value was measured; a
        /// new producer that wants re-inference says `hot_measured: false` explicitly, which
        /// serializes, so new-to-new is unaffected.
        #[serde(default = "legacy_hot_measured")]
        hot_measured: bool,
    },
}

/// The default for a `hot_measured` that is not on the wire at all; see the field's docs.
#[cfg(all(target_os = "linux", feature = "drm"))]
fn legacy_hot_measured() -> bool {
    true
}

#[tokio::main(flavor = "current_thread")]
pub async fn start(postfix: &str) -> ResultType<()> {
    let mut incoming = new_listener(postfix).await?;
    loop {
        if let Some(result) = incoming.next().await {
            match result {
                Ok(stream) => {
                    let mut stream = Connection::new(stream);
                    let postfix = postfix.to_owned();
                    #[cfg(any(target_os = "linux", target_os = "macos"))]
                    if config::is_service_ipc_postfix(&postfix) {
                        if !authorize_service_scoped_ipc_connection(&stream, &postfix) {
                            continue;
                        }
                    }
                    #[cfg(windows)]
                    if postfix.is_empty() {
                        // Windows main IPC (`postfix == ""`) is authorized here.
                        // Other security-sensitive channels use dedicated authorization paths:
                        // - `_portable_service`: portable-service listener + handshake policy
                        // - service-scoped postfixes: service-specific listener/authorization
                        if !authorize_windows_main_ipc_connection(&stream, &postfix) {
                            continue;
                        }
                    }
                    tokio::spawn(async move {
                        loop {
                            match stream.next().await {
                                Err(err) => {
                                    log::trace!("ipc '{}' connection closed: {}", postfix, err);
                                    break;
                                }
                                Ok(Some(data)) => {
                                    // On Linux/macOS, the protected `_service` channel is used only for
                                    // syncing config between root service and the active user process.
                                    //
                                    // NOTE: `is_service_ipc_postfix()` also includes `_uinput_*`, but those
                                    // channels are handled by the dedicated uinput listener/protocol in
                                    // `src/server/uinput.rs` and therefore do not share this Data enum
                                    // allowlist. The SyncConfig allowlist here is intentionally scoped to the
                                    // `_service` channel only.
                                    //
                                    // Keep this explicit branch to avoid policy drift between `_service` and
                                    // uinput IPC paths while still minimizing exposed message surface here.
                                    #[cfg(any(target_os = "linux", target_os = "macos"))]
                                    if postfix == crate::POSTFIX_SERVICE {
                                        if matches!(&data, Data::SyncConfig(_)) {
                                            handle_service_sync(data, &mut stream).await;
                                        } else {
                                            log::warn!(
                                                "Rejected non-sync data on protected _service IPC channel: postfix={}, data_kind={:?}, peer_uid={:?}",
                                                postfix,
                                                std::mem::discriminant(&data),
                                                stream.peer_uid()
                                            );
                                            // Close the connection to avoid keeping a protected channel
                                            // alive while repeatedly receiving invalid traffic.
                                            break;
                                        }
                                        continue;
                                    }
                                    handle(data, &mut stream).await;
                                }
                                Ok(None) => {
                                    // `Ok(None)` means a complete frame arrived but did not
                                    // deserialize into `Data`. Peer close/reset is returned as
                                    // `Err` by `ConnectionTmpl::next()`. Keep the historical
                                    // ignore behavior except on the protected `_service` channel.
                                    #[cfg(any(target_os = "linux", target_os = "macos"))]
                                    {
                                        if postfix == crate::POSTFIX_SERVICE {
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    });
                }
                Err(err) => {
                    log::error!("Couldn't get client: {:?}", err);
                }
            }
        }
    }
}

/// Config name under which a client that joined or paired with a server
/// hands the device token to the server process, which keeps it.
pub const IPC_JOINED_DEVICE_TOKEN: &str = "neodesk-joined-device-token";
/// The server process's public key (base64), for a join in another
/// process (onboard/device_key.rs).
pub const IPC_PUBLIC_KEY: &str = "public-key";
/// Whether 2FA is on ("Y" or "N"). The 2FA secret itself stays in the
/// process that holds the device's secrets (L442).
pub const IPC_2FA_SET: &str = "2fa-set";
/// The receiver's tickets with something unread (nd_tickets.rs), which the
/// tray asks the process with the device token for.
pub const IPC_TICKETS_UNREAD: &str = "nd-tickets-unread";

fn bool_to_yn(value: bool) -> String {
    if value { "Y" } else { "N" }.to_owned()
}

/// The IPC path of `postfix` for this process. A quick support process uses
/// names of its own, so it never reaches an installed client's server,
/// connection manager or service. The pipes of an installed client's
/// service on Windows have protected names.
pub(crate) fn ipc_path(postfix: &str) -> String {
    let path = Config::ipc_path(postfix);
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    if crate::onboard::is_quick_support() {
        return crate::onboard::namespaced_ipc_path(&path);
    }
    #[cfg(windows)]
    if is_shared_pipe_on_windows(postfix) && is_installed_once() {
        return protected_pipe_path(&path);
    }
    path
}

/// The pipe path `path` under the prefix whose names only elevated
/// administrators and LocalSystem may create (L485). Any account may make
/// any other pipe name while the service is stopped and so keep the service
/// from serving; this name it can't take.
#[cfg(any(windows, test))]
fn protected_pipe_path(path: &str) -> String {
    const PIPES: &str = r"\\.\pipe\";
    match path.strip_prefix(PIPES) {
        Some(name) => format!(r"{PIPES}ProtectedPrefix\Administrators\{name}"),
        None => path.to_owned(),
    }
}

/// Whether the client is installed, read once per process: every process
/// of an installed client, the service and the person's, must agree on the
/// names of the service's pipes.
#[cfg(windows)]
fn is_installed_once() -> bool {
    static INSTALLED: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *INSTALLED.get_or_init(crate::platform::is_installed)
}

pub async fn new_listener(postfix: &str) -> ResultType<Incoming> {
    let path = ipc_path(postfix);
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    let should_scrub_parent_entries = ensure_secure_ipc_parent_dir(&path, postfix)?;
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    let existing_listener_alive = check_pid(postfix).await;
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    if should_scrub_parent_entries_after_check_pid(
        should_scrub_parent_entries,
        existing_listener_alive,
    ) {
        scrub_secure_ipc_parent_dir(&path, postfix)?;
    }
    let mut endpoint = Endpoint::new(path.clone());
    let security_attrs = {
        #[cfg(windows)]
        {
            if postfix == "_portable_service" {
                portable_service_listener_security_attributes()
            } else if is_shared_pipe_on_windows(postfix) {
                shared_pipe_security_attributes()
            } else {
                Ok(SecurityAttributes::empty())
            }
        }
        #[cfg(not(windows))]
        {
            SecurityAttributes::allow_everyone_create()
        }
    };
    match security_attrs {
        Ok(attr) => endpoint.set_security_attributes(attr),
        Err(err) => {
            log::error!("Failed to set ipc{} security: {}", postfix, err);
            #[cfg(windows)]
            if postfix == "_portable_service" {
                // Fail closed for `_portable_service` when SDDL construction fails.
                // This endpoint is security-critical and must not start with default ACLs.
                return Err(err.into());
            }
        }
    };
    match endpoint.incoming() {
        Ok(incoming) => {
            if postfix == crate::POSTFIX_SERVICE {
                log::info!("Started protected ipc service server: postfix={}", postfix);
            } else {
                log::info!("Started ipc{} server at path: {}", postfix, &path);
            }
            #[cfg(any(target_os = "linux", target_os = "macos"))]
            {
                // NOTE: On Linux/macOS, some IPC sockets are intentionally world-connectable
                // (0666) so the active (non-root) user process can connect. Authorization is
                // enforced at accept-time for these channels, and the protected `_service`
                // channel is further restricted by an explicit message allowlist (SyncConfig
                // only).
                let socket_mode = if config::is_service_ipc_postfix(postfix) {
                    0o0666
                } else {
                    0o0600
                };
                if let Err(err) =
                    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(socket_mode))
                {
                    log::error!(
                        "Failed to set permissions on ipc{} socket at path {}: {}",
                        postfix,
                        &path,
                        err
                    );
                    std::fs::remove_file(&path).ok();
                    return Err(err.into());
                }
                write_pid(postfix);
            }
            Ok(incoming)
        }
        Err(err) => {
            log::error!(
                "Failed to start ipc{} server at path {}: {}",
                postfix,
                path,
                err
            );
            Err(err.into())
        }
    }
}

pub struct CheckIfRestart {
    stop_service: String,
    rendezvous_servers: Vec<String>,
    audio_input: String,
    voice_call_input: String,
    ws: String,
    disable_udp: String,
    allow_insecure_tls_fallback: String,
    api_server: String,
}

impl CheckIfRestart {
    pub fn new() -> CheckIfRestart {
        CheckIfRestart {
            stop_service: Config::get_option("stop-service"),
            rendezvous_servers: Config::get_rendezvous_servers(),
            audio_input: Config::get_option("audio-input"),
            voice_call_input: Config::get_option("voice-call-input"),
            ws: Config::get_option(OPTION_ALLOW_WEBSOCKET),
            disable_udp: Config::get_option(config::keys::OPTION_DISABLE_UDP),
            allow_insecure_tls_fallback: Config::get_option(
                config::keys::OPTION_ALLOW_INSECURE_TLS_FALLBACK,
            ),
            api_server: Config::get_option("api-server"),
        }
    }
}
impl Drop for CheckIfRestart {
    fn drop(&mut self) {
        // If https proxy is used, we need to restart rendezvous mediator.
        // No need to check if https proxy is used, because this option does not change frequently
        // and restarting mediator is safe even https proxy is not used.
        let allow_insecure_tls_fallback_changed = self.allow_insecure_tls_fallback
            != Config::get_option(config::keys::OPTION_ALLOW_INSECURE_TLS_FALLBACK);
        if allow_insecure_tls_fallback_changed
            || self.stop_service != Config::get_option("stop-service")
            || self.rendezvous_servers != Config::get_rendezvous_servers()
            || self.ws != Config::get_option(OPTION_ALLOW_WEBSOCKET)
            || self.disable_udp != Config::get_option(config::keys::OPTION_DISABLE_UDP)
            || self.api_server != Config::get_option("api-server")
        {
            if allow_insecure_tls_fallback_changed {
                hbb_common::tls::reset_tls_cache();
            }
            RendezvousMediator::restart();
        }
        if self.audio_input != Config::get_option("audio-input") {
            crate::audio_service::restart();
        }
        if self.voice_call_input != Config::get_option("voice-call-input") {
            crate::audio_service::set_voice_call_input_device(
                Some(Config::get_option("voice-call-input")),
                true,
            )
        }
    }
}

async fn handle(data: Data, stream: &mut Connection) {
    match data {
        Data::SystemInfo(_) => {
            let info = format!(
                "log_path: {}, config: {}, username: {}",
                Config::log_path().to_str().unwrap_or(""),
                Config::file().to_str().unwrap_or(""),
                crate::username(),
            );
            allow_err!(stream.send(&Data::SystemInfo(Some(info))).await);
        }
        Data::ClickTime(_) => {
            let t = crate::server::CLICK_TIME.load(Ordering::SeqCst);
            allow_err!(stream.send(&Data::ClickTime(t)).await);
        }
        #[cfg(not(any(target_os = "android", target_os = "ios")))]
        Data::MouseMoveTime(_) => {
            let t = crate::server::MOUSE_MOVE_TIME.load(Ordering::SeqCst);
            allow_err!(stream.send(&Data::MouseMoveTime(t)).await);
        }
        Data::Close => {
            log::info!("Receive close message");
            if EXIT_RECV_CLOSE.load(Ordering::SeqCst) {
                #[cfg(not(target_os = "android"))]
                crate::server::input_service::fix_key_down_timeout_at_exit();
                if is_server() {
                    let _ = privacy_mode::turn_off_privacy(0, Some(PrivacyModeState::OffByPeer));
                }
                #[cfg(any(target_os = "macos", target_os = "linux"))]
                if crate::is_main() {
                    // below part is for main windows can be reopen during rustdesk installation and installing service from UI
                    // this make new ipc server (domain socket) can be created.
                    std::fs::remove_file(&ipc_path("")).ok();
                    #[cfg(target_os = "linux")]
                    {
                        hbb_common::sleep((crate::platform::SERVICE_INTERVAL * 2) as f32 / 1000.0)
                            .await;
                        // https://github.com/rustdesk/rustdesk/discussions/9254
                        crate::run_me::<&str>(vec!["--no-server"]).ok();
                    }
                    #[cfg(target_os = "macos")]
                    {
                        // our launchagent interval is 1 second
                        hbb_common::sleep(1.5).await;
                        std::process::Command::new("open")
                            .arg("-n")
                            .arg(&format!("/Applications/{}.app", crate::get_app_name()))
                            .spawn()
                            .ok();
                    }
                    // leave above open a little time
                    hbb_common::sleep(0.3).await;
                    // in case below exit failed
                    crate::platform::quit_gui();
                }
                std::process::exit(-1); // to make sure --server luauchagent process can restart because SuccessfulExit used
            }
        }
        Data::OnlineStatus(_) => {
            let x = config::get_online_state();
            let confirmed = Config::get_key_confirmed();
            allow_err!(stream.send(&Data::OnlineStatus(Some((x, confirmed)))).await);
        }
        Data::PairingProof((path, None)) => {
            let proof = crate::hbbs_http::enrollment::proof_for_others(
                crate::hbbs_http::pairing_proof::METHOD,
                &path,
            );
            allow_err!(stream.send(&Data::PairingProof((path, proof))).await);
        }
        #[cfg(not(target_os = "ios"))]
        Data::SealedCall(SealedCall::Ask {
            method,
            path,
            authorization,
        }) => {
            let answer =
                crate::common::sealed_call_for_other_process(&method, &path, &authorization).await;
            if let Err(err) = &answer {
                hbb_common::throttled_log!(
                    std::time::Duration::from_secs(60),
                    warn,
                    "Sealed call {method} for another process not made: {err}"
                );
            }
            allow_err!(
                stream
                    .send(&Data::SealedCall(SealedCall::Answer(answer)))
                    .await
            );
        }
        #[cfg(not(any(target_os = "android", target_os = "ios")))]
        Data::NdChat(request) => crate::nd_chat::serve(request, stream).await,
        Data::HandOverSecrets(HandOver::Secrets(secrets)) => {
            if let Some(public_key) = take_handed_over_secrets(*secrets) {
                allow_err!(
                    stream
                        .send(&Data::HandOverSecrets(HandOver::Held(public_key)))
                        .await
                );
            }
        }
        Data::Socks(s) => match s {
            None => {
                allow_err!(stream.send(&Data::Socks(Config::get_socks())).await);
            }
            Some(data) => {
                let _nat = CheckTestNatType::new();
                if data.proxy.is_empty() {
                    Config::set_socks(None);
                } else {
                    Config::set_socks(Some(data));
                }
                RendezvousMediator::restart();
                log::info!("socks updated");
            }
        },
        Data::SocksWs(s) => match s {
            None => {
                allow_err!(
                    stream
                        .send(&Data::SocksWs(Some(Box::new((
                            Config::get_socks(),
                            Config::get_option(OPTION_ALLOW_WEBSOCKET)
                        )))))
                        .await
                );
            }
            _ => {}
        },
        #[cfg(feature = "flutter")]
        Data::VideoConnCount(None) => {
            let n = crate::server::AUTHED_CONNS
                .lock()
                .unwrap()
                .iter()
                .filter(|x| x.conn_type == crate::server::AuthConnType::Remote)
                .count();
            allow_err!(stream.send(&Data::VideoConnCount(Some(n))).await);
        }
        Data::Config((name, value)) => match value {
            None => {
                let value;
                if name == "id" {
                    value = Some(Config::get_id());
                } else if name == "temporary-password" {
                    value = Some(password::temporary_password());
                } else if name == IPC_2FA_SET {
                    // Whether 2FA is on, never the secret (L442)
                    value = Some(bool_to_yn(crate::auth_2fa::get_2fa(None).is_some()));
                } else if name == "permanent-password-set" {
                    value = Some(if Config::has_permanent_password() {
                        "Y".to_owned()
                    } else {
                        "N".to_owned()
                    });
                } else if name == "permanent-password-is-preset" {
                    value = Some(if Config::is_using_preset_password() {
                        "Y".to_owned()
                    } else {
                        "N".to_owned()
                    });
                } else if name == "salt" {
                    value = Some(Config::get_salt());
                } else if name == "rendezvous_server" {
                    value = Some(format!(
                        "{},{}",
                        Config::get_rendezvous_server(),
                        Config::get_rendezvous_servers().join(",")
                    ));
                } else if name == "rendezvous_servers" {
                    value = Some(Config::get_rendezvous_servers().join(","));
                } else if name == IPC_PUBLIC_KEY {
                    // A join in another process sends the console this
                    // process's key, the one it signs with (L438)
                    value = crate::hbbs_http::enrollment::public_key_b64();
                } else if name == "fingerprint" {
                    value = if Config::get_key_confirmed() {
                        Some(crate::common::pk_to_fingerprint(Config::get_key_pair().1))
                    } else {
                        None
                    };
                } else if name == "hide_cm" {
                    value = if crate::hbbs_http::sync::is_pro() || crate::common::is_custom_client()
                    {
                        Some(hbb_common::password_security::hide_cm().to_string())
                    } else {
                        None
                    };
                } else if name == "voice-call-input" {
                    value = crate::audio_service::get_voice_call_input_device();
                } else if name == "unlock-pin" {
                    value = Some(Config::get_unlock_pin());
                } else if name == "trusted-devices" {
                    value = Some(Config::get_trusted_devices_json());
                } else if name == IPC_TICKETS_UNREAD {
                    // The receiver's tray: tickets with something unread
                    #[cfg(not(any(target_os = "android", target_os = "ios")))]
                    {
                        value = crate::nd_tickets::unread().map(|n| n.to_string());
                    }
                    #[cfg(any(target_os = "android", target_os = "ios"))]
                    {
                        value = None;
                    }
                } else {
                    value = None;
                }
                allow_err!(stream.send(&Data::Config((name, value))).await);
            }
            Some(value) => {
                let mut updated = true;
                if name == "id" {
                    // An empty id would wipe the local id and unconfirm the key (cf. #15626).
                    if value.is_empty() {
                        log::warn!("Ignoring empty id write over IPC");
                        updated = false;
                    } else {
                        Config::set_key_confirmed(false);
                        Config::set_id(&value);
                    }
                } else if name == "temporary-password" {
                    password::update_temporary_password();
                } else if name == "permanent-password" {
                    if Config::is_disable_change_permanent_password() {
                        log::warn!("Changing permanent password is disabled");
                        updated = false;
                    } else {
                        updated = Config::set_permanent_password(&value);
                    }
                    // Explicitly ACK/NACK permanent-password writes. This allows UIs/FFI to
                    // distinguish "accepted by daemon" vs "IPC send succeeded" without
                    // reading back any secret.
                    let ack = if updated { "Y" } else { "N" }.to_owned();
                    allow_err!(stream.send(&Data::Config((name.clone(), Some(ack)))).await);
                } else if name == keys::OPTION_2FA {
                    // Turns 2FA on with a secret the window made, or off with
                    // an empty value, and answers whether it took it (L442)
                    updated = value.is_empty()
                        || crate::auth_2fa::get_2fa(Some(value.clone())).is_some();
                    if updated {
                        Config::set_option(keys::OPTION_2FA.to_owned(), value);
                    }
                    allow_err!(
                        stream
                            .send(&Data::Config((name.clone(), Some(bool_to_yn(updated)))))
                            .await
                    );
                } else if name == "salt" {
                    Config::set_salt(&value);
                } else if name == "voice-call-input" {
                    crate::audio_service::set_voice_call_input_device(Some(value), true);
                } else if name == "unlock-pin" {
                    Config::set_unlock_pin(&value);
                } else if name == IPC_JOINED_DEVICE_TOKEN {
                    #[cfg(not(any(target_os = "android", target_os = "ios")))]
                    crate::onboard::store_device_token(&value);
                } else {
                    return;
                }
                if updated {
                    log::info!("{} updated", name);
                }
            }
        },
        Data::ConnectionModeChanged(None) => {
            allow_err!(
                stream
                    .send(&Data::ConnectionModeChanged(Some(
                        config::connection_mode().to_owned(),
                    )))
                    .await
            );
        }
        Data::ConnectionModeChanged(Some(_)) => {}
        Data::Options(value) => match value {
            // The secret options (the 2FA secret) never travel this
            // channel (L442)
            None => {
                let v = Config::get_options_for_other_process();
                allow_err!(stream.send(&Data::Options(Some(v))).await);
            }
            Some(mut value) => {
                let _chk = CheckIfRestart::new();
                let _nat = CheckTestNatType::new();
                if let Some(v) = value.get("privacy-mode-impl-key") {
                    crate::privacy_mode::switch(v);
                }
                #[cfg(all(target_os = "linux", feature = "drm"))]
                let drm_capture_was_on = crate::platform::linux::drm_login_screen_allowed();
                // What the server's strategy manages stays the server's (A267)
                crate::hbbs_http::sync::keep_server_managed(&mut value, &Config::get_options());
                Config::set_options_from_other_process(value);
                allow_err!(stream.send(&Data::Options(None)).await);
                // Not from a UI that hosts this IPC itself: its copy of the config can be older
                // than the service's, and the sync sends all of it.
                #[cfg(all(target_os = "linux", feature = "drm"))]
                if crate::is_server() {
                    crate::platform::linux::sync_drm_capture_to_service(drm_capture_was_on).await;
                }
            }
        },
        Data::NatType(_) => {
            let t = Config::get_nat_type();
            allow_err!(stream.send(&Data::NatType(Some(t))).await);
        }
        // The device's secrets (key pair, stored permanent password, 2FA
        // secret) never travel this channel (L442)
        Data::SyncConfig(Some(configs)) => {
            let (config, config2) = *configs;
            let _chk = CheckIfRestart::new();
            Config::set_from_other_process(config);
            Config2::set_from_other_process(config2);
            allow_err!(stream.send(&Data::SyncConfig(None)).await);
        }
        Data::SyncConfig(None) => {
            allow_err!(
                stream
                    .send(&Data::SyncConfig(Some(
                        (
                            Config::get_for_other_process(),
                            Config2::get_for_other_process()
                        )
                            .into()
                    )))
                    .await
            );
        }
        #[cfg(windows)]
        Data::SyncWinCpuUsage(None) => {
            allow_err!(
                stream
                    .send(&Data::SyncWinCpuUsage(
                        hbb_common::platform::windows::cpu_uage_one_minute()
                    ))
                    .await
            );
        }
        Data::TestRendezvousServer => {
            crate::test_rendezvous_server();
        }
        Data::Deployed => {
            crate::rendezvous_mediator::NEEDS_DEPLOY.store(false, Ordering::SeqCst);
            crate::rendezvous_mediator::RendezvousMediator::restart();
        }
        #[cfg(feature = "flutter")]
        #[cfg(not(any(target_os = "android", target_os = "ios")))]
        Data::SwitchSidesRequest(id) => {
            let uuid = uuid::Uuid::new_v4();
            crate::server::insert_switch_sides_uuid(id, uuid.clone());
            crate::hbbs_http::sync::register_switch_grant(uuid.to_string());
            allow_err!(
                stream
                    .send(&Data::SwitchSidesRequest(uuid.to_string()))
                    .await
            );
        }
        #[cfg(feature = "flutter")]
        #[cfg(not(any(target_os = "android", target_os = "ios")))]
        Data::SwitchSidesUuid(uuid, id, action, None) => {
            let allowed = uuid
                .parse::<uuid::Uuid>()
                .map(|uuid| match action {
                    SwitchSidesUuidAction::Check => {
                        crate::server::has_pending_switch_sides_uuid(&id, &uuid)
                    }
                    SwitchSidesUuidAction::Consume => {
                        crate::server::claim_pending_switch_sides_uuid(&id, &uuid)
                    }
                })
                .unwrap_or(false);
            allow_err!(
                stream
                    .send(&Data::SwitchSidesUuid(uuid, id, action, Some(allowed)))
                    .await
            );
        }
        #[cfg(windows)]
        Data::ControlledSessionCount(_) => {
            allow_err!(
                stream
                    .send(&Data::ControlledSessionCount(
                        crate::Connection::alive_conns().len()
                    ))
                    .await
            );
        }
        #[cfg(target_os = "macos")]
        Data::HasNoActiveConns(None) => {
            allow_err!(
                stream
                    .send(&Data::HasNoActiveConns(Some(
                        crate::updater::has_no_active_conns()
                    )))
                    .await
            );
        }
        #[cfg(all(
            feature = "flutter",
            not(any(target_os = "android", target_os = "ios"))
        ))]
        Data::ControllingSessionCount(count) => {
            crate::updater::update_controlling_session_count(count);
        }
        #[cfg(target_os = "linux")]
        Data::TerminalSessionCount(_) => {
            let count = crate::terminal_service::get_terminal_session_count(true);
            allow_err!(stream.send(&Data::TerminalSessionCount(count)).await);
        }
        #[cfg(feature = "hwcodec")]
        #[cfg(not(any(target_os = "android", target_os = "ios")))]
        Data::CheckHwcodec => {
            scrap::hwcodec::start_check_process();
        }
        #[cfg(feature = "hwcodec")]
        #[cfg(not(any(target_os = "android", target_os = "ios")))]
        Data::HwCodecConfig(c) => {
            match c {
                None => {
                    let v = match scrap::hwcodec::HwCodecConfig::get_set_value() {
                        Some(v) => Some(serde_json::to_string(&v).unwrap_or_default()),
                        None => None,
                    };
                    allow_err!(stream.send(&Data::HwCodecConfig(v)).await);
                }
                Some(v) => {
                    // --server and portable
                    scrap::hwcodec::HwCodecConfig::set(v);
                }
            }
        }
        Data::WaylandScreencastRestoreToken((key, value)) => {
            let v = if value == "get" {
                let opt = get_local_option(key.clone());
                #[cfg(not(target_os = "linux"))]
                {
                    Some(opt)
                }
                #[cfg(target_os = "linux")]
                {
                    let v = if opt.is_empty() {
                        if scrap::wayland::pipewire::is_rdp_session_hold() {
                            "fake token".to_string()
                        } else {
                            "".to_owned()
                        }
                    } else {
                        opt
                    };
                    Some(v)
                }
            } else if value == "clear" {
                set_local_option(key.clone(), "".to_owned());
                #[cfg(target_os = "linux")]
                scrap::wayland::pipewire::close_session();
                Some("".to_owned())
            } else {
                None
            };
            if let Some(v) = v {
                allow_err!(
                    stream
                        .send(&Data::WaylandScreencastRestoreToken((key, v)))
                        .await
                );
            }
        }
        Data::RemoveTrustedDevices(v) => {
            Config::remove_trusted_devices(&v);
        }
        Data::ClearTrustedDevices => {
            Config::clear_trusted_devices();
        }
        Data::InstallOption(opt) => match opt {
            Some((_k, _v)) => {
                #[cfg(target_os = "windows")]
                if let Err(e) = crate::platform::windows::update_install_option(&_k, &_v) {
                    log::error!(
                        "Failed to update install option \"{}\" to \"{}\", error: {}",
                        &_k,
                        &_v,
                        e
                    );
                }
            }
            None => {
                // `None` is usually used to get values.
                // This branch is left blank for unification and further use.
            }
        },
        #[cfg(target_os = "windows")]
        Data::PortForwardSessionCount(c) => match c {
            None => {
                let count = crate::server::AUTHED_CONNS
                    .lock()
                    .unwrap()
                    .iter()
                    .filter(|c| c.conn_type == crate::server::AuthConnType::PortForward)
                    .count();
                allow_err!(
                    stream
                        .send(&Data::PortForwardSessionCount(Some(count)))
                        .await
                );
            }
            _ => {
                // Port forward session count is only a get value.
            }
        },
        Data::ControlPermissionsRemoteModify(_) => {
            use hbb_common::rendezvous_proto::control_permissions::Permission;
            let state =
                crate::server::get_control_permission_state(Permission::remote_modify, true);
            allow_err!(
                stream
                    .send(&Data::ControlPermissionsRemoteModify(state))
                    .await
            );
        }
        #[cfg(target_os = "windows")]
        Data::FileTransferEnabledState(_) => {
            use hbb_common::rendezvous_proto::control_permissions::Permission;
            let state = crate::server::get_control_permission_state(Permission::file, false);
            let enabled = state.unwrap_or_else(|| {
                crate::server::Connection::is_permission_enabled_locally(
                    config::keys::OPTION_ENABLE_FILE_TRANSFER,
                )
            });
            allow_err!(
                stream
                    .send(&Data::FileTransferEnabledState(Some(enabled)))
                    .await
            );
        }
        _ => {}
    };
}

#[cfg(target_os = "windows")]
pub(crate) fn generate_one_time_ipc_token() -> ResultType<String> {
    use hbb_common::rand::{rngs::OsRng, RngCore as _};
    use std::fmt::Write as _;

    let mut random_bytes = [0u8; IPC_TOKEN_RANDOM_BYTES];
    let mut rng = OsRng;
    rng.try_fill_bytes(&mut random_bytes).map_err(|err| {
        hbb_common::anyhow::anyhow!(
            "failed to generate portable service ipc token from OsRng: {}",
            err
        )
    })?;

    let mut token = String::with_capacity(IPC_TOKEN_LEN);
    for byte in random_bytes {
        let _ = write!(token, "{:02x}", byte);
    }
    Ok(token)
}

#[cfg(target_os = "windows")]
pub(crate) fn constant_time_ipc_token_eq(expected: &str, candidate: &str) -> bool {
    if expected.len() != IPC_TOKEN_LEN || candidate.len() != IPC_TOKEN_LEN {
        return false;
    }
    expected
        .as_bytes()
        .iter()
        .zip(candidate.as_bytes().iter())
        .fold(0u8, |diff, (left, right)| diff | (*left ^ *right))
        == 0
}

#[cfg(target_os = "windows")]
pub(crate) async fn portable_service_ipc_handshake_as_client<T>(
    stream: &mut ConnectionTmpl<T>,
    token: &str,
) -> ResultType<()>
where
    T: AsyncRead + AsyncWrite + std::marker::Unpin,
{
    stream
        .send(&Data::DataPortableService(DataPortableService::AuthToken(
            token.to_owned(),
        )))
        .await?;
    match stream
        .next_timeout(PORTABLE_SERVICE_IPC_HANDSHAKE_TIMEOUT_MS)
        .await?
    {
        Some(Data::DataPortableService(DataPortableService::AuthResult(true))) => Ok(()),
        Some(Data::DataPortableService(DataPortableService::AuthResult(false))) => {
            bail!("portable service ipc handshake was rejected by server")
        }
        Some(_) | None => bail!("portable service ipc handshake returned an unexpected response"),
    }
}

#[cfg(target_os = "windows")]
pub(crate) async fn portable_service_ipc_handshake_as_server<T, F>(
    stream: &mut ConnectionTmpl<T>,
    mut validate_token: F,
) -> ResultType<()>
where
    T: AsyncRead + AsyncWrite + std::marker::Unpin,
    // Token validators must use `constant_time_ipc_token_eq` or an equivalent
    // fixed-length comparison; this handshake is part of the privilege boundary.
    F: FnMut(&str) -> bool,
{
    let authorized = match stream
        .next_timeout(PORTABLE_SERVICE_IPC_HANDSHAKE_TIMEOUT_MS)
        .await?
    {
        Some(Data::DataPortableService(DataPortableService::AuthToken(token))) => {
            validate_token(&token)
        }
        Some(_) | None => false,
    };
    stream
        .send(&Data::DataPortableService(DataPortableService::AuthResult(
            authorized,
        )))
        .await?;
    if !authorized {
        bail!("portable service ipc handshake failed")
    }
    Ok(())
}

#[inline]
async fn connect_with_path(ms_timeout: u64, path: &str) -> ResultType<ConnectionTmpl<ConnClient>> {
    #[cfg(windows)]
    let client = timeout(ms_timeout, connect_pipe(path)).await??;
    #[cfg(not(windows))]
    let client = timeout(ms_timeout, Endpoint::connect(path)).await??;
    Ok(ConnectionTmpl::new(client))
}

#[cfg(any(target_os = "linux", target_os = "macos"))]
#[inline]
fn select_server_uid_for_user_main_ipc(
    server_uids: &[u32],
    active_uid: Option<u32>,
    prefer_root: bool,
) -> ResultType<u32> {
    let mut server_uids = server_uids.to_vec();
    server_uids.sort_unstable();
    server_uids.dedup();

    match server_uids.as_slice() {
        [] => {
            if let Some(uid) = active_uid {
                // If no `--server` processes are found but the active user is identifiable,
                // try the active user anyway because the main process may also listen on "" IPC.
                return Ok(uid);
            } else {
                bail!("No --server process found for user main IPC")
            }
        }
        [uid] => return Ok(*uid),
        _ => {}
    }

    if prefer_root && server_uids.contains(&0) {
        return Ok(0);
    }
    if let Some(active_uid) = active_uid.filter(|uid| server_uids.contains(uid)) {
        return Ok(active_uid);
    }
    bail!("Multiple --server processes found for user main IPC");
}

#[cfg(any(target_os = "linux", target_os = "macos"))]
fn running_server_uids_for_current_exe() -> ResultType<Vec<u32>> {
    let current_exe = std::env::current_exe()?;
    let current_exe_path = std::fs::canonicalize(&current_exe)?;
    let current_pid = hbb_common::sysinfo::Pid::from_u32(std::process::id());
    let mut sys = hbb_common::sysinfo::System::new();
    sys.refresh_processes();
    let mut server_uids = Vec::new();
    for process in sys.processes().values() {
        if process.pid() == current_pid {
            continue;
        }
        if process.cmd().get(1).map_or(true, |arg| arg != "--server") {
            continue;
        }
        let Ok(process_path) = std::fs::canonicalize(process.exe()) else {
            continue;
        };
        if process_path != current_exe_path {
            continue;
        }
        let Some(uid) = process.user_id().map(|uid| **uid as u32) else {
            // Root CLI management commands need a stable matching `--server` target.
            // If this key process races during enumeration, failing the command is clearer
            // than silently skipping it; `--server` is not expected to exit frequently.
            bail!("Failed to read --server process uid");
        };
        server_uids.push(uid);
    }
    Ok(server_uids)
}

#[cfg(any(target_os = "linux", target_os = "macos"))]
fn user_main_ipc_server_uid() -> ResultType<u32> {
    let server_uids = running_server_uids_for_current_exe()?;
    #[cfg(target_os = "linux")]
    let prefer_root = crate::platform::linux::is_login_screen_wayland();
    #[cfg(target_os = "macos")]
    let prefer_root = false;
    select_server_uid_for_user_main_ipc(&server_uids, active_uid(), prefer_root)
}

pub async fn connect(ms_timeout: u64, postfix: &str) -> ResultType<ConnectionTmpl<ConnClient>> {
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    {
        let use_user_main_ipc = USE_USER_MAIN_IPC.with(|use_user_main| use_user_main.get());
        let is_root_main_ipc =
            unsafe { hbb_common::libc::geteuid() == 0 } && postfix.is_empty() && use_user_main_ipc;
        if is_root_main_ipc {
            let uid = user_main_ipc_server_uid()?;
            let path = Config::ipc_path_for_uid(uid, postfix);
            return connect_with_path(ms_timeout, &path).await;
        }
        let path = ipc_path(postfix);
        return connect_with_path(ms_timeout, &path).await;
    }
    #[cfg(not(any(target_os = "linux", target_os = "macos")))]
    {
        let path = ipc_path(postfix);
        let conn = connect_with_path(ms_timeout, &path).await?;
        #[cfg(windows)]
        if refuses_main_ipc_server(postfix, Config::holds_secrets(), conn.server_is_local_system())
        {
            bail!("the main IPC server is not the service");
        }
        Ok(conn)
    }
}

/// Whether a process refuses the IPC server it reached under `postfix`.
/// The window of an installed client (it does not hold the device's
/// secrets) talks on the main pipe to the service only, not to a process
/// that made an instance of its pipe name before the service started: what
/// it sends there can be a secret, a new permanent password, a 2FA secret
/// or a device token (L442), and what it takes from there includes the key
/// proof of a pairing or a join ([`pairing_proof`], L483).
#[cfg(any(windows, test))]
fn refuses_main_ipc_server(postfix: &str, holds_secrets: bool, server_is_service: bool) -> bool {
    postfix.is_empty() && !holds_secrets && !server_is_service
}

#[cfg(any(target_os = "linux", target_os = "macos"))]
pub async fn connect_for_uid(
    ms_timeout: u64,
    uid: u32,
    postfix: &str,
) -> ResultType<ConnectionTmpl<ConnClient>> {
    let path = Config::ipc_path_for_uid(uid, postfix);
    let conn = connect_with_path(ms_timeout, &path).await?;
    #[cfg(target_os = "macos")]
    if postfix.is_empty()
        && !authorize_user_server_process(conn.peer_uid(), conn.peer_pid(), uid)
    {
        bail!("Rejected user IPC peer for uid {}", uid);
    }
    Ok(conn)
}

#[cfg(target_os = "linux")]
#[tokio::main(flavor = "current_thread")]
pub async fn start_pa() {
    use crate::audio_service::AUDIO_DATA_SIZE_U8;

    match new_listener("_pa").await {
        Ok(mut incoming) => {
            loop {
                if let Some(result) = incoming.next().await {
                    match result {
                        Ok(stream) => {
                            let mut stream = Connection::new(stream);
                            let mut device: String = "".to_owned();
                            if let Some(Ok(Some(Data::Config((_, Some(x)))))) =
                                stream.next_timeout2(1000).await
                            {
                                device = x;
                            }
                            if !device.is_empty() {
                                device = crate::platform::linux::get_pa_source_name(&device);
                            }
                            if device.is_empty() {
                                device = crate::platform::linux::get_pa_monitor();
                            }
                            if device.is_empty() {
                                continue;
                            }
                            let spec = pulse::sample::Spec {
                                format: pulse::sample::Format::F32le,
                                channels: 2,
                                rate: crate::platform::PA_SAMPLE_RATE,
                            };
                            log::info!("pa monitor: {:?}", device);
                            // systemctl --user status pulseaudio.service
                            let mut buf: Vec<u8> = vec![0; AUDIO_DATA_SIZE_U8];
                            match psimple::Simple::new(
                                None,                             // Use the default server
                                &crate::get_app_name(),           // Our application’s name
                                pulse::stream::Direction::Record, // We want a record stream
                                Some(&device),                    // Use the default device
                                "record",                         // Description of our stream
                                &spec,                            // Our sample format
                                None,                             // Use default channel map
                                None, // Use default buffering attributes
                            ) {
                                Ok(s) => loop {
                                    if let Ok(_) = s.read(&mut buf) {
                                        let out =
                                            if buf.iter().filter(|x| **x != 0).next().is_none() {
                                                vec![]
                                            } else {
                                                buf.clone()
                                            };
                                        if let Err(err) = stream.send_raw(out.into()).await {
                                            log::error!("Failed to send audio data:{}", err);
                                            break;
                                        }
                                    }
                                },
                                Err(err) => {
                                    log::error!("Could not create simple pulse: {}", err);
                                }
                            }
                        }
                        Err(err) => {
                            log::error!("Couldn't get pa client: {:?}", err);
                        }
                    }
                }
            }
        }
        Err(err) => {
            log::error!("Failed to start pa ipc server: {}", err);
        }
    }
}

pub struct ConnectionTmpl<T> {
    inner: Framed<T, BytesCodec>,
}

pub type Connection = ConnectionTmpl<Conn>;

impl<T> ConnectionTmpl<T>
where
    T: AsyncRead + AsyncWrite + std::marker::Unpin,
{
    pub fn new(conn: T) -> Self {
        Self {
            inner: Framed::new(conn, BytesCodec::new()),
        }
    }

    pub async fn send(&mut self, data: &Data) -> ResultType<()> {
        let v = serde_json::to_vec(data)?;
        self.inner.send(bytes::Bytes::from(v)).await?;
        Ok(())
    }

    async fn send_config(&mut self, name: &str, value: String) -> ResultType<()> {
        self.send(&Data::Config((name.to_owned(), Some(value))))
            .await
    }

    pub async fn next_timeout(&mut self, ms_timeout: u64) -> ResultType<Option<Data>> {
        Ok(timeout(ms_timeout, self.next()).await??)
    }

    pub async fn next_timeout2(&mut self, ms_timeout: u64) -> Option<ResultType<Option<Data>>> {
        if let Ok(x) = timeout(ms_timeout, self.next()).await {
            Some(x)
        } else {
            None
        }
    }

    pub async fn next(&mut self) -> ResultType<Option<Data>> {
        match self.inner.next().await {
            Some(res) => {
                let bytes = res?;
                if let Ok(s) = std::str::from_utf8(&bytes) {
                    if let Ok(data) = serde_json::from_str::<Data>(s) {
                        return Ok(Some(data));
                    }
                }
                return Ok(None);
            }
            _ => {
                bail!("reset by the peer");
            }
        }
    }

    pub async fn send_raw(&mut self, data: Bytes) -> ResultType<()> {
        self.inner.send(data).await?;
        Ok(())
    }

    pub async fn next_raw(&mut self) -> ResultType<bytes::BytesMut> {
        match self.inner.next().await {
            Some(Ok(res)) => Ok(res),
            _ => {
                bail!("reset by the peer");
            }
        }
    }
}

#[tokio::main(flavor = "current_thread")]
pub async fn get_config(name: &str) -> ResultType<Option<String>> {
    get_config_async(name, 1_000).await
}

/// The server process's public key and key proof for the pairing request
/// or the join at `path`, None when no server process answers or it
/// refuses (an older one signs no join). In the window of an installed
/// client on Windows, [`connect`] refuses a main pipe whose server is not
/// the service ([`refuses_main_ipc_server`]), so a proof from any other
/// process is never used: the request then goes out without one.
pub async fn pairing_proof(path: &str) -> Option<(String, Vec<(String, String)>)> {
    let mut c = connect(1_000, "").await.ok()?;
    c.send(&Data::PairingProof((path.to_owned(), None)))
        .await
        .ok()?;
    match c.next_timeout(1_000).await {
        Ok(Some(Data::PairingProof((answered, Some(proof))))) if answered == path => Some(proof),
        _ => None,
    }
}

/// How long the window waits for the server process to make a sealed call:
/// the call may try plain TLS, native TLS and the TCP proxy, 12 s each.
const SEALED_CALL_TIMEOUT_MS: u64 = 60_000;

/// Has the server process make the sealed NeoDesk API call `method` `path`
/// with the account token `authorization` (common.rs
/// call_through_server_process). None when no server process answers; in
/// the window of an installed client on Windows that includes a main pipe
/// whose server is not the service ([`refuses_main_ipc_server`]).
pub async fn sealed_call(
    method: &str,
    path: &str,
    authorization: &str,
) -> Option<Result<String, String>> {
    let mut c = connect(1_000, "").await.ok()?;
    c.send(&Data::SealedCall(SealedCall::Ask {
        method: method.to_owned(),
        path: path.to_owned(),
        authorization: authorization.to_owned(),
    }))
    .await
    .ok()?;
    match c.next_timeout(SEALED_CALL_TIMEOUT_MS).await {
        Ok(Some(Data::SealedCall(SealedCall::Answer(answer)))) => Some(answer),
        _ => None,
    }
}

/// The `_service` channel on Linux and macOS. The person's server process
/// signs sessions and checks passwords as the person, so it gets the root
/// service's whole config, secrets included; a config it sends never
/// replaces the service's key pair, it only fills one the service does not
/// have yet (L442).
#[cfg(any(target_os = "linux", target_os = "macos"))]
async fn handle_service_sync(data: Data, stream: &mut Connection) {
    match data {
        Data::SyncConfig(Some(configs)) => {
            let (config, config2) = *configs;
            let _chk = CheckIfRestart::new();
            Config::set_from_user_server(config);
            Config2::set(config2);
            allow_err!(stream.send(&Data::SyncConfig(None)).await);
        }
        Data::SyncConfig(None) => {
            allow_err!(
                stream
                    .send(&Data::SyncConfig(Some(
                        (Config::get(), Config2::get()).into()
                    )))
                    .await
            );
        }
        _ => {}
    }
}

/// The holder's side of [`Data::HandOverSecrets`]: takes each secret only
/// when this process holds the device's secrets and has none of that kind
/// yet, and answers with its public key (base64). None in a process that
/// does not hold the secrets.
fn take_handed_over_secrets(secrets: config::ProfileSecrets) -> Option<String> {
    if !Config::holds_secrets() {
        return None;
    }
    if let Some(key_pair) = secrets.key_pair {
        if Config::adopt_key_pair_if_none(key_pair) {
            log::info!("Took the device key that a profile of an older version held");
        }
    }
    if let Some((storage, salt)) = secrets.permanent_password {
        if Config::adopt_permanent_password_if_none(&storage, &salt) {
            log::info!("Took the permanent password that a profile of an older version held");
        }
    }
    for (key, value) in secrets.options {
        let valid = key != keys::OPTION_2FA
            || crate::auth_2fa::get_2fa(Some(value.clone())).is_some();
        if valid && Config::adopt_secret_option_if_none(&key, &value) {
            log::info!("Took the {key} setting that a profile of an older version held");
        }
    }
    let (_, public_key) = Config::get_key_pair();
    (public_key.len() == hbb_common::sodiumoxide::crypto::sign::PUBLICKEYBYTES)
        .then(|| crate::encode64(public_key))
}

/// For a process that does not hold the device's secrets (the window of an
/// installed client on Windows), once `conn` reaches the service (L442).
/// The secrets an older version left in this profile (the key pair, the
/// stored permanent password, the 2FA secret) go to the service, which takes
/// each only when it has none of that kind yet, so an install keeps the
/// identity the server knows; the copies leave the profile once the service
/// answers that it holds the secrets. Without such copies this process only
/// learns the service's public key. Without an answer (an older service) the
/// copies stay until a later start.
pub async fn settle_device_secrets(conn: &mut ConnectionTmpl<ConnClient>) {
    if Config::holds_secrets() {
        return;
    }
    // Secrets go only to the service itself, and only its public key is
    // taken, not one from a process that made an instance of the same pipe
    // name before the service started
    #[cfg(windows)]
    if !conn.server_is_local_system() {
        log::warn!("The IPC server is not the service; this profile keeps its copies of the device's secrets for now");
        return;
    }
    let Some(secrets) = Config::secrets_in_files() else {
        if conn
            .send(&Data::Config((IPC_PUBLIC_KEY.to_owned(), None)))
            .await
            .is_ok()
        {
            if let Ok(Some(Data::Config((name, Some(public_key))))) =
                conn.next_timeout(1_000).await
            {
                if name == IPC_PUBLIC_KEY {
                    if let Ok(public_key) = crate::decode64(public_key) {
                        Config::set_holder_public_key(public_key);
                    }
                }
            }
        }
        return;
    };
    log::info!("This profile holds copies of the device's secrets: {secrets:?}");
    let mut held = None;
    if conn
        .send(&Data::HandOverSecrets(HandOver::Secrets(Box::new(secrets))))
        .await
        .is_ok()
    {
        if let Ok(Some(Data::HandOverSecrets(HandOver::Held(public_key)))) =
            conn.next_timeout(2_000).await
        {
            held = Some(public_key);
        }
    }
    after_hand_over(held);
}

/// Takes the secrets out of this profile once the holder answered with its
/// public key, and keeps that public key for this process. False, with the
/// profile as it was, without an answer.
pub(crate) fn after_hand_over(held: Option<String>) -> bool {
    let public_key = held
        .and_then(|public_key| crate::decode64(public_key).ok())
        .filter(|public_key| {
            public_key.len() == hbb_common::sodiumoxide::crypto::sign::PUBLICKEYBYTES
        });
    let Some(public_key) = public_key else {
        log::warn!("The service did not take this profile's copies of the device's secrets yet");
        return false;
    };
    if Config::remove_secrets_from_files() {
        log::info!("The service holds the device's secrets; this profile's copies are removed");
    }
    Config::set_holder_public_key(public_key);
    true
}

/// The device's public key: this process's own when it holds the key, else
/// the holder's, asked over IPC when this process has not learned it yet.
/// Empty when no holder answers.
pub fn device_public_key() -> Vec<u8> {
    if Config::holds_secrets() {
        return Config::get_key_pair().1;
    }
    if let Some(public_key) = Config::get_cached_pk().filter(|key| !key.is_empty()) {
        return public_key;
    }
    let public_key = get_config(IPC_PUBLIC_KEY)
        .ok()
        .flatten()
        .and_then(|public_key| crate::decode64(public_key).ok())
        .unwrap_or_default();
    Config::set_holder_public_key(public_key.clone());
    public_key
}

async fn get_config_async(name: &str, ms_timeout: u64) -> ResultType<Option<String>> {
    let mut c = connect(ms_timeout, "").await?;
    c.send(&Data::Config((name.to_owned(), None))).await?;
    if let Some(Data::Config((name2, value))) = c.next_timeout(ms_timeout).await? {
        if name == name2 {
            return Ok(value);
        }
    }
    return Ok(None);
}

pub async fn set_config_async(name: &str, value: String) -> ResultType<()> {
    let mut c = connect(1000, "").await?;
    c.send_config(name, value).await?;
    Ok(())
}

#[tokio::main(flavor = "current_thread")]
pub async fn set_data(data: &Data) -> ResultType<()> {
    set_data_async(data).await
}

async fn set_data_async(data: &Data) -> ResultType<()> {
    let mut c = connect(1000, "").await?;
    c.send(data).await?;
    Ok(())
}

#[tokio::main(flavor = "current_thread")]
pub async fn set_config(name: &str, value: String) -> ResultType<()> {
    set_config_async(name, value).await
}

pub fn update_temporary_password() -> ResultType<()> {
    set_config("temporary-password", "".to_owned())
}

pub fn is_permanent_password_set() -> bool {
    match get_config("permanent-password-set") {
        Ok(Some(v)) => {
            let v = v.trim();
            return v == "Y";
        }
        Ok(None) => {
            // No response/value (timeout).
        }
        Err(_) => {
            // Connection error.
        }
    }
    log::warn!("Failed to query permanent password state from daemon");
    false
}

pub fn is_permanent_password_preset() -> bool {
    if let Ok(Some(v)) = get_config("permanent-password-is-preset") {
        let v = v.trim();
        return v == "Y";
    }
    false
}

/// Whether 2FA is on, asked from the process that holds the 2FA secret.
/// None without an answer.
pub fn is_2fa_set() -> Option<bool> {
    match get_config(IPC_2FA_SET) {
        Ok(Some(v)) => Some(v.trim() == "Y"),
        _ => None,
    }
}

/// Turns 2FA on with `value` (the secret, as auth_2fa stores it) or off
/// with an empty value, in the process that holds the device's secrets
/// (L442). True once that process took it.
#[tokio::main(flavor = "current_thread")]
pub async fn set_2fa(value: String) -> ResultType<bool> {
    let ms_timeout = 1_000;
    let mut c = connect(ms_timeout, "").await?;
    c.send_config(keys::OPTION_2FA, value).await?;
    if let Some(Data::Config((name, Some(v)))) = c.next_timeout(ms_timeout).await? {
        if name == keys::OPTION_2FA {
            return Ok(v.trim() == "Y");
        }
    }
    Ok(false)
}

pub fn get_fingerprint() -> String {
    get_config("fingerprint")
        .unwrap_or_default()
        .unwrap_or_default()
}

pub fn set_permanent_password(v: String) -> ResultType<()> {
    if Config::is_disable_change_permanent_password() {
        bail!("Changing permanent password is disabled");
    }
    if set_permanent_password_with_ack(v)? {
        Ok(())
    } else {
        bail!("Changing permanent password was rejected by daemon");
    }
}

#[tokio::main(flavor = "current_thread")]
pub async fn set_permanent_password_with_ack(v: String) -> ResultType<bool> {
    set_permanent_password_with_ack_async(v).await
}

async fn set_permanent_password_with_ack_async(v: String) -> ResultType<bool> {
    // The daemon ACK/NACK is expected quickly since it applies the config in-process.
    let ms_timeout = 1_000;
    let mut c = connect(ms_timeout, "").await?;
    c.send_config("permanent-password", v).await?;
    if let Some(Data::Config((name2, Some(v)))) = c.next_timeout(ms_timeout).await? {
        if name2 == "permanent-password" {
            // The stored password stays in the daemon (L442)
            return Ok(v.trim() == "Y");
        }
    }
    Ok(false)
}

#[cfg(feature = "flutter")]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn set_unlock_pin(v: String, translate: bool) -> ResultType<()> {
    let v = v.trim().to_owned();
    let min_len = 4;
    let max_len = crate::ui_interface::max_encrypt_len();
    let len = v.chars().count();
    if !v.is_empty() {
        if len < min_len {
            let err = if translate {
                crate::lang::translate(
                    "Requires at least {".to_string() + &format!("{min_len}") + "} characters",
                )
            } else {
                // Sometimes, translated can't show normally in command line
                format!("Requires at least {} characters", min_len)
            };
            bail!(err);
        }
        if len > max_len {
            bail!("No more than {max_len} characters");
        }
    }
    Config::set_unlock_pin(&v);
    set_config("unlock-pin", v)
}

#[cfg(feature = "flutter")]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn get_unlock_pin() -> String {
    if let Ok(Some(v)) = get_config("unlock-pin") {
        Config::set_unlock_pin(&v);
        v
    } else {
        Config::get_unlock_pin()
    }
}

#[cfg(feature = "flutter")]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn get_trusted_devices() -> String {
    if let Ok(Some(v)) = get_config("trusted-devices") {
        v
    } else {
        Config::get_trusted_devices_json()
    }
}

#[cfg(feature = "flutter")]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn remove_trusted_devices(hwids: Vec<Bytes>) {
    Config::remove_trusted_devices(&hwids);
    allow_err!(set_data(&Data::RemoveTrustedDevices(hwids)));
}

#[cfg(feature = "flutter")]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn clear_trusted_devices() {
    Config::clear_trusted_devices();
    allow_err!(set_data(&Data::ClearTrustedDevices));
}

pub fn get_id() -> String {
    // An empty id may come from a process that took over the main IPC with a
    // config scope that has no id yet (e.g. a user GUI that became the server
    // while the installed service was restarting). Treat it as no answer,
    // otherwise the empty id is adopted below and wipes the local one.
    if let Ok(Some(v)) = get_config("id") {
        if !v.is_empty() {
            // update salt also, so that next time reinstallation not causing first-time auto-login failure
            if let Ok(Some(v2)) = get_config("salt") {
                Config::set_salt(&v2);
            }
            if v != Config::get_id() {
                Config::set_key_confirmed(false);
                Config::set_id(&v);
            }
            return v;
        }
    }
    Config::get_id()
}

pub async fn get_rendezvous_server(ms_timeout: u64) -> (String, Vec<String>) {
    if let Ok(Some(v)) = get_config_async("rendezvous_server", ms_timeout).await {
        let mut urls = v.split(",");
        let a = urls.next().unwrap_or_default().to_owned();
        let b: Vec<String> = urls.map(|x| x.to_owned()).collect();
        (a, b)
    } else {
        (
            Config::get_rendezvous_server(),
            Config::get_rendezvous_servers(),
        )
    }
}

async fn get_options_(ms_timeout: u64) -> ResultType<HashMap<String, String>> {
    let mut c = connect(ms_timeout, "").await?;
    c.send(&Data::Options(None)).await?;
    if let Some(Data::Options(Some(value))) = c.next_timeout(ms_timeout).await? {
        Config::set_options_from_other_process(value.clone());
        Ok(value)
    } else {
        Ok(Config::get_options())
    }
}

pub async fn get_options_async() -> HashMap<String, String> {
    get_options_(1000).await.unwrap_or(Config::get_options())
}

#[tokio::main(flavor = "current_thread")]
pub async fn get_options() -> HashMap<String, String> {
    get_options_async().await
}

pub async fn get_option_async(key: &str) -> String {
    if let Some(v) = get_options_async().await.get(key) {
        v.clone()
    } else {
        "".to_owned()
    }
}

pub fn set_option(key: &str, value: &str) {
    let mut options = get_options();
    if value.is_empty() {
        options.remove(key);
    } else {
        options.insert(key.to_owned(), value.to_owned());
    }
    set_options(options).ok();
}

#[tokio::main(flavor = "current_thread")]
pub async fn set_options(value: HashMap<String, String>) -> ResultType<()> {
    let _nat = CheckTestNatType::new();
    if let Ok(mut c) = connect(1000, "").await {
        c.send(&Data::Options(Some(value.clone()))).await?;
        // do not put below before connect, because we need to check should_exit
        c.next_timeout(1000).await.ok();
    }
    Config::set_options_from_other_process(value);
    Ok(())
}

/// For the CLI, a process that just loaded the config. With no `--server` up to apply the change,
/// as right after an install, nothing else tells the service.
#[cfg(all(target_os = "linux", feature = "drm"))]
#[tokio::main(flavor = "current_thread")]
pub async fn sync_drm_capture_to_service_blocking(was_on: bool) {
    crate::platform::linux::sync_drm_capture_to_service(was_on).await
}

#[inline]
async fn get_nat_type_(ms_timeout: u64) -> ResultType<i32> {
    let mut c = connect(ms_timeout, "").await?;
    c.send(&Data::NatType(None)).await?;
    if let Some(Data::NatType(Some(value))) = c.next_timeout(ms_timeout).await? {
        Config::set_nat_type(value);
        Ok(value)
    } else {
        Ok(Config::get_nat_type())
    }
}

pub async fn get_nat_type(ms_timeout: u64) -> i32 {
    get_nat_type_(ms_timeout)
        .await
        .unwrap_or(Config::get_nat_type())
}

pub async fn get_rendezvous_servers(ms_timeout: u64) -> Vec<String> {
    if let Ok(Some(v)) = get_config_async("rendezvous_servers", ms_timeout).await {
        return v.split(',').map(|x| x.to_owned()).collect();
    }
    return Config::get_rendezvous_servers();
}

#[inline]
async fn get_socks_(ms_timeout: u64) -> ResultType<Option<config::Socks5Server>> {
    let mut c = connect(ms_timeout, "").await?;
    c.send(&Data::Socks(None)).await?;
    if let Some(Data::Socks(value)) = c.next_timeout(ms_timeout).await? {
        Config::set_socks(value.clone());
        Ok(value)
    } else {
        Ok(Config::get_socks())
    }
}

pub async fn get_socks_async(ms_timeout: u64) -> Option<config::Socks5Server> {
    get_socks_(ms_timeout).await.unwrap_or(Config::get_socks())
}

#[tokio::main(flavor = "current_thread")]
pub async fn get_socks() -> Option<config::Socks5Server> {
    get_socks_async(1_000).await
}

#[tokio::main(flavor = "current_thread")]
pub async fn set_socks(value: config::Socks5Server) -> ResultType<()> {
    let _nat = CheckTestNatType::new();
    Config::set_socks(if value.proxy.is_empty() {
        None
    } else {
        Some(value.clone())
    });
    connect(1_000, "")
        .await?
        .send(&Data::Socks(Some(value)))
        .await?;
    Ok(())
}

async fn get_socks_ws_(ms_timeout: u64) -> ResultType<(Option<config::Socks5Server>, String)> {
    let mut c = connect(ms_timeout, "").await?;
    c.send(&Data::SocksWs(None)).await?;
    if let Some(Data::SocksWs(Some(value))) = c.next_timeout(ms_timeout).await? {
        Config::set_socks(value.0.clone());
        Config::set_option(OPTION_ALLOW_WEBSOCKET.to_string(), value.1.clone());
        Ok(*value)
    } else {
        Ok((
            Config::get_socks(),
            Config::get_option(OPTION_ALLOW_WEBSOCKET),
        ))
    }
}

#[tokio::main(flavor = "current_thread")]
pub async fn get_socks_ws() -> (Option<config::Socks5Server>, String) {
    get_socks_ws_(1_000).await.unwrap_or((
        Config::get_socks(),
        Config::get_option(OPTION_ALLOW_WEBSOCKET),
    ))
}

pub fn get_proxy_status() -> bool {
    Config::get_socks().is_some()
}
#[tokio::main(flavor = "current_thread")]
pub async fn test_rendezvous_server() -> ResultType<()> {
    let mut c = connect(1000, "").await?;
    c.send(&Data::TestRendezvousServer).await?;
    Ok(())
}

#[tokio::main(flavor = "current_thread")]
pub async fn notify_deployed() -> ResultType<()> {
    let mut c = connect(1000, "").await?;
    c.send(&Data::Deployed).await?;
    Ok(())
}

#[tokio::main(flavor = "current_thread")]
pub async fn send_url_scheme(url: String) -> ResultType<()> {
    connect(1_000, "_url")
        .await?
        .send(&Data::UrlLink(url))
        .await?;
    Ok(())
}

// Emit `close` events to ipc.
pub fn close_all_instances() -> ResultType<bool> {
    match crate::ipc::send_url_scheme(IPC_ACTION_CLOSE.to_owned()) {
        Ok(_) => Ok(true),
        Err(err) => Err(err),
    }
}

#[cfg(windows)]
#[tokio::main(flavor = "current_thread")]
pub async fn connect_to_user_session(usid: Option<u32>) -> ResultType<()> {
    let mut stream = crate::ipc::connect_service(1000).await?;
    timeout(1000, stream.send(&crate::ipc::Data::UserSid(usid))).await??;
    Ok(())
}

#[tokio::main(flavor = "current_thread")]
pub async fn notify_server_to_check_hwcodec() -> ResultType<()> {
    connect(1_000, "").await?.send(&&Data::CheckHwcodec).await?;
    Ok(())
}

#[cfg(target_os = "windows")]
pub async fn get_port_forward_session_count(ms_timeout: u64) -> ResultType<usize> {
    let mut c = connect(ms_timeout, "").await?;
    c.send(&Data::PortForwardSessionCount(None)).await?;
    if let Some(Data::PortForwardSessionCount(Some(count))) = c.next_timeout(ms_timeout).await? {
        return Ok(count);
    }
    bail!("Failed to get port forward session count");
}

#[cfg(feature = "hwcodec")]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
#[tokio::main(flavor = "current_thread")]
pub async fn get_hwcodec_config_from_server() -> ResultType<()> {
    if !scrap::codec::enable_hwcodec_option() || scrap::hwcodec::HwCodecConfig::already_set() {
        return Ok(());
    }
    let mut c = connect(50, "").await?;
    c.send(&Data::HwCodecConfig(None)).await?;
    if let Some(Data::HwCodecConfig(v)) = c.next_timeout(50).await? {
        match v {
            Some(v) => {
                scrap::hwcodec::HwCodecConfig::set(v);
                return Ok(());
            }
            None => {
                bail!("hwcodec config is none");
            }
        }
    }
    bail!("failed to get hwcodec config");
}

#[cfg(feature = "hwcodec")]
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn client_get_hwcodec_config_thread(wait_sec: u64) {
    static ONCE: std::sync::Once = std::sync::Once::new();
    if !crate::platform::is_installed()
        || !scrap::codec::enable_hwcodec_option()
        || scrap::hwcodec::HwCodecConfig::already_set()
    {
        return;
    }
    ONCE.call_once(move || {
        std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_secs(1));
            let mut intervals: Vec<u64> = vec![wait_sec, 3, 3, 6, 9];
            for i in intervals.drain(..) {
                if i > 0 {
                    std::thread::sleep(std::time::Duration::from_secs(i));
                }
                if get_hwcodec_config_from_server().is_ok() {
                    break;
                }
            }
        });
    });
}

#[cfg(feature = "hwcodec")]
#[tokio::main(flavor = "current_thread")]
pub async fn hwcodec_process() {
    let s = scrap::hwcodec::check_available_hwcodec();
    for _ in 0..5 {
        match crate::ipc::connect(1000, "").await {
            Ok(mut conn) => {
                match conn
                    .send(&crate::ipc::Data::HwCodecConfig(Some(s.clone())))
                    .await
                {
                    Ok(()) => {
                        log::info!("send ok");
                        break;
                    }
                    Err(e) => {
                        log::error!("send failed: {e:?}");
                    }
                }
            }
            Err(e) => {
                log::error!("connect failed: {e:?}");
            }
        }
        std::thread::sleep(std::time::Duration::from_secs(1));
    }
}

#[tokio::main(flavor = "current_thread")]
pub async fn get_wayland_screencast_restore_token(key: String) -> ResultType<String> {
    let v = handle_wayland_screencast_restore_token(key, "get".to_owned()).await?;
    Ok(v.unwrap_or_default())
}

#[tokio::main(flavor = "current_thread")]
pub async fn clear_wayland_screencast_restore_token(key: String) -> ResultType<bool> {
    if let Some(v) = handle_wayland_screencast_restore_token(key, "clear".to_owned()).await? {
        return Ok(v.is_empty());
    }
    return Ok(false);
}

#[cfg(all(
    feature = "flutter",
    not(any(target_os = "android", target_os = "ios"))
))]
#[tokio::main(flavor = "current_thread")]
pub async fn update_controlling_session_count(count: usize) -> ResultType<()> {
    let mut c = connect(1000, "").await?;
    c.send(&Data::ControllingSessionCount(count)).await?;
    Ok(())
}

#[cfg(target_os = "linux")]
#[tokio::main(flavor = "current_thread")]
pub async fn get_terminal_session_count() -> ResultType<usize> {
    let timeout_ms = 1_000;
    let effective_uid = unsafe { hbb_common::libc::geteuid() as u32 };
    let candidate_uids = terminal_count_candidate_uids(effective_uid);
    let mut last_err: Option<anyhow::Error> = None;
    for candidate_uid in candidate_uids {
        let socket_path = Config::ipc_path_for_uid(candidate_uid, "");
        let connect_result = timeout(timeout_ms, Endpoint::connect(&socket_path))
            .await
            .map_err(|err| {
                anyhow::anyhow!(
                    "Timeout connecting to terminal ipc at {}: {}",
                    socket_path,
                    err
                )
            });
        let connection = match connect_result {
            Ok(Ok(connection)) => connection,
            Ok(Err(err)) => {
                last_err = Some(anyhow::anyhow!(
                    "Failed to connect to terminal ipc at {}: {}",
                    socket_path,
                    err
                ));
                continue;
            }
            Err(err) => {
                last_err = Some(err);
                continue;
            }
        };
        let mut ipc_conn = ConnectionTmpl::new(connection);
        if let Err(err) = ipc_conn.send(&Data::TerminalSessionCount(0)).await {
            last_err = Some(anyhow::anyhow!(
                "Failed to request terminal session count via ipc at {}: {}",
                socket_path,
                err
            ));
            continue;
        }
        match ipc_conn.next_timeout(timeout_ms).await {
            Ok(Some(Data::TerminalSessionCount(session_count))) => {
                return Ok(session_count);
            }
            Ok(None) => {
                last_err = Some(anyhow::anyhow!(
                    "Invalid response when requesting terminal session count via ipc at {}",
                    socket_path
                ));
            }
            Ok(other) => {
                last_err = Some(anyhow::anyhow!(
                    "Unexpected response when requesting terminal session count via ipc at {}: {:?}",
                    socket_path,
                    other.map(|v| std::mem::discriminant(&v))
                ));
            }
            Err(err) => {
                last_err = Some(anyhow::anyhow!(
                    "Failed to read terminal session count via ipc at {}: {}",
                    socket_path,
                    err
                ));
            }
        }
    }
    if let Some(err) = last_err {
        Err(err.into())
    } else {
        Ok(0)
    }
}

async fn handle_wayland_screencast_restore_token(
    key: String,
    value: String,
) -> ResultType<Option<String>> {
    let ms_timeout = 1_000;
    let mut c = connect(ms_timeout, "").await?;
    c.send(&Data::WaylandScreencastRestoreToken((key, value)))
        .await?;
    if let Some(Data::WaylandScreencastRestoreToken((_key, v))) = c.next_timeout(ms_timeout).await?
    {
        return Ok(Some(v));
    }
    return Ok(None);
}

#[tokio::main(flavor = "current_thread")]
pub async fn set_install_option(k: String, v: String) -> ResultType<()> {
    if let Ok(mut c) = connect(1000, "").await {
        c.send(&&Data::InstallOption(Some((k, v)))).await?;
        // do not put below before connect, because we need to check should_exit
        c.next_timeout(1000).await.ok();
    }
    Ok(())
}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn the_service_pipes_of_an_installed_client_get_protected_names() {
        assert_eq!(
            protected_pipe_path(r"\\.\pipe\neodesk\query"),
            r"\\.\pipe\ProtectedPrefix\Administrators\neodesk\query"
        );
        assert_eq!(
            protected_pipe_path(r"\\.\pipe\neodesk\query_service"),
            r"\\.\pipe\ProtectedPrefix\Administrators\neodesk\query_service"
        );
    }

    #[test]
    fn verify_ffi_enum_data_size() {
        println!("{}", std::mem::size_of::<Data>());
        assert!(std::mem::size_of::<Data>() <= 120);
    }

    #[cfg(any(target_os = "linux", target_os = "macos"))]
    #[test]
    fn test_service_ipc_path_is_shared_across_uids() {
        assert_eq!(
            Config::ipc_path_for_uid(0, crate::POSTFIX_SERVICE),
            Config::ipc_path_for_uid(501, crate::POSTFIX_SERVICE)
        );
    }

    #[cfg(any(target_os = "linux", target_os = "macos"))]
    #[test]
    fn test_ipc_path_differs_by_uid_for_cm() {
        let effective_uid = unsafe { hbb_common::libc::geteuid() as u32 };
        let other_uid = effective_uid.saturating_add(1);
        let postfix = "_cm";

        // Default connect path targets the current effective uid.
        assert_eq!(
            Config::ipc_path(postfix),
            Config::ipc_path_for_uid(effective_uid, postfix)
        );
        // A different uid yields a different socket path - this is the root cause of the
        // cross-user regression when root spawns a user process but still connects as uid 0.
        assert_ne!(
            Config::ipc_path(postfix),
            Config::ipc_path_for_uid(other_uid, postfix)
        );
    }

    #[cfg(any(target_os = "linux", target_os = "macos"))]
    #[test]
    fn test_select_server_uid_uses_active_uid_when_no_server_found() {
        assert_eq!(
            select_server_uid_for_user_main_ipc(&[], Some(501), false).unwrap(),
            501
        );
    }

    #[cfg(any(target_os = "linux", target_os = "macos"))]
    #[test]
    fn test_select_server_uid_uses_single_server_uid() {
        assert_eq!(
            select_server_uid_for_user_main_ipc(&[501], None, false).unwrap(),
            501
        );
    }

    #[cfg(any(target_os = "linux", target_os = "macos"))]
    #[test]
    fn test_select_server_uid_prefers_active_uid_with_multiple_servers() {
        assert_eq!(
            select_server_uid_for_user_main_ipc(&[0, 501], Some(501), false).unwrap(),
            501
        );
    }

    #[cfg(any(target_os = "linux", target_os = "macos"))]
    #[test]
    fn test_select_server_uid_prefers_root_on_wayland_login_screen() {
        assert_eq!(
            select_server_uid_for_user_main_ipc(&[0, 501], Some(501), true).unwrap(),
            0
        );
    }

    #[cfg(any(target_os = "linux", target_os = "macos"))]
    #[test]
    fn test_select_server_uid_fails_when_multiple_servers_are_ambiguous() {
        assert!(select_server_uid_for_user_main_ipc(&[501, 502], None, false).is_err());
    }

    /// The upgrade window: an old root service is still streaming when a new `--server` starts,
    /// and its DrmCursor carries no `hot_measured` at all. Read as `false` the consumer would
    /// discard a hotspot the producer did measure and re-infer one from the bitmap, which moves
    /// the cursor on a rotated display until the old process is replaced. `bool::default()` is
    /// the wrong default here; the right one preserves what the old protocol meant.
    #[cfg(all(target_os = "linux", feature = "drm"))]
    #[test]
    fn a_drm_cursor_without_provenance_keeps_the_hotspot_the_producer_sent() {
        // `Data` is adjacently tagged (`tag = "t", content = "c"`), so this is the real shape on
        // the socket, not a simplified one.
        let legacy =
            r#"{"t":"DrmCursor","c":{"id":7,"width":24,"height":24,"hotx":12,"hoty":11}}"#;
        let msg: Data = serde_json::from_str(legacy).expect("legacy DrmCursor must deserialize");
        match msg {
            Data::DrmCursor {
                hotx,
                hoty,
                hot_measured,
                ..
            } => {
                assert_eq!((hotx, hoty), (12, 11));
                assert!(
                    hot_measured,
                    "a message with no provenance field must be treated as the old protocol did, \
                     i.e. use the hotspot as sent, not re-infer it"
                );
            }
            other => panic!("expected DrmCursor, got {other:?}"),
        }

        // And a NEW producer that really wants re-inference says so, which serializes: the
        // default must not swallow an explicit false.
        let modern = r#"{"t":"DrmCursor","c":{"id":7,"width":24,"height":24,"hotx":0,"hoty":0,"hot_measured":false}}"#;
        match serde_json::from_str::<Data>(modern).expect("modern DrmCursor must deserialize") {
            Data::DrmCursor { hot_measured, .. } => assert!(!hot_measured),
            other => panic!("expected DrmCursor, got {other:?}"),
        }
    }

    /// A frame from a producer that predates the plane rotation reads as `None`, in the cpu frame
    /// header and in the dma-buf descriptor: the root service and the `--server` are upgraded
    /// separately, and `None` keeps the previous rule.
    #[cfg(all(target_os = "linux", feature = "drm"))]
    #[test]
    fn a_frame_without_a_plane_rotation_reads_as_none() {
        let legacy = r#"{"t":"DrmFrame","c":{"width":8,"height":8}}"#;
        match serde_json::from_str::<Data>(legacy).expect("legacy DrmFrame must deserialize") {
            Data::DrmFrame { plane_rotation, .. } => assert_eq!(plane_rotation, None),
            other => panic!("expected DrmFrame, got {other:?}"),
        }
        let modern = r#"{"t":"DrmFrame","c":{"width":8,"height":8,"plane_rotation":4}}"#;
        match serde_json::from_str::<Data>(modern).expect("modern DrmFrame must deserialize") {
            Data::DrmFrame { plane_rotation, .. } => assert_eq!(plane_rotation, Some(4)),
            other => panic!("expected DrmFrame, got {other:?}"),
        }
        let desc = DmabufDesc {
            buffer_id: 0,
            width: 4,
            height: 4,
            format: 0,
            modifier: 0,
            fb_id: 0,
            num_planes: 1,
            offsets: [0; 4],
            pitches: [16, 0, 0, 0],
            hdr_eotf: 0,
            hdr_max_nits: 0,
            has_fd: false,
            plane_rotation: Some(4),
            cursor_pos: None,
        };
        let mut value = serde_json::to_value(&desc).unwrap();
        assert!(value.as_object_mut().unwrap().remove("plane_rotation").is_some());
        let legacy: DmabufDesc =
            serde_json::from_value(value).expect("legacy DmabufDesc must deserialize");
        assert_eq!(legacy.plane_rotation, None);
    }

    /// A frame header from a producer that predates the cursor plane position reads as `None`;
    /// a producer that sends one is read back exactly. A pin, not a gate: the consumer only ever
    /// measures against `Some`.
    #[cfg(all(target_os = "linux", feature = "drm"))]
    #[test]
    fn a_drm_frame_without_a_cursor_position_reads_as_none() {
        let legacy = r#"{"t":"DrmFrame","c":{"width":8,"height":8}}"#;
        match serde_json::from_str::<Data>(legacy).expect("legacy DrmFrame must deserialize") {
            Data::DrmFrame {
                width,
                height,
                cursor_pos,
                ..
            } => {
                assert_eq!((width, height), (8, 8));
                assert_eq!(cursor_pos, None);
            }
            other => panic!("expected DrmFrame, got {other:?}"),
        }
        let modern = r#"{"t":"DrmFrame","c":{"width":8,"height":8,"cursor_pos":[3,4]}}"#;
        match serde_json::from_str::<Data>(modern).expect("modern DrmFrame must deserialize") {
            Data::DrmFrame { cursor_pos, .. } => assert_eq!(cursor_pos, Some((3, 4))),
            other => panic!("expected DrmFrame, got {other:?}"),
        }
    }
}

/// Tests of how the device's secrets (the key pair, the stored permanent
/// password, the 2FA secret) stay in the process that holds them (L442).
/// They change this process's config and key state, so they take
/// [`DEVICE_KEY_TEST_LOCK`]. No test prints a secret.
#[cfg(test)]
pub(crate) mod device_key_tests {
    use super::*;
    use std::time::Duration;

    pub(crate) static DEVICE_KEY_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    /// Puts this process's config files and config back as they were.
    pub(crate) struct ConfigFilesGuard {
        files: Vec<(std::path::PathBuf, Option<Vec<u8>>)>,
        config: Config,
        config2: Config2,
    }

    impl ConfigFilesGuard {
        pub(crate) fn new() -> Self {
            Self {
                files: [Config::file(), Config2::file()]
                    .into_iter()
                    .map(|path| {
                        let content = std::fs::read(&path).ok();
                        (path, content)
                    })
                    .collect(),
                config: Config::get(),
                config2: Config2::get(),
            }
        }
    }

    impl Drop for ConfigFilesGuard {
        fn drop(&mut self) {
            Config::set(self.config.clone());
            Config2::set(self.config2.clone());
            for (path, content) in &self.files {
                match content {
                    Some(content) => {
                        std::fs::write(path, content).ok();
                    }
                    None => {
                        std::fs::remove_file(path).ok();
                    }
                }
            }
        }
    }

    /// The forms a secret could take in an IPC answer: serde writes bytes as
    /// a list of numbers; base64 and hex for good measure. The seed half of
    /// a key alone counts too.
    pub(crate) fn reveals(text: &[u8], secret: &[u8]) -> bool {
        let text = String::from_utf8_lossy(text);
        [secret, &secret[..secret.len().min(32)]]
            .iter()
            .any(|part| {
                let numbers = part
                    .iter()
                    .map(|b| b.to_string())
                    .collect::<Vec<_>>()
                    .join(",");
                text.contains(&numbers)
                    || text.contains(&crate::encode64(part))
                    || text.contains(&hex::encode(part))
            })
    }

    /// Whether `text` carries the stored permanent password or the 2FA
    /// secret, stored or plain.
    pub(crate) fn reveals_any(text: &[u8], secrets: &TestSecrets) -> bool {
        reveals(text, &secrets.key_pair.0)
            || String::from_utf8_lossy(text).contains(&secrets.password.0)
            || reveals(text, &secrets.two_fa_plain)
            || reveals(text, &stored_2fa_secret(&secrets.two_fa))
    }

    /// The secret bytes inside a 2FA value as auth_2fa stores it (encrypted).
    fn stored_2fa_secret(two_fa: &str) -> Vec<u8> {
        serde_json::from_str::<crate::auth_2fa::TOTPInfo>(two_fa)
            .map(|info| info.secret)
            .unwrap_or_default()
    }

    /// Runs this process's IPC server under `postfix` on a thread of its own.
    pub(crate) fn start_test_listener(postfix: &'static str) {
        std::thread::spawn(move || {
            let _ = start(postfix);
        });
        for _ in 0..50 {
            if ask(postfix, &[]).is_some() {
                return;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        panic!("the test IPC server did not start");
    }

    /// Sends each request as raw bytes and collects what came back within a
    /// second each. None when the server cannot be reached.
    #[tokio::main(flavor = "current_thread")]
    pub(crate) async fn ask(postfix: &str, requests: &[Vec<u8>]) -> Option<Vec<Vec<u8>>> {
        let mut c = connect(1000, postfix).await.ok()?;
        let mut answers = Vec::new();
        for request in requests {
            c.send_raw(request.clone().into()).await.ok()?;
            if let Ok(Ok(answer)) = timeout(1000, c.next_raw()).await {
                answers.push(answer.to_vec());
            }
        }
        Some(answers)
    }

    fn request(data: &Data) -> Vec<u8> {
        serde_json::to_vec(data).unwrap()
    }

    fn answer_of(answer: Option<&Vec<u8>>) -> Option<Data> {
        answer.and_then(|answer| serde_json::from_slice::<Data>(answer).ok())
    }

    /// This process's key pair as the holder makes or loads it, once it is
    /// stored.
    pub(crate) fn own_key_pair() -> (Vec<u8>, Vec<u8>) {
        let key_pair = Config::get_key_pair();
        // A key made now is stored by a thread of its own
        std::thread::sleep(Duration::from_millis(300));
        key_pair
    }

    /// A key pair made for the test.
    pub(crate) fn test_key_pair() -> (Vec<u8>, Vec<u8>) {
        let (pk, sk) = hbb_common::sodiumoxide::crypto::sign::gen_keypair();
        (sk.0.to_vec(), pk.0.to_vec())
    }

    /// A 2FA value as auth_2fa stores it, and its secret in plain.
    pub(crate) fn test_2fa() -> (String, Vec<u8>) {
        let secret = hbb_common::sodiumoxide::randombytes::randombytes(20);
        let info = crate::auth_2fa::TOTPInfo {
            name: "123456789".to_owned(),
            secret: secret.clone(),
            digits: 6,
            created_at: 0,
        };
        (info.into_string().unwrap(), secret)
    }

    /// A stored permanent password and its salt as the holder makes them;
    /// this process's own password stays as it was.
    pub(crate) fn test_permanent_password(password: &str) -> (String, String) {
        let own = Config::get_local_permanent_password_storage_and_salt();
        assert!(Config::set_permanent_password(password));
        let made = Config::get_local_permanent_password_storage_and_salt();
        if own.0.is_empty() {
            Config::set_permanent_password("");
        } else {
            Config::set_permanent_password_storage_for_sync(&own.0, &own.1).unwrap();
        }
        made
    }

    /// The secrets of one device for a test.
    pub(crate) struct TestSecrets {
        pub(crate) key_pair: (Vec<u8>, Vec<u8>),
        pub(crate) password: (String, String),
        pub(crate) two_fa: String,
        pub(crate) two_fa_plain: Vec<u8>,
    }

    impl TestSecrets {
        pub(crate) fn new(password: &str) -> Self {
            let (two_fa, two_fa_plain) = test_2fa();
            Self {
                key_pair: test_key_pair(),
                password: test_permanent_password(password),
                two_fa,
                two_fa_plain,
            }
        }

        /// Makes these the secrets this process (the service in a test)
        /// holds, all but the key pair, which stays [`own_key_pair`].
        pub(crate) fn hold(mut self) -> Self {
            self.key_pair = own_key_pair();
            Config::set_permanent_password("");
            Config::set_permanent_password_storage_for_sync(&self.password.0, &self.password.1)
                .unwrap();
            Config::set_option(keys::OPTION_2FA.to_owned(), self.two_fa.clone());
            self
        }

        pub(crate) fn handed(&self) -> config::ProfileSecrets {
            let mut options = HashMap::new();
            options.insert(keys::OPTION_2FA.to_owned(), self.two_fa.clone());
            config::ProfileSecrets {
                key_pair: Some(self.key_pair.clone()),
                permanent_password: Some(self.password.clone()),
                options,
            }
        }
    }

    /// Writes `key_pair` into this process's config file, the way an older
    /// version left it in the person's profile.
    pub(crate) fn write_key_pair_to_file(key_pair: &(Vec<u8>, Vec<u8>)) {
        let config = hbb_common::config::load_path::<Config>(Config::file());
        let mut value = serde_json::to_value(config).unwrap();
        value["key_pair"] = serde_json::json!([key_pair.0, key_pair.1]);
        let config: Config = serde_json::from_value(value).unwrap();
        hbb_common::config::store_path(Config::file(), config).unwrap();
    }

    /// Writes all of `secrets` into this process's config files, the way an
    /// older version left them in the person's profile.
    pub(crate) fn write_secrets_to_files(secrets: &TestSecrets) {
        let config = hbb_common::config::load_path::<Config>(Config::file());
        let mut value = serde_json::to_value(config).unwrap();
        value["key_pair"] = serde_json::json!([secrets.key_pair.0, secrets.key_pair.1]);
        value["password"] = serde_json::json!(secrets.password.0);
        value["salt"] = serde_json::json!(secrets.password.1);
        let config: Config = serde_json::from_value(value).unwrap();
        hbb_common::config::store_path(Config::file(), config).unwrap();
        let mut config2 = hbb_common::config::load_path::<Config2>(Config2::file());
        config2
            .options
            .insert(keys::OPTION_2FA.to_owned(), secrets.two_fa.clone());
        hbb_common::config::store_path(Config2::file(), config2).unwrap();
    }

    /// The key pair in this process's config file, as JSON.
    pub(crate) fn key_pair_of_file() -> Vec<u8> {
        let config = hbb_common::config::load_path::<Config>(Config::file());
        serde_json::to_vec(&serde_json::to_value(config).unwrap()["key_pair"]).unwrap()
    }

    /// This process's config files, as JSON.
    fn files() -> Vec<u8> {
        let config = hbb_common::config::load_path::<Config>(Config::file());
        let config2 = hbb_common::config::load_path::<Config2>(Config2::file());
        serde_json::to_vec(&(config, config2)).unwrap()
    }

    /// Makes this test process one that does not hold the device's secrets,
    /// the way the window of an installed client runs on Windows, and the
    /// holder again afterwards.
    pub(crate) struct NotSecretsHolder;

    impl NotSecretsHolder {
        pub(crate) fn new() -> Self {
            Config::set_holds_secrets(false);
            Self
        }
    }

    impl Drop for NotSecretsHolder {
        fn drop(&mut self) {
            Config::set_holds_secrets(true);
        }
    }

    fn lock() -> std::sync::MutexGuard<'static, ()> {
        DEVICE_KEY_TEST_LOCK
            .lock()
            .unwrap_or_else(|err| err.into_inner())
    }

    #[cfg(any(target_os = "linux", target_os = "macos"))]
    #[test]
    fn the_service_keeps_its_secrets_and_answers_a_hand_over_with_its_public_key() {
        let _lock = lock();
        let _files = ConfigFilesGuard::new();
        let handed = TestSecrets::new("handed-password");
        let own = TestSecrets::new("own-password").hold();
        start_test_listener("_l442_handover");

        let answers = ask(
            "_l442_handover",
            &[request(&Data::HandOverSecrets(HandOver::Secrets(Box::new(
                handed.handed(),
            ))))],
        )
        .expect("the test IPC server answers");
        let held = match answer_of(answers.first()) {
            Some(Data::HandOverSecrets(HandOver::Held(key))) => key,
            _ => String::new(),
        };
        assert_eq!(
            held,
            crate::encode64(&own.key_pair.1),
            "the service did not answer with its public key"
        );
        assert!(
            Config::get_key_pair().0 == own.key_pair.0,
            "the service took a handed-over key while it had one"
        );
        assert!(
            Config::get_local_permanent_password_storage_and_salt() == own.password,
            "the service took a handed-over password while it had one"
        );
        assert!(
            Config::get_option(keys::OPTION_2FA) == own.two_fa,
            "the service took a handed-over 2FA secret while it had one"
        );
        assert!(reveals(&key_pair_of_file(), &own.key_pair.0));
        for answer in &answers {
            assert!(!reveals_any(answer, &own) && !reveals_any(answer, &handed));
        }
    }

    #[cfg(any(target_os = "linux", target_os = "macos"))]
    #[test]
    fn the_service_takes_handed_over_secrets_it_does_not_have() {
        let _lock = lock();
        let _files = ConfigFilesGuard::new();
        let own_key = own_key_pair();
        Config::set_permanent_password("");
        Config::set_option(keys::OPTION_2FA.to_owned(), "".to_owned());
        let handed = TestSecrets::new("handed-password");
        start_test_listener("_l442_take");

        let mut broken = handed.handed();
        broken
            .options
            .insert(keys::OPTION_2FA.to_owned(), "not a 2FA secret".to_owned());
        broken.permanent_password = None;
        ask(
            "_l442_take",
            &[request(&Data::HandOverSecrets(HandOver::Secrets(Box::new(broken))))],
        )
        .expect("the test IPC server answers");
        assert!(
            Config::get_option(keys::OPTION_2FA).is_empty(),
            "the service took a 2FA value that is no 2FA secret"
        );

        let answers = ask(
            "_l442_take",
            &[request(&Data::HandOverSecrets(HandOver::Secrets(Box::new(
                handed.handed(),
            ))))],
        )
        .expect("the test IPC server answers");
        assert!(matches!(
            answer_of(answers.first()),
            Some(Data::HandOverSecrets(HandOver::Held(_)))
        ));
        assert!(
            Config::get_local_permanent_password_storage_and_salt() == handed.password,
            "the service did not take the handed-over password"
        );
        assert!(
            Config::get_option(keys::OPTION_2FA) == handed.two_fa,
            "the service did not take the handed-over 2FA secret"
        );
        assert!(
            Config::get_key_pair().0 == own_key.0,
            "the service took a handed-over key while it had one"
        );
    }

    #[test]
    fn the_profile_copies_leave_once_the_service_holds_the_secrets() {
        let _lock = lock();
        let _files = ConfigFilesGuard::new();
        let legacy = TestSecrets::new("legacy-password");
        write_secrets_to_files(&legacy);
        let _not_holder = NotSecretsHolder::new();

        // No answer (an older service): the copies stay for a later start
        assert!(!after_hand_over(None));
        assert!(
            reveals_any(&files(), &legacy),
            "the copies left the profile before the service held the secrets"
        );
        let found = Config::secrets_in_files().expect("the profile holds copies");
        assert!(found == legacy.handed(), "the copies found are not the ones stored");

        let (_, service_public) = test_key_pair();
        assert!(after_hand_over(Some(crate::encode64(&service_public))));
        assert!(Config::secrets_in_files().is_none());
        let files = files();
        assert!(
            !reveals_any(&files, &legacy),
            "the profile still holds a secret"
        );
        assert!(
            key_pair_of_file() == br#"[[],[]]"#.to_vec(),
            "the profile still holds a key pair"
        );
        assert!(Config::get_key_pair().0.is_empty());
        assert!(Config::get_key_pair().1 == service_public);
    }

    #[test]
    fn a_window_without_the_device_key_signs_no_pairing_request() {
        let _lock = lock();
        let _files = ConfigFilesGuard::new();
        let legacy = test_key_pair();
        write_key_pair_to_file(&legacy);
        let _not_holder = NotSecretsHolder::new();

        let url = "http://127.0.0.1:9/api/pairing/redeem";
        let request = crate::hbbs_http::enrollment::sign_request(
            reqwest::Client::new().post(url),
            "POST",
            url,
            "123456789",
            None,
        )
        .build()
        .unwrap();
        assert!(
            request
                .headers()
                .get(crate::hbbs_http::enrollment::HEADER_SIGNATURE)
                .is_none(),
            "a window without the device key signed a pairing request"
        );
        assert!(crate::hbbs_http::enrollment::public_key_b64()
            .map_or(true, |key| key != crate::encode64(&legacy.1)));
        assert!(reveals(&key_pair_of_file(), &legacy.0));
    }

    // The window of an installed client takes the key proof of a pairing or a
    // join from the service only (L483). pairing_proof asks on the main pipe
    // (postfix "") through connect, which on Windows refuses that pipe when
    // its server is not the service; the request then goes out unsigned.
    #[test]
    fn the_window_takes_a_key_proof_from_the_service_only() {
        assert!(
            refuses_main_ipc_server("", false, false),
            "the window used a main pipe whose server is not the service"
        );
        assert!(!refuses_main_ipc_server("", false, true));
        // A process that holds the device's secrets signs itself when no
        // server process answers
        assert!(!refuses_main_ipc_server("", true, false));
    }

    #[cfg(any(target_os = "linux", target_os = "macos"))]
    #[test]
    fn the_service_proves_its_key_for_a_pairing_without_handing_it_out() {
        use crate::hbbs_http::enrollment::{
            proof_payload, HEADER_NONCE, HEADER_SIGNATURE, HEADER_TIMESTAMP,
        };
        use hbb_common::sodiumoxide::crypto::sign;
        let _lock = lock();
        let _files = ConfigFilesGuard::new();
        let (secret, public) = own_key_pair();
        start_test_listener("_l442_proof");

        // The pairing request and the join (L483)
        for path in [
            crate::hbbs_http::pairing_proof::PATH,
            crate::hbbs_http::pairing_proof::JOIN_PATH,
        ] {
            let answers = ask(
                "_l442_proof",
                &[request(&Data::PairingProof((path.to_owned(), None)))],
            )
            .expect("the test IPC server answers");
            let Some(Data::PairingProof((answered, Some((key, headers))))) =
                answer_of(answers.first())
            else {
                panic!("the service gave no proof for {path}");
            };
            assert_eq!(answered, path);
            assert_eq!(key, crate::encode64(&public));
            let header = |name: &str| {
                headers
                    .iter()
                    .find(|(header, _)| header == name)
                    .map(|(_, value)| value.clone())
                    .unwrap_or_default()
            };
            let payload = proof_payload(
                "POST",
                path,
                &Config::get_id(),
                &key,
                &header(HEADER_TIMESTAMP),
                &header(HEADER_NONCE),
            );
            let signature = crate::decode64(header(HEADER_SIGNATURE)).unwrap_or_default();
            let signature = sign::Signature::from_bytes(&signature).expect("a signature");
            assert!(
                sign::verify_detached(
                    &signature,
                    payload.as_bytes(),
                    &sign::PublicKey::from_slice(&public).unwrap()
                ),
                "the proof for {path} does not verify"
            );
            for answer in &answers {
                assert!(!reveals(answer, &secret));
            }
        }

        // Nothing else
        for path in [
            "/api/onboard/join/",
            "/x/api/onboard/join",
            "/api/devices/register",
            "/api/devices/register/status",
        ] {
            let answers = ask(
                "_l442_proof",
                &[request(&Data::PairingProof((path.to_owned(), None)))],
            )
            .expect("the test IPC server answers");
            assert!(
                matches!(
                    answer_of(answers.first()),
                    Some(Data::PairingProof((_, None)))
                ),
                "the service signed {path} for another process"
            );
        }
    }

    #[cfg(any(target_os = "linux", target_os = "macos"))]
    #[test]
    fn the_ipc_never_answers_with_the_device_secrets() {
        let _lock = lock();
        let _files = ConfigFilesGuard::new();
        let own = TestSecrets::new("own-password").hold();
        assert_eq!(own.key_pair.0.len(), 64);
        Config::set_key_confirmed(true);
        start_test_listener("_l442_secret");

        let config = |name: &str| request(&Data::Config((name.to_owned(), None)));
        let answers = ask(
            "_l442_secret",
            &[
                br#"{"t":"ConfirmedKey","c":null}"#.to_vec(),
                request(&Data::SyncConfig(None)),
                config("key_pair"),
                config(IPC_PUBLIC_KEY),
                request(&Data::Options(None)),
                config("permanent-password-storage-and-salt"),
                config("permanent-password"),
                config(keys::OPTION_2FA),
                config(IPC_2FA_SET),
                config("permanent-password-set"),
            ],
        )
        .expect("the test IPC server answers");
        assert!(answers.len() >= 5, "too few answers: {}", answers.len());
        for (i, answer) in answers.iter().enumerate() {
            assert!(
                !reveals_any(answer, &own),
                "IPC answer {i} carries one of the device's secrets"
            );
        }
        let says = |name: &str| {
            answers.iter().find_map(|answer| match answer_of(Some(answer)) {
                Some(Data::Config((n, Some(value)))) if n == name => Some(value),
                _ => None,
            })
        };
        assert_eq!(says(IPC_2FA_SET).as_deref(), Some("Y"));
        assert_eq!(says("permanent-password-set").as_deref(), Some("Y"));
    }

    #[cfg(any(target_os = "linux", target_os = "macos"))]
    #[test]
    fn a_config_sent_over_the_ipc_does_not_replace_the_device_secrets() {
        let _lock = lock();
        let _files = ConfigFilesGuard::new();
        let planted = TestSecrets::new("planted-password");
        let own = TestSecrets::new("own-password").hold();
        start_test_listener("_l442_plant");

        let mut config = serde_json::to_value(Config::get()).unwrap();
        config["key_pair"] = serde_json::json!([planted.key_pair.0, planted.key_pair.1]);
        config["password"] = serde_json::json!(planted.password.0);
        config["salt"] = serde_json::json!(planted.password.1);
        let mut config2 = serde_json::to_value(Config2::get()).unwrap();
        config2["options"][keys::OPTION_2FA] = serde_json::json!(planted.two_fa);
        let sync = serde_json::json!({"t": "SyncConfig", "c": [config, config2]});
        let mut options = Config::get_options_for_other_process();
        let without_2fa = options.clone();
        options.insert(keys::OPTION_2FA.to_owned(), planted.two_fa.clone());
        ask(
            "_l442_plant",
            &[
                serde_json::to_vec(&sync).unwrap(),
                request(&Data::Options(Some(options))),
                request(&Data::Options(Some(without_2fa))),
            ],
        )
        .expect("the test IPC server answers");

        let in_files = files();
        assert!(
            !reveals_any(&in_files, &planted),
            "a secret sent over the IPC went into the config files"
        );
        assert!(
            reveals(&in_files, &own.key_pair.0),
            "the device's own key left the file"
        );
        assert!(Config::get_key_pair().1 == own.key_pair.1);
        assert!(
            Config::get_local_permanent_password_storage_and_salt() == own.password,
            "a password sent over the IPC replaced the own"
        );
        assert!(
            Config::get_option(keys::OPTION_2FA) == own.two_fa,
            "options sent over the IPC replaced or removed the 2FA secret"
        );
    }

    #[cfg(any(target_os = "linux", target_os = "macos"))]
    #[test]
    fn the_window_turns_2fa_on_and_off_in_the_service() {
        let _lock = lock();
        let _files = ConfigFilesGuard::new();
        Config::set_option(keys::OPTION_2FA.to_owned(), "".to_owned());
        let (two_fa, _) = test_2fa();
        start_test_listener("_l442_2fa");

        let set = |value: &str| {
            request(&Data::Config((
                keys::OPTION_2FA.to_owned(),
                Some(value.to_owned()),
            )))
        };
        let is_set = request(&Data::Config((IPC_2FA_SET.to_owned(), None)));
        let answers = ask(
            "_l442_2fa",
            &[set("not a 2FA secret"), set(&two_fa), is_set.clone()],
        )
        .expect("the test IPC server answers");
        let values: Vec<Option<String>> = answers
            .iter()
            .map(|answer| match answer_of(Some(answer)) {
                Some(Data::Config((_, value))) => value,
                _ => None,
            })
            .collect();
        assert_eq!(
            values,
            vec![Some("N".to_owned()), Some("Y".to_owned()), Some("Y".to_owned())]
        );
        assert!(
            Config::get_option(keys::OPTION_2FA) == two_fa,
            "the service did not turn 2FA on"
        );

        let answers = ask("_l442_2fa", &[set(""), is_set]).expect("the test IPC server answers");
        assert!(matches!(
            answer_of(answers.last()),
            Some(Data::Config((_, Some(value)))) if value == "N"
        ));
        assert!(
            Config::get_option(keys::OPTION_2FA).is_empty(),
            "2FA stayed on"
        );
    }
}
