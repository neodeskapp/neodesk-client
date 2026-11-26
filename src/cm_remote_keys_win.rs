//! The Windows half of cm_remote_keys.rs: a low-level keyboard hook in the
//! connection manager's process that drops keys the server typed for a
//! remote computer while a connection manager window is in front.

use crate::cm_remote_keys::RemoteKeyFilter;
use hbb_common::{config::LocalConfig, lazy_static, log};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    mpsc, Mutex,
};
use winapi::{
    shared::minwindef::{DWORD, HMODULE, LPARAM, LRESULT, WPARAM},
    um::{
        libloaderapi::GetModuleHandleExA,
        processthreadsapi::GetCurrentProcessId,
        winuser::*,
    },
};

const GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT: u32 = 2;
const GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS: u32 = 4;

static RUNNING: AtomicBool = AtomicBool::new(false);
static STARTED: AtomicBool = AtomicBool::new(false);

lazy_static::lazy_static! {
    static ref FILTER: Mutex<RemoteKeyFilter> = Mutex::new(RemoteKeyFilter::default());
}

fn cm_in_front() -> bool {
    // The option that lets the remote side use the connection manager.
    if LocalConfig::get_option("allow-remote-cm-modification") == "Y" {
        return false;
    }
    unsafe {
        let hwnd = GetForegroundWindow();
        if hwnd.is_null() {
            return false;
        }
        let mut pid: DWORD = 0;
        GetWindowThreadProcessId(hwnd, &mut pid);
        pid == GetCurrentProcessId()
    }
}

unsafe extern "system" fn on_keyboard(code: i32, w_param: WPARAM, l_param: LPARAM) -> LRESULT {
    if code == HC_ACTION {
        let ks = &*(l_param as *const KBDLLHOOKSTRUCT);
        let msg = w_param as u32;
        let down = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
        let from_remote = ks.flags & LLKHF_INJECTED != 0
            && ks.dwExtraInfo == enigo::ENIGO_INPUT_EXTRA_VALUE;
        let drop = FILTER
            .lock()
            .map(|mut f| f.on_key((ks.vkCode, ks.scanCode), down, from_remote, cm_in_front))
            .unwrap_or(false);
        if drop {
            return 1;
        }
    }
    CallNextHookEx(std::ptr::null_mut(), code, w_param, l_param)
}

/// Sets the hook on a thread of its own. Returns when it is set or failed.
pub fn start() {
    if STARTED.swap(true, Ordering::SeqCst) {
        return;
    }
    let (tx, rx) = mpsc::channel::<bool>();
    std::thread::spawn(move || unsafe {
        let mut module: HMODULE = std::ptr::null_mut();
        if GetModuleHandleExA(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            DefWindowProcA as _,
            &mut module as _,
        ) == 0
        {
            log::error!("cm remote keys: GetModuleHandleExA failed: {}", std::io::Error::last_os_error());
            tx.send(false).ok();
            return;
        }
        let hook = SetWindowsHookExA(WH_KEYBOARD_LL, Some(on_keyboard), module, 0);
        if hook.is_null() {
            log::error!("cm remote keys: SetWindowsHookExA failed: {}", std::io::Error::last_os_error());
            tx.send(false).ok();
            return;
        }
        RUNNING.store(true, Ordering::SeqCst);
        tx.send(true).ok();
        let mut msg: MSG = std::mem::zeroed();
        while GetMessageA(&mut msg, std::ptr::null_mut(), 0, 0) > 0 {
            TranslateMessage(&msg);
            DispatchMessageA(&msg);
        }
        RUNNING.store(false, Ordering::SeqCst);
        UnhookWindowsHookEx(hook);
    });
    let ok = rx.recv_timeout(std::time::Duration::from_secs(2)).unwrap_or(false);
    log::info!("cm remote keys: hook {}", if ok { "set" } else { "not set" });
}

pub fn is_running() -> bool {
    RUNNING.load(Ordering::SeqCst)
}
