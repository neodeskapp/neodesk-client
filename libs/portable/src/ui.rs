//! The window the packer shows from a double-click until the client's own
//! window is up: the NeoDesk logo, what it is doing and how far it got.
//! White like the MSI's pages, sized for the display's scaling.

use native_windows_gui as nwg;
use std::{
    cell::RefCell,
    rc::Rc,
    sync::atomic::{AtomicBool, AtomicUsize, Ordering},
};

/// Files written so far and in all, while unpacking.
static DONE: AtomicUsize = AtomicUsize::new(0);
static TOTAL: AtomicUsize = AtomicUsize::new(0);
/// Unpacked; the client is starting.
static STARTING: AtomicBool = AtomicBool::new(false);

// The console palette's light surface and rule, and the logo's blue.
const BG: [u8; 3] = [0xff, 0xff, 0xff];
const RULE: [u8; 3] = [0xdd, 0xe1, 0xe2];
const BLUE: [u8; 3] = [0x1f, 0x6f, 0xeb];

/// The full logo on white, rendered from the owner's SVG at these heights.
const LOGOS: [(u32, &[u8]); 4] = [
    (28, include_bytes!("./res/splash-logo-light-28.png")),
    (35, include_bytes!("./res/splash-logo-light-35.png")),
    (42, include_bytes!("./res/splash-logo-light-42.png")),
    (56, include_bytes!("./res/splash-logo-light-56.png")),
];

// The layout at 100 %.
const WIDTH: i32 = 400;
const HEIGHT: i32 = 136;
const MARGIN: i32 = 32;
const LOGO_TOP: i32 = 28;
const LOGO_HEIGHT: u32 = 28;
const TEXT_TOP: i32 = 70;
const TEXT_SIZE: i32 = 12;
const BAR_TOP: i32 = 102;
const BAR_HEIGHT: i32 = 4;

pub fn set_progress(done: usize, total: usize) {
    TOTAL.store(total, Ordering::Relaxed);
    DONE.store(done, Ordering::Relaxed);
}

pub fn set_starting() {
    STARTING.store(true, Ordering::Relaxed);
}

/// The words in the person's Windows language: German or English.
fn texts() -> (&'static str, &'static str) {
    let lang = unsafe { winapi::um::winnls::GetUserDefaultUILanguage() };
    if lang & 0x3ff == 0x07 {
        ("NeoDesk wird entpackt\u{2026}", "NeoDesk wird gestartet\u{2026}")
    } else {
        ("Unpacking NeoDesk\u{2026}", "Starting NeoDesk\u{2026}")
    }
}

/// The display scaling (ui() makes the process DPI aware first); Windows 7
/// has no GetDpiForSystem, so the screen's device context tells it.
fn scale() -> f64 {
    use winapi::um::{wingdi, winuser};
    let dpi = unsafe {
        let dc = winuser::GetDC(std::ptr::null_mut());
        if dc.is_null() {
            0
        } else {
            let dpi = wingdi::GetDeviceCaps(dc, wingdi::LOGPIXELSX);
            winuser::ReleaseDC(std::ptr::null_mut(), dc);
            dpi
        }
    };
    if dpi <= 0 {
        1.0
    } else {
        dpi as f64 / 96.0
    }
}

#[derive(Default)]
struct Splash {
    window: nwg::Window,
    border: nwg::ImageFrame,
    inner: nwg::ImageFrame,
    logo: nwg::ImageFrame,
    label: nwg::Label,
    track: nwg::ImageFrame,
    fill: nwg::ImageFrame,
    timer: nwg::AnimationTimer,
    font: nwg::Font,
    logo_bitmap: Option<nwg::Bitmap>,
    bar_width: usize,
    bar_height: u32,
    /// The step and bar width on screen; None until the first tick.
    shown: RefCell<Option<(bool, usize)>>,
}

impl Splash {
    /// Shows the step and how far it got. The packer ends, and the window
    /// with it, once the client's window is up.
    fn tick(&self) {
        let starting = STARTING.load(Ordering::Relaxed);
        let total = TOTAL.load(Ordering::Relaxed);
        let width = if starting {
            self.bar_width
        } else if total == 0 {
            0
        } else {
            self.bar_width * DONE.load(Ordering::Relaxed).min(total) / total
        };
        let mut shown = self.shown.borrow_mut();
        if *shown == Some((starting, width)) {
            return;
        }
        // The text is set here, not when the label is built: set then, the
        // label paints the dialog grey behind it until the first change.
        if shown.map(|(s, _)| s) != Some(starting) {
            let (unpacking, start) = texts();
            self.label.set_text(if starting { start } else { unpacking });
        }
        self.fill.set_visible(width > 0);
        self.fill.set_size(width.max(1) as u32, self.bar_height);
        *shown = Some((starting, width));
    }
}

/// The logo at `height` pixels and its size: a rendering of that height, or
/// the next larger one scaled down.
fn logo_bitmap(
    decoder: &nwg::ImageDecoder,
    height: u32,
) -> Result<(nwg::Bitmap, (u32, u32)), nwg::NwgError> {
    let (rendered, bytes) = LOGOS
        .iter()
        .find(|(h, _)| *h >= height)
        .unwrap_or(&LOGOS[LOGOS.len() - 1]);
    let image = decoder.from_stream(bytes)?.frame(0)?;
    let (w, h) = image.size();
    if *rendered == height {
        return Ok((image.as_bitmap()?, (w, h)));
    }
    let width = (w as u64 * height as u64 / h.max(1) as u64) as u32;
    let image = decoder.resize_image(&image, [width, height])?;
    Ok((image.as_bitmap()?, (width, height)))
}

fn build() -> Result<Rc<Splash>, nwg::NwgError> {
    let s = scale();
    let px = |v: i32| (v as f64 * s).round() as i32;
    let mut ui = Splash::default();

    let decoder = nwg::ImageDecoder::new()?;
    let logo_height = px(LOGO_HEIGHT as i32) as u32;
    let (logo, logo_size) = logo_bitmap(&decoder, logo_height)?;
    ui.logo_bitmap = Some(logo);

    nwg::Font::builder()
        .family("Segoe UI")
        .size_absolute(px(TEXT_SIZE) as u32)
        .build(&mut ui.font)?;

    let (w, h) = (px(WIDTH), px(HEIGHT));
    nwg::Window::builder()
        .flags(nwg::WindowFlags::POPUP | nwg::WindowFlags::VISIBLE)
        .size((w, h))
        .center(true)
        .title("NeoDesk")
        .build(&mut ui.window)?;
    nwg::ImageFrame::builder()
        .parent(&ui.window)
        .size((w, h))
        .background_color(Some(RULE))
        .build(&mut ui.border)?;
    let edge = px(1).max(1);
    nwg::ImageFrame::builder()
        .parent(&ui.border)
        .position((edge, edge))
        .size((w - 2 * edge, h - 2 * edge))
        .background_color(Some(BG))
        .build(&mut ui.inner)?;
    // Positions inside the inner frame are one border width less.
    let at = |v: i32| px(v) - edge;
    nwg::ImageFrame::builder()
        .parent(&ui.inner)
        .position((at(MARGIN), at(LOGO_TOP)))
        .size((logo_size.0 as i32, logo_size.1 as i32))
        .background_color(Some(BG))
        .bitmap(ui.logo_bitmap.as_ref())
        .build(&mut ui.logo)?;
    let content = w - 2 * px(MARGIN);
    nwg::Label::builder()
        .parent(&ui.inner)
        .position((at(MARGIN), at(TEXT_TOP)))
        .size((content, px(TEXT_SIZE * 2)))
        .font(Some(&ui.font))
        .background_color(Some(BG))
        .text("")
        .build(&mut ui.label)?;
    ui.bar_width = content.max(1) as usize;
    ui.bar_height = px(BAR_HEIGHT).max(2) as u32;
    nwg::ImageFrame::builder()
        .parent(&ui.inner)
        .position((at(MARGIN), at(BAR_TOP)))
        .size((content, ui.bar_height as i32))
        .background_color(Some(RULE))
        .build(&mut ui.track)?;
    nwg::ImageFrame::builder()
        .parent(&ui.track)
        .position((0, 0))
        .size((1, ui.bar_height as i32))
        .background_color(Some(BLUE))
        .build(&mut ui.fill)?;
    ui.fill.set_visible(false);
    nwg::AnimationTimer::builder()
        .parent(&ui.window)
        .interval(std::time::Duration::from_millis(50))
        .build(&mut ui.timer)?;

    let ui = Rc::new(ui);
    let weak = Rc::downgrade(&ui);
    let handler = nwg::full_bind_event_handler(&ui.window.handle, move |evt, _data, _handle| {
        if let Some(ui) = weak.upgrade() {
            match evt {
                nwg::Event::OnTimerTick => ui.tick(),
                nwg::Event::OnWindowClose => {
                    ui.timer.stop();
                    nwg::stop_thread_dispatch();
                }
                _ => {}
            }
        }
    });
    ui.timer.start();
    // The handler lives as long as the window; the process ends with it.
    std::mem::forget(handler);
    Ok(ui)
}

fn ui() -> Result<(), nwg::NwgError> {
    // The released packer carries the Flutter runner's resources, not a
    // DPI-aware manifest; without this Windows stretches the window at 150 %
    // and the logo blurs. It must come before the first window.
    unsafe { winapi::um::winuser::SetProcessDPIAware() };
    nwg::init()?;
    let _ui = build()?;
    nwg::dispatch_thread_events();
    Ok(())
}

pub fn setup() {
    std::thread::spawn(move || {
        if let Err(e) = ui() {
            eprintln!("{:?}", e);
        }
    });
}
