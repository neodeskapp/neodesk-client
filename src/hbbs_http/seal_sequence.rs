//! The sequence number of the device's sealed requests (L500).
//!
//! The server takes a sealed request only when its number is higher than
//! every number it saw from the device before. The counter lives in a file
//! of its own next to the config, which only the process that seals writes:
//! a process that keeps a copy of the whole local config writes that copy
//! back on every change, and so moved the counter back when it lived there.
//! Each number is taken under an exclusive lock on a lock file, read from
//! the file, raised past the floor the caller gives (the number older
//! versions keep in the local config) and written back through a new file
//! renamed over the old one. So no two processes or threads take the same
//! number, and a restart of any of them continues above the last one.
//!
//! This file uses nothing but std, so its tests also run on their own:
//! `rustc --edition 2021 --test src/hbbs_http/seal_sequence.rs`.

use std::{
    fs::{self, File, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
};

/// Takes the next number from the counter in `file`: one above the higher
/// of the number stored there and `floor`.
pub fn next(file: &Path, floor: u64) -> io::Result<u64> {
    if let Some(dir) = file.parent() {
        fs::create_dir_all(dir)?;
    }
    let _lock = Lock::take(&with_suffix(file, ".lock"))?;
    let stored = read(file);
    let next = stored
        .max(floor)
        .checked_add(1)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "sequence counter exhausted"))?;
    let fresh = with_suffix(file, ".new");
    {
        let mut out = open_private(&fresh, true)?;
        out.write_all(next.to_string().as_bytes())?;
        out.sync_all()?;
    }
    fs::rename(&fresh, file)?;
    Ok(next)
}

/// The number stored in `file`, 0 when there is none.
pub fn read(file: &Path) -> u64 {
    fs::read_to_string(file)
        .ok()
        .and_then(|text| text.trim().parse().ok())
        .unwrap_or(0)
}

fn with_suffix(file: &Path, suffix: &str) -> PathBuf {
    let mut name = file.as_os_str().to_owned();
    name.push(suffix);
    PathBuf::from(name)
}

fn open_private(path: &Path, truncate: bool) -> io::Result<File> {
    let mut options = OpenOptions::new();
    options
        .read(true)
        .write(true)
        .create(true)
        .truncate(truncate);
    #[cfg(unix)]
    std::os::unix::fs::OpenOptionsExt::mode(&mut options, 0o600);
    options.open(path)
}

/// An exclusive lock on a file, held until it is dropped. The system lets
/// it go when the process ends, so a crash leaves no stale lock.
struct Lock(#[allow(dead_code)] File);

impl Lock {
    fn take(path: &Path) -> io::Result<Self> {
        let file = open_private(path, false)?;
        lock_exclusive(&file)?;
        Ok(Lock(file))
    }
}

#[cfg(unix)]
fn lock_exclusive(file: &File) -> io::Result<()> {
    use std::os::unix::io::AsRawFd;
    extern "C" {
        fn flock(fd: i32, operation: i32) -> i32;
    }
    const LOCK_EX: i32 = 2;
    loop {
        // SAFETY: the descriptor belongs to `file`, which outlives the call
        if unsafe { flock(file.as_raw_fd(), LOCK_EX) } == 0 {
            return Ok(());
        }
        let err = io::Error::last_os_error();
        if err.kind() != io::ErrorKind::Interrupted {
            return Err(err);
        }
    }
}

#[cfg(windows)]
fn lock_exclusive(file: &File) -> io::Result<()> {
    use std::os::windows::io::AsRawHandle;
    #[repr(C)]
    struct Overlapped {
        internal: usize,
        internal_high: usize,
        offset: u32,
        offset_high: u32,
        event: *mut std::ffi::c_void,
    }
    #[link(name = "kernel32")]
    extern "system" {
        fn LockFileEx(
            file: *mut std::ffi::c_void,
            flags: u32,
            reserved: u32,
            bytes_low: u32,
            bytes_high: u32,
            overlapped: *mut Overlapped,
        ) -> i32;
    }
    const LOCKFILE_EXCLUSIVE_LOCK: u32 = 2;
    let mut overlapped = Overlapped {
        internal: 0,
        internal_high: 0,
        offset: 0,
        offset_high: 0,
        event: std::ptr::null_mut(),
    };
    // SAFETY: the handle belongs to `file`, which outlives the call, and the
    // handle is synchronous, so the call returns once the lock is held
    let locked = unsafe {
        LockFileEx(
            file.as_raw_handle() as *mut std::ffi::c_void,
            LOCKFILE_EXCLUSIVE_LOCK,
            0,
            u32::MAX,
            u32::MAX,
            &mut overlapped,
        )
    };
    if locked == 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

#[cfg(not(any(unix, windows)))]
fn lock_exclusive(_file: &File) -> io::Result<()> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        collections::HashSet,
        process::{Command, Stdio},
        sync::Arc,
        thread,
    };

    fn temp_counter(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "neodesk-seq-{}-{}-{name}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or(0)
        ));
        fs::create_dir_all(&dir).unwrap();
        dir.join("NeoDesk Client_sequence")
    }

    #[test]
    fn counts_up_from_nothing() {
        let file = temp_counter("fresh");
        assert_eq!(next(&file, 0).unwrap(), 1);
        assert_eq!(next(&file, 0).unwrap(), 2);
        assert_eq!(read(&file), 2);
    }

    /// The lab's numbers: the counter stood at 1714 and the window's stale
    /// copy said 1711. A stale floor never moves the counter back.
    #[test]
    fn a_stale_floor_never_moves_it_back() {
        let file = temp_counter("stale");
        fs::write(&file, "1714").unwrap();
        assert_eq!(next(&file, 1711).unwrap(), 1715);
        assert_eq!(next(&file, 0).unwrap(), 1716);
    }

    /// An older version kept counting in the local config: the first number
    /// after the update is above it.
    #[test]
    fn continues_above_a_higher_floor() {
        let file = temp_counter("floor");
        fs::write(&file, "12").unwrap();
        assert_eq!(next(&file, 1674).unwrap(), 1675);
        assert_eq!(read(&file), 1675);
    }

    #[test]
    fn a_restart_continues_above_the_last_number() {
        let file = temp_counter("restart");
        for _ in 0..5 {
            next(&file, 0).unwrap();
        }
        // A new process knows only the file
        assert_eq!(read(&file), 5);
        assert_eq!(next(&file, 3).unwrap(), 6);
    }

    #[test]
    fn a_damaged_file_falls_back_to_the_floor() {
        let file = temp_counter("damaged");
        fs::write(&file, "not a number").unwrap();
        assert_eq!(next(&file, 40).unwrap(), 41);
    }

    /// Many users of one file at once, each with a handle of its own as a
    /// separate process has: every number is taken once and each user's
    /// numbers only go up.
    #[test]
    fn two_users_of_the_file_never_share_a_number() {
        let file = Arc::new(temp_counter("threads"));
        let users = (0..8)
            .map(|_| {
                let file = file.clone();
                thread::spawn(move || (0..50).map(|_| next(&file, 0).unwrap()).collect::<Vec<_>>())
            })
            .collect::<Vec<_>>();
        let mut seen = HashSet::new();
        for user in users {
            let numbers = user.join().unwrap();
            assert!(numbers.windows(2).all(|w| w[0] < w[1]), "{numbers:?}");
            for n in numbers {
                assert!(seen.insert(n), "{n} taken twice");
            }
        }
        assert_eq!(seen.len(), 400);
        assert_eq!(read(&file), 400);
    }

    const CHILD_FILE: &str = "NEODESK_SEQ_TEST_FILE";

    /// Runs in the child processes of
    /// [`two_processes_never_share_a_number`] only.
    #[test]
    fn child_process_takes_numbers() {
        let Ok(file) = std::env::var(CHILD_FILE) else {
            return;
        };
        let numbers = (0..100)
            .map(|_| next(Path::new(&file), 0).unwrap().to_string())
            .collect::<Vec<_>>();
        println!("NUMBERS {}", numbers.join(","));
    }

    #[test]
    fn two_processes_never_share_a_number() {
        let file = temp_counter("processes");
        let exe = std::env::current_exe().unwrap();
        let children = (0..2)
            .map(|_| {
                Command::new(&exe)
                    .args(["--exact", "--nocapture", "--test-threads=1"])
                    .arg(test_name("child_process_takes_numbers"))
                    .env(CHILD_FILE, &file)
                    .output()
                    .unwrap()
            })
            .collect::<Vec<_>>();
        // Run them at the same time, too
        let parallel = (0..2)
            .map(|_| {
                Command::new(&exe)
                    .args(["--exact", "--nocapture", "--test-threads=1"])
                    .arg(test_name("child_process_takes_numbers"))
                    .env(CHILD_FILE, &file)
                    .stdout(Stdio::piped())
                    .spawn()
                    .unwrap()
            })
            .collect::<Vec<_>>();
        let mut outputs = children;
        for child in parallel {
            outputs.push(child.wait_with_output().unwrap());
        }
        let mut seen = HashSet::new();
        for output in outputs {
            assert!(output.status.success());
            let text = String::from_utf8_lossy(&output.stdout);
            // libtest prints the test's name on the same line before it
            let line = text
                .split("NUMBERS ")
                .nth(1)
                .and_then(|rest| rest.lines().next())
                .unwrap_or_else(|| panic!("no numbers from the child: {text}"));
            let numbers = line
                .split(',')
                .map(|n| n.parse::<u64>().unwrap())
                .collect::<Vec<_>>();
            assert!(numbers.windows(2).all(|w| w[0] < w[1]));
            for n in numbers {
                assert!(seen.insert(n), "{n} taken by two processes");
            }
        }
        assert_eq!(seen.len(), 400);
        assert_eq!(read(&file), 400);
    }

    /// The child's test name: its module path inside the crate, which
    /// differs between `rustc --test` of this file and the client's tests.
    fn test_name(name: &str) -> String {
        let module = module_path!();
        match module.split_once("::") {
            Some((_, rest)) => format!("{rest}::{name}"),
            None => format!("tests::{name}"),
        }
    }
}
