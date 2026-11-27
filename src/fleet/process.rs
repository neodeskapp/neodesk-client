//! Runs a program with a time limit and keeps the end of what it writes.

use std::{
    io::Read,
    process::{Command, Stdio},
    sync::{mpsc, Arc, Mutex},
    time::{Duration, Instant},
};

/// The most output a result carries: the last 64 KiB
pub const MAX_OUTPUT: usize = 64 * 1024;
/// How long the readers may take after the program ended. A program it
/// started in the background can keep the pipes open for good.
const DRAIN_WAIT: Duration = Duration::from_secs(2);

#[derive(Debug)]
pub struct Outcome {
    pub exit_code: Option<i32>,
    pub output: String,
    pub timed_out: bool,
}

/// The last `limit` bytes of everything written to it
#[derive(Debug)]
pub struct Tail {
    data: Vec<u8>,
    limit: usize,
    dropped: bool,
}

impl Tail {
    pub fn new(limit: usize) -> Self {
        Self {
            data: Vec::new(),
            limit,
            dropped: false,
        }
    }

    pub fn push(&mut self, bytes: &[u8]) {
        if bytes.len() >= self.limit {
            self.data.clear();
            self.data
                .extend_from_slice(&bytes[bytes.len() - self.limit..]);
            self.dropped = true;
            return;
        }
        self.data.extend_from_slice(bytes);
        // Drop in chunks, so a stream of small writes does not move the
        // buffer every time
        if self.data.len() > self.limit * 2 {
            let excess = self.data.len() - self.limit;
            self.data.drain(..excess);
            self.dropped = true;
        }
    }

    pub fn text(&self) -> String {
        let start = self.data.len().saturating_sub(self.limit);
        let bytes = &self.data[start..];
        let dropped = self.dropped || start > 0;
        // Cut at a character, not in the middle of one
        let bytes = if dropped {
            let skip = bytes
                .iter()
                .take(4)
                .take_while(|byte| (**byte & 0xC0) == 0x80)
                .count();
            &bytes[skip..]
        } else {
            bytes
        };
        clean_output(&String::from_utf8_lossy(bytes))
    }
}

/// Output as the server stores it: control characters but line breaks and
/// tabs become U+FFFD, so the JSON stays near the size of the text
pub fn clean_output(text: &str) -> String {
    text.chars()
        .map(|c| {
            if c.is_control() && !matches!(c, '\n' | '\r' | '\t') {
                '\u{FFFD}'
            } else {
                c
            }
        })
        .collect()
}

pub fn cap(text: &str) -> String {
    let mut tail = Tail::new(MAX_OUTPUT);
    tail.push(text.as_bytes());
    tail.text()
}

/// Runs `command` until it ends or `timeout` passes. On a timeout the
/// program and everything it started are killed. stdout and stderr end up
/// in one text, in the order they arrived.
pub fn run(mut command: Command, timeout: Duration) -> std::io::Result<Outcome> {
    command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    prepare(&mut command);
    let mut child = command.spawn()?;
    let tree = track(&child);
    let tail = Arc::new(Mutex::new(Tail::new(MAX_OUTPUT)));
    let (done_tx, done_rx) = mpsc::channel::<()>();
    let mut readers = 0;
    if let Some(stdout) = child.stdout.take() {
        readers += 1;
        read_into(stdout, tail.clone(), done_tx.clone());
    }
    if let Some(stderr) = child.stderr.take() {
        readers += 1;
        read_into(stderr, tail.clone(), done_tx.clone());
    }
    drop(done_tx);

    let deadline = Instant::now() + timeout;
    let mut timed_out = false;
    let status = loop {
        match child.try_wait()? {
            Some(status) => break Some(status),
            None if Instant::now() >= deadline => {
                timed_out = true;
                kill_tree(&mut child, &tree);
                break child.wait().ok();
            }
            None => std::thread::sleep(Duration::from_millis(50)),
        }
    };
    let drain_until = Instant::now() + DRAIN_WAIT;
    for _ in 0..readers {
        let left = drain_until.saturating_duration_since(Instant::now());
        if done_rx.recv_timeout(left).is_err() {
            break;
        }
    }
    let output = tail.lock().map(|tail| tail.text()).unwrap_or_default();
    Ok(Outcome {
        exit_code: if timed_out {
            None
        } else {
            status.and_then(|status| status.code())
        },
        output,
        timed_out,
    })
}

fn read_into(
    mut source: impl Read + Send + 'static,
    tail: Arc<Mutex<Tail>>,
    done: mpsc::Sender<()>,
) {
    std::thread::spawn(move || {
        let mut buffer = [0_u8; 8192];
        loop {
            match source.read(&mut buffer) {
                Ok(0) | Err(_) => break,
                Ok(n) => {
                    if let Ok(mut tail) = tail.lock() {
                        tail.push(&buffer[..n]);
                    }
                }
            }
        }
        let _ = done.send(());
    });
}

#[cfg(unix)]
fn prepare(command: &mut Command) {
    use std::os::unix::process::CommandExt;
    // A group of its own, so a timeout can end the whole tree
    command.process_group(0);
}

#[cfg(windows)]
fn prepare(command: &mut Command) {
    use std::os::windows::process::CommandExt;
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    command.creation_flags(CREATE_NO_WINDOW);
}

#[cfg(not(any(unix, windows)))]
fn prepare(_command: &mut Command) {}

/// What ends the program and everything it started
#[cfg(windows)]
type Tree = Option<super::win::Job>;
#[cfg(not(windows))]
type Tree = ();

#[cfg(windows)]
fn track(child: &std::process::Child) -> Tree {
    super::win::track(child)
}

#[cfg(not(windows))]
fn track(_child: &std::process::Child) -> Tree {}

#[cfg(unix)]
fn kill_tree(child: &mut std::process::Child, _tree: &Tree) {
    let pid = child.id() as i32;
    unsafe {
        hbb_common::libc::kill(-pid, hbb_common::libc::SIGKILL);
    }
    let _ = child.kill();
}

#[cfg(windows)]
fn kill_tree(child: &mut std::process::Child, tree: &Tree) {
    use std::os::windows::process::CommandExt;
    if let Some(job) = tree {
        job.kill();
    }
    // For a process that started before it joined the job
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    let _ = Command::new("taskkill.exe")
        .args(["/T", "/F", "/PID", &child.id().to_string()])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .creation_flags(CREATE_NO_WINDOW)
        .status();
    let _ = child.kill();
}

#[cfg(not(any(unix, windows)))]
fn kill_tree(child: &mut std::process::Child, _tree: &Tree) {
    let _ = child.kill();
}

/// A program with a short time limit, for the checks and settings of the
/// other fleet commands: its output, or why it failed
pub fn quick(program: &str, args: &[&str], timeout: Duration) -> Result<String, String> {
    let mut command = Command::new(program);
    command.args(args);
    match run(command, timeout) {
        Ok(outcome) if outcome.timed_out => Err(format!("{program} did not finish in time")),
        Ok(outcome) if outcome.exit_code == Some(0) => Ok(outcome.output),
        Ok(outcome) => Err(if outcome.output.trim().is_empty() {
            format!("{program} failed ({:?})", outcome.exit_code)
        } else {
            outcome.output.trim().to_owned()
        }),
        Err(err) => Err(format!("{program} could not start: {err}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_tail_keeps_the_last_bytes() {
        let mut tail = Tail::new(10);
        tail.push(b"0123456789abcdef");
        assert_eq!(tail.text(), "6789abcdef");
        for _ in 0..100 {
            tail.push(b"xy");
        }
        tail.push(b"END");
        assert_eq!(tail.text(), "yxyxyxyEND");
        let mut short = Tail::new(10);
        short.push(b"abc");
        assert_eq!(short.text(), "abc");
    }

    #[test]
    fn output_is_capped_at_64_kib_keeping_the_end() {
        let text = format!("{}{}", "a".repeat(MAX_OUTPUT), "the end");
        let capped = cap(&text);
        assert_eq!(capped.len(), MAX_OUTPUT);
        assert!(capped.ends_with("the end"));
        assert!(capped.starts_with('a'));
    }

    #[test]
    fn a_cut_never_splits_a_character() {
        // "ä" is two bytes: the cut falls into the first one
        let text = format!("{}{}", "ä".repeat(10), "z");
        let mut tail = Tail::new(6);
        tail.push(text.as_bytes());
        let kept = tail.text();
        assert!(!kept.contains('\u{FFFD}'), "{kept:?}");
        assert!(kept.ends_with("ääz"), "{kept:?}");
    }

    #[test]
    fn control_characters_do_not_reach_the_result() {
        assert_eq!(
            clean_output("a\u{1b}[31mb\n\tc\0"),
            "a\u{FFFD}[31mb\n\tc\u{FFFD}"
        );
    }

    #[cfg(unix)]
    fn shell(script: &str) -> Command {
        let mut command = Command::new("/bin/sh");
        command.arg("-c").arg(script);
        command
    }

    #[cfg(windows)]
    fn shell(script: &str) -> Command {
        use std::os::windows::process::CommandExt;
        // cmd reads its command line as it is, without the quoting of arg()
        let mut command = Command::new("cmd.exe");
        command.arg("/C").raw_arg(script);
        command
    }

    #[test]
    fn stdout_and_stderr_and_the_exit_code_come_back() {
        let outcome = run(
            shell("echo out && echo err 1>&2 && exit 3"),
            Duration::from_secs(20),
        )
        .unwrap();
        assert!(!outcome.timed_out);
        assert_eq!(outcome.exit_code, Some(3));
        assert!(outcome.output.contains("out"), "{:?}", outcome.output);
        assert!(outcome.output.contains("err"), "{:?}", outcome.output);
    }

    #[cfg(unix)]
    #[test]
    fn a_timeout_kills_the_program_and_what_it_started() {
        let marker =
            std::env::temp_dir().join(format!("neodesk-fleet-kill-{}", uuid::Uuid::new_v4()));
        let script = format!(
            "(sleep 2; touch '{}') & echo started; sleep 30",
            marker.display()
        );
        let begun = Instant::now();
        let outcome = run(shell(&script), Duration::from_millis(500)).unwrap();
        assert!(outcome.timed_out);
        assert_eq!(outcome.exit_code, None);
        assert!(outcome.output.contains("started"));
        assert!(
            begun.elapsed() < Duration::from_secs(10),
            "{:?}",
            begun.elapsed()
        );
        // The background child died with the group
        std::thread::sleep(Duration::from_secs(3));
        assert!(!marker.exists(), "a child outlived the timeout");
    }

    #[cfg(windows)]
    #[test]
    fn a_timeout_kills_the_program_and_what_it_started() {
        let marker =
            std::env::temp_dir().join(format!("neodesk-fleet-kill-{}", uuid::Uuid::new_v4()));
        // A second cmd that would write the marker after three seconds
        let script = format!(
            "start /b cmd /c \"ping -n 4 127.0.0.1 >nul & echo late> \"{}\"\" & echo started & ping -n 30 127.0.0.1 >nul",
            marker.display()
        );
        let begun = Instant::now();
        let outcome = run(shell(&script), Duration::from_millis(800)).unwrap();
        assert!(outcome.timed_out);
        assert_eq!(outcome.exit_code, None);
        assert!(outcome.output.contains("started"), "{:?}", outcome.output);
        assert!(
            begun.elapsed() < Duration::from_secs(10),
            "{:?}",
            begun.elapsed()
        );
        std::thread::sleep(Duration::from_secs(5));
        assert!(!marker.exists(), "a child outlived the timeout");
    }

    #[cfg(unix)]
    #[test]
    fn a_background_program_holding_the_pipe_does_not_hold_the_result() {
        let begun = Instant::now();
        let outcome = run(shell("sleep 20 & echo quick"), Duration::from_secs(30)).unwrap();
        assert_eq!(outcome.exit_code, Some(0));
        assert!(outcome.output.contains("quick"));
        assert!(
            begun.elapsed() < Duration::from_secs(8),
            "{:?}",
            begun.elapsed()
        );
    }
}
