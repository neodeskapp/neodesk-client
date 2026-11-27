//! Windows: PowerShell for the service itself and for the signed-in user.
//! Printer connections and network drives belong to a user's logon, so
//! they are set up by a PowerShell that runs in the user's session.

use std::{
    io::Read,
    os::windows::io::FromRawHandle,
    process::Command,
    sync::{mpsc, Arc, Mutex},
    time::Duration,
};

use hbb_common::base64::{engine::general_purpose::STANDARD, Engine as _};
use windows::{
    core::{PCWSTR, PWSTR},
    Win32::{
        Foundation::{
            CloseHandle, SetHandleInformation, HANDLE, HANDLE_FLAGS, HANDLE_FLAG_INHERIT,
            WAIT_OBJECT_0,
        },
        Security::SECURITY_ATTRIBUTES,
        System::{
            Environment::{CreateEnvironmentBlock, DestroyEnvironmentBlock},
            JobObjects::{AssignProcessToJobObject, CreateJobObjectW, TerminateJobObject},
            Pipes::CreatePipe,
            Threading::{
                CreateProcessAsUserW, GetExitCodeProcess, ResumeThread, TerminateProcess,
                WaitForSingleObject, CREATE_NO_WINDOW, CREATE_SUSPENDED,
                CREATE_UNICODE_ENVIRONMENT, PROCESS_INFORMATION, STARTF_USESTDHANDLES,
                STARTUPINFOW,
            },
        },
    },
};

use super::process::{self, Outcome, Tail, MAX_OUTPUT};

extern "C" {
    // src/platform/windows.cc; declared as in platform/windows.rs
    fn GetSessionUserTokenWin(
        token: *mut *mut core::ffi::c_void,
        session_id: u32,
        as_user: i32,
        token_pid: &mut u32,
    ) -> i32;
}

/// A script as PowerShell's -EncodedCommand takes it. Progress records
/// would come out as CLIXML on stderr, so they are switched off.
fn encode(script: &str) -> String {
    let script = format!(
        "$ProgressPreference = 'SilentlyContinue'\n[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)\n{script}"
    );
    let bytes: Vec<u8> = script
        .encode_utf16()
        .flat_map(|unit| unit.to_le_bytes())
        .collect();
    STANDARD.encode(bytes)
}

const PS_ARGS: [&str; 5] = [
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy",
    "Bypass",
    "-EncodedCommand",
];

/// Runs `script` in the service's own PowerShell (SYSTEM)
pub fn powershell(script: &str, timeout: Duration) -> std::io::Result<Outcome> {
    let mut command = Command::new(super::run::windows_powershell());
    command.args(PS_ARGS).arg(encode(script));
    process::run(command, timeout)
}

/// `script` in PowerShell with a short time limit: its output, or why it
/// failed. Scripts end with `throw` on failure.
pub fn ps(script: &str) -> Result<String, String> {
    outcome_text(powershell(script, Duration::from_secs(120)).map_err(|err| err.to_string())?)
}

/// Runs `script` as the user signed in at the console or over RDP. A
/// client that does not run as SYSTEM already is that user.
pub fn ps_as_user(script: &str) -> Result<String, String> {
    let timeout = Duration::from_secs(120);
    if !crate::platform::windows::is_root() {
        return ps(script);
    }
    let session = crate::platform::windows::get_current_session_id(true);
    if session == u32::MAX {
        return Err("Nobody is signed in to this computer.".to_owned());
    }
    let command_line = format!(
        "\"{}\" {} {}",
        super::run::windows_powershell(),
        PS_ARGS.join(" "),
        encode(script)
    );
    outcome_text(run_in_session(session, &command_line, timeout)?)
}

fn outcome_text(outcome: Outcome) -> Result<String, String> {
    if outcome.timed_out {
        return Err("PowerShell did not finish in time.".to_owned());
    }
    let text = outcome.output.trim().to_owned();
    if outcome.exit_code == Some(0) {
        Ok(text)
    } else if text.is_empty() {
        Err(format!("PowerShell failed ({:?}).", outcome.exit_code))
    } else {
        Err(text)
    }
}

struct Handle(HANDLE);

/// The processes a task started, for ending all of them on a timeout.
/// Every process a member starts joins the job too.
pub struct Job(Handle);

impl Job {
    pub fn new() -> Option<Self> {
        unsafe { CreateJobObjectW(None, PCWSTR::null()) }
            .ok()
            .map(|handle| Self(Handle(handle)))
    }

    pub fn assign(&self, process: HANDLE) -> bool {
        unsafe { AssignProcessToJobObject(self.0 .0, process) }.is_ok()
    }

    pub fn kill(&self) {
        unsafe {
            let _ = TerminateJobObject(self.0 .0, 1);
        }
    }
}

/// A job with `child` in it
pub fn track(child: &std::process::Child) -> Option<Job> {
    use std::os::windows::io::AsRawHandle;
    let job = Job::new()?;
    job.assign(HANDLE(child.as_raw_handle() as _))
        .then_some(job)
}

impl Drop for Handle {
    fn drop(&mut self) {
        if !self.0.is_invalid() && !self.0 .0.is_null() {
            unsafe {
                let _ = CloseHandle(self.0);
            }
        }
    }
}

/// Starts `command_line` with the token of the user of `session`, stdout
/// and stderr into one pipe, and waits up to `timeout`.
fn run_in_session(session: u32, command_line: &str, timeout: Duration) -> Result<Outcome, String> {
    let mut raw_token: *mut core::ffi::c_void = std::ptr::null_mut();
    let mut token_pid = 0_u32;
    if unsafe { GetSessionUserTokenWin(&mut raw_token, session, 1, &mut token_pid) } == 0 {
        return Err(if token_pid == 0 {
            "Nobody is signed in to this computer.".to_owned()
        } else {
            format!(
                "The signed-in user's token is not available: {}",
                std::io::Error::last_os_error()
            )
        });
    }
    let token = Handle(HANDLE(raw_token));

    let attributes = SECURITY_ATTRIBUTES {
        nLength: std::mem::size_of::<SECURITY_ATTRIBUTES>() as u32,
        lpSecurityDescriptor: std::ptr::null_mut(),
        bInheritHandle: true.into(),
    };
    let mut read = HANDLE::default();
    let mut write = HANDLE::default();
    unsafe { CreatePipe(&mut read, &mut write, Some(&attributes), 0) }
        .map_err(|err| format!("No pipe for the output: {err}"))?;
    let write = Handle(write);
    // Only the child's end is inherited
    unsafe { SetHandleInformation(read, HANDLE_FLAG_INHERIT.0, HANDLE_FLAGS(0)) }
        .map_err(|err| format!("The pipe could not be set up: {err}"))?;
    let reader = unsafe { std::fs::File::from_raw_handle(read.0 as _) };

    let mut environment: *mut core::ffi::c_void = std::ptr::null_mut();
    let has_environment =
        unsafe { CreateEnvironmentBlock(&mut environment, Some(token.0), false) }.is_ok();

    let mut startup = STARTUPINFOW {
        cb: std::mem::size_of::<STARTUPINFOW>() as u32,
        dwFlags: STARTF_USESTDHANDLES,
        hStdInput: HANDLE::default(),
        hStdOutput: write.0,
        hStdError: write.0,
        ..Default::default()
    };
    let mut information = PROCESS_INFORMATION::default();
    let mut line: Vec<u16> = command_line.encode_utf16().chain(Some(0)).collect();
    // Suspended until it is in the job, so nothing it starts escapes
    let mut flags = CREATE_NO_WINDOW | CREATE_SUSPENDED;
    if has_environment {
        flags |= CREATE_UNICODE_ENVIRONMENT;
    }
    let started = unsafe {
        CreateProcessAsUserW(
            Some(token.0),
            PCWSTR::null(),
            Some(PWSTR(line.as_mut_ptr())),
            None,
            None,
            true,
            flags,
            if has_environment {
                Some(environment as *const _)
            } else {
                None
            },
            PCWSTR::null(),
            &mut startup,
            &mut information,
        )
    };
    if has_environment {
        unsafe {
            let _ = DestroyEnvironmentBlock(environment);
        }
    }
    started.map_err(|err| format!("PowerShell did not start for the signed-in user: {err}"))?;
    let process = Handle(information.hProcess);
    let thread = Handle(information.hThread);
    let job = Job::new().filter(|job| job.assign(process.0));
    unsafe {
        ResumeThread(thread.0);
    }
    drop(thread);
    // The child holds its own copy now; EOF comes when it ends
    drop(write);

    let tail = Arc::new(Mutex::new(Tail::new(MAX_OUTPUT)));
    let (done_tx, done_rx) = mpsc::channel::<()>();
    {
        let tail = tail.clone();
        let mut reader = reader;
        std::thread::spawn(move || {
            let mut buffer = [0_u8; 8192];
            while let Ok(n) = reader.read(&mut buffer) {
                if n == 0 {
                    break;
                }
                if let Ok(mut tail) = tail.lock() {
                    tail.push(&buffer[..n]);
                }
            }
            let _ = done_tx.send(());
        });
    }

    let millis = timeout.as_millis().min(u32::MAX as u128 - 1) as u32;
    let waited = unsafe { WaitForSingleObject(process.0, millis) };
    let timed_out = waited != WAIT_OBJECT_0;
    let mut exit_code = None;
    if timed_out {
        if let Some(job) = &job {
            job.kill();
        }
        unsafe {
            let _ = TerminateProcess(process.0, 1);
        }
    } else {
        let mut code = 0_u32;
        if unsafe { GetExitCodeProcess(process.0, &mut code) }.is_ok() {
            exit_code = Some(code as i32);
        }
    }
    let _ = done_rx.recv_timeout(Duration::from_secs(2));
    let output = tail.lock().map(|tail| tail.text()).unwrap_or_default();
    Ok(Outcome {
        exit_code,
        output,
        timed_out,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encoded_scripts_run_and_report_failure() {
        assert_eq!(ps("Write-Output 'ä ok'").unwrap(), "ä ok");
        let err = ps("throw 'broken'").unwrap_err();
        assert!(err.contains("broken"), "{err}");
    }
}
