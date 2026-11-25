//! Where `--join` says its result on Windows (L521). The client is a
//! windowed program and has no console of its own. A script, an RMM tool or
//! an SSH session that starts it passes its output pipes, and the result
//! goes there. Started from a console window, it goes to that console. A
//! message box is left for a person at a visible desktop: elsewhere (an SSH
//! session, a service) nobody can close it, and the command never ended.
//!
//! This file uses nothing but std, so its tests also run on their own:
//! `rustc --edition 2021 --test src/onboard/cli_output.rs`.

/// Where a result went.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Channel {
    /// The output or error pipe the process got from whoever started it.
    Inherited,
    /// The console of the process that started this one.
    ParentConsole,
    /// Nowhere yet: the caller shows a message box.
    MessageBox,
    /// Nowhere: no pipe, no console and no desktop anyone sees.
    Nowhere,
}

/// The ways this process can say something, tried in the order of [`say`].
pub trait Outputs {
    /// Writes to the inherited output (or error) pipe; false without one.
    fn inherited(&mut self, text: &str, error: bool) -> bool;
    /// Attaches to the starting process's console and writes there; false
    /// without one.
    fn parent_console(&mut self, text: &str) -> bool;
    /// Whether this process's desktop is one a person sees.
    fn visible_desktop(&self) -> bool;
}

/// Says `text`: through the first output that takes it.
pub fn say(out: &mut impl Outputs, text: &str, error: bool) -> Channel {
    if out.inherited(text, error) {
        Channel::Inherited
    } else if out.parent_console(text) {
        Channel::ParentConsole
    } else if out.visible_desktop() {
        Channel::MessageBox
    } else {
        Channel::Nowhere
    }
}

/// This process's outputs on Windows.
#[cfg(windows)]
pub struct Process;

#[cfg(windows)]
mod sys {
    use std::ffi::c_void;
    pub const STD_OUTPUT_HANDLE: u32 = -11i32 as u32;
    pub const STD_ERROR_HANDLE: u32 = -12i32 as u32;
    pub const FILE_TYPE_UNKNOWN: u32 = 0;
    pub const ATTACH_PARENT_PROCESS: u32 = u32::MAX;
    pub const UOI_FLAGS: i32 = 1;
    pub const WSF_VISIBLE: u32 = 1;

    #[repr(C)]
    #[derive(Default)]
    pub struct UserObjectFlags {
        pub inherit: i32,
        pub reserved: i32,
        pub flags: u32,
    }

    #[link(name = "kernel32")]
    extern "system" {
        pub fn GetStdHandle(which: u32) -> *mut c_void;
        pub fn GetFileType(handle: *mut c_void) -> u32;
        pub fn AttachConsole(process: u32) -> i32;
    }

    #[link(name = "user32")]
    extern "system" {
        pub fn GetProcessWindowStation() -> *mut c_void;
        pub fn GetUserObjectInformationW(
            object: *mut c_void,
            index: i32,
            info: *mut c_void,
            length: u32,
            needed: *mut u32,
        ) -> i32;
    }
}

#[cfg(windows)]
impl Outputs for Process {
    fn inherited(&mut self, text: &str, error: bool) -> bool {
        use std::io::Write;
        let which = if error {
            sys::STD_ERROR_HANDLE
        } else {
            sys::STD_OUTPUT_HANDLE
        };
        // SAFETY: plain queries of this process's standard handle
        let handle = unsafe { sys::GetStdHandle(which) };
        if handle.is_null()
            || handle as isize == -1
            || unsafe { sys::GetFileType(handle) } == sys::FILE_TYPE_UNKNOWN
        {
            return false;
        }
        if error {
            let mut err = std::io::stderr();
            writeln!(err, "{text}").and_then(|_| err.flush()).is_ok()
        } else {
            let mut out = std::io::stdout();
            writeln!(out, "{text}").and_then(|_| out.flush()).is_ok()
        }
    }

    fn parent_console(&mut self, text: &str) -> bool {
        use std::io::Write;
        // SAFETY: attaching fails harmlessly when the parent has no console
        if unsafe { sys::AttachConsole(sys::ATTACH_PARENT_PROCESS) } == 0 {
            return false;
        }
        match std::fs::OpenOptions::new().write(true).open("CONOUT$") {
            Ok(mut console) => writeln!(console, "\n{text}").is_ok(),
            Err(_) => false,
        }
    }

    fn visible_desktop(&self) -> bool {
        let mut flags = sys::UserObjectFlags::default();
        let mut needed = 0u32;
        // SAFETY: the window station handle is this process's own and the
        // buffer is the size the call is told
        let ok = unsafe {
            sys::GetUserObjectInformationW(
                sys::GetProcessWindowStation(),
                sys::UOI_FLAGS,
                &mut flags as *mut _ as *mut std::ffi::c_void,
                std::mem::size_of::<sys::UserObjectFlags>() as u32,
                &mut needed,
            )
        };
        ok != 0 && flags.flags & sys::WSF_VISIBLE != 0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Default)]
    struct Fake {
        pipe: bool,
        console: bool,
        desktop: bool,
        written: Vec<(String, &'static str)>,
    }

    impl Outputs for Fake {
        fn inherited(&mut self, text: &str, error: bool) -> bool {
            if self.pipe {
                let to = if error { "stderr" } else { "stdout" };
                self.written.push((text.to_owned(), to));
            }
            self.pipe
        }
        fn parent_console(&mut self, text: &str) -> bool {
            if self.console {
                self.written.push((text.to_owned(), "console"));
            }
            self.console
        }
        fn visible_desktop(&self) -> bool {
            self.desktop
        }
    }

    /// L521: started over SSH or by an RMM tool, the result goes to the
    /// pipes it was given, and no message box waits for a click nobody can
    /// make.
    #[test]
    fn a_started_command_with_pipes_prints_there() {
        let mut out = Fake {
            pipe: true,
            desktop: false,
            ..Default::default()
        };
        assert_eq!(say(&mut out, "joined", false), Channel::Inherited);
        assert_eq!(say(&mut out, "failed", true), Channel::Inherited);
        assert_eq!(
            out.written,
            vec![
                ("joined".to_owned(), "stdout"),
                ("failed".to_owned(), "stderr")
            ]
        );
    }

    #[test]
    fn a_console_window_gets_the_result() {
        let mut out = Fake {
            console: true,
            desktop: true,
            ..Default::default()
        };
        assert_eq!(say(&mut out, "joined", false), Channel::ParentConsole);
    }

    #[test]
    fn a_message_box_only_on_a_visible_desktop() {
        let mut person = Fake {
            desktop: true,
            ..Default::default()
        };
        assert_eq!(say(&mut person, "joined", false), Channel::MessageBox);
        let mut nobody = Fake::default();
        assert_eq!(say(&mut nobody, "joined", false), Channel::Nowhere);
    }

    /// The real outputs: a child process with piped output gets the text on
    /// its pipes and ends.
    #[cfg(windows)]
    #[test]
    fn the_process_prints_to_its_pipes() {
        if let Ok(text) = std::env::var("NEODESK_CLI_OUTPUT_TEST") {
            assert_eq!(say(&mut Process, &text, false), Channel::Inherited);
            assert_eq!(say(&mut Process, "to stderr", true), Channel::Inherited);
            return;
        }
        let exe = std::env::current_exe().unwrap();
        let module = module_path!();
        let name = match module.split_once("::") {
            Some((_, rest)) => format!("{rest}::the_process_prints_to_its_pipes"),
            None => "tests::the_process_prints_to_its_pipes".to_owned(),
        };
        let output = std::process::Command::new(exe)
            .args(["--exact", "--nocapture", &name])
            .env(
                "NEODESK_CLI_OUTPUT_TEST",
                "This computer joined example. ID: 1",
            )
            .output()
            .unwrap();
        assert!(output.status.success());
        assert!(
            String::from_utf8_lossy(&output.stdout).contains("This computer joined example. ID: 1")
        );
        assert!(String::from_utf8_lossy(&output.stderr).contains("to stderr"));
    }
}
