//! What the exe's install page shows while it installs. The elevated install
//! script reports nothing until it ends, so the steps come from what can be
//! seen from outside: the permission prompt is up until files start to
//! change in the install folder, the copy is as far as the folder's size, the
//! rest of the script sets up the service, and then the installed client
//! starts and the install window waits for its window.

use std::{
    path::{Path, PathBuf},
    sync::Mutex,
    time::{Duration, Instant},
};

struct Progress {
    folder: PathBuf,
    /// The size of what gets copied, in KB.
    total_kb: u64,
    /// The install folder's size when the install began (an update replaces
    /// a full folder).
    first_kb: u64,
    copying: bool,
    script_done: bool,
    error: Option<String>,
}

static PROGRESS: Mutex<Option<Progress>> = Mutex::new(None);

/// The install script is about to ask for permission and run.
pub fn begin(folder: &str, total_kb: u64) {
    *PROGRESS.lock().unwrap() = Some(Progress {
        folder: PathBuf::from(folder),
        total_kb,
        first_kb: size_kb(Path::new(folder)),
        copying: false,
        script_done: false,
        error: None,
    });
}

/// The install script ended without an error.
pub fn script_done() {
    if let Some(p) = PROGRESS.lock().unwrap().as_mut() {
        p.script_done = true;
    }
}

/// The install failed; the page shows `error` with Try again.
pub fn failed(error: &str) {
    let mut lock = PROGRESS.lock().unwrap();
    match lock.as_mut() {
        Some(p) => p.error = Some(error.to_owned()),
        None => {
            *lock = Some(Progress {
                folder: PathBuf::new(),
                total_kb: 0,
                first_kb: 0,
                copying: false,
                script_done: false,
                error: Some(error.to_owned()),
            })
        }
    }
}

/// The step for the install page: {"step": "preparing" | "permission" |
/// "copying" | "service" | "starting" | "failed", "percent": 0..100,
/// "error": "...", "cancelled": bool}.
pub fn json() -> String {
    let mut lock = PROGRESS.lock().unwrap();
    let Some(p) = lock.as_mut() else {
        return serde_json::json!({ "step": "preparing", "percent": 0 }).to_string();
    };
    if let Some(error) = p.error.take() {
        // Shown once; Try again starts over.
        *lock = None;
        return serde_json::json!({
            "step": "failed",
            "percent": 0,
            "error": error,
            "cancelled": is_cancelled(&error),
        })
        .to_string();
    }
    if p.script_done {
        return serde_json::json!({ "step": "starting", "percent": 100 }).to_string();
    }
    let now = size_kb(&p.folder);
    if now != p.first_kb {
        p.copying = true;
    }
    let (step, percent) = if !p.copying {
        ("permission", 0)
    } else if now * 100 < p.total_kb * 97 {
        ("copying", (now * 100 / p.total_kb.max(1)).min(99))
    } else {
        ("service", 100)
    };
    serde_json::json!({ "step": step, "percent": percent }).to_string()
}

/// Whether the error is the permission prompt answered with No.
fn is_cancelled(error: &str) -> bool {
    // ERROR_CANCELLED from ShellExecuteEx when the prompt is declined.
    error.contains("1223") || error.to_lowercase().contains("cancel")
}

/// Waits until the installed client's main window is up (it has the app's
/// name as its title), so the install window does not leave a gap; at most
/// 30 seconds.
pub fn wait_for_client_window() {
    use winapi::um::winuser::{FindWindowW, IsWindowVisible};
    let title: Vec<u16> = crate::get_app_name()
        .encode_utf16()
        .chain(std::iter::once(0))
        .collect();
    let class: Vec<u16> = "FLUTTER_RUNNER_WIN32_WINDOW"
        .encode_utf16()
        .chain(std::iter::once(0))
        .collect();
    let start = Instant::now();
    while start.elapsed() < Duration::from_secs(30) {
        let hwnd = unsafe { FindWindowW(class.as_ptr(), title.as_ptr()) };
        if !hwnd.is_null() && unsafe { IsWindowVisible(hwnd) } != 0 {
            // The client fades its window in; let it paint first.
            std::thread::sleep(Duration::from_millis(800));
            return;
        }
        std::thread::sleep(Duration::from_millis(200));
    }
}

/// A folder's size in KB, without following links.
fn size_kb(path: &Path) -> u64 {
    let mut total = 0u64;
    let mut stack = vec![path.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let Ok(entries) = std::fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let Ok(meta) = std::fs::symlink_metadata(entry.path()) else {
                continue;
            };
            if meta.is_symlink() {
                continue;
            }
            if meta.is_dir() {
                stack.push(entry.path());
            } else {
                total = total.saturating_add(meta.len());
            }
        }
    }
    total / 1024
}
