//! A picture of the screen for the receiver: the person adds it to a
//! message or a ticket ("Add a picture of my screen"). The window hides
//! itself before it asks (flutter/lib/receiver/receiver_screenshot.dart),
//! so the picture shows what the person sees behind it. The main screen
//! only, as a PNG file in the temporary folder.

use hbb_common::{bail, log, ResultType};
use scrap::{Capturer, Display, Frame, TraitCapturer, TraitPixelBuffer};
use std::{
    io::ErrorKind::WouldBlock,
    time::{Duration, Instant},
};

/// How long to wait for a frame of the screen.
const WAIT: Duration = Duration::from_secs(3);

/// Takes the picture and answers {"path", "size"} of the PNG file, or
/// {"error"} when the screen could not be read.
pub fn take_json() -> String {
    match take().and_then(|png| save(&png)) {
        Ok((path, size)) => serde_json::json!({"path": path, "size": size}).to_string(),
        Err(err) => {
            log::warn!("No picture of the screen: {err}");
            serde_json::json!({"error": err.to_string()}).to_string()
        }
    }
}

enum Outcome {
    Got(usize, usize, Vec<u8>),
    Wait,
    Failed(String),
}

/// The main screen as a PNG.
fn take() -> ResultType<Vec<u8>> {
    let display = Display::primary()?;
    let mut capturer = Capturer::new(display)?;
    let start = Instant::now();
    #[cfg(windows)]
    let mut tried_gdi = false;
    loop {
        let outcome = match capturer.frame(Duration::from_millis(200)) {
            Ok(Frame::PixelBuffer(f)) if !f.data().is_empty() => match rgba_of(&f) {
                Ok(rgba) => Outcome::Got(f.width(), f.height(), rgba),
                Err(err) => Outcome::Failed(err.to_string()),
            },
            Ok(Frame::PixelBuffer(_)) => Outcome::Wait,
            Ok(Frame::Texture(_)) => Outcome::Failed("the screen came as a texture".to_owned()),
            Err(err) if err.kind() == WouldBlock => Outcome::Wait,
            Err(err) => Outcome::Failed(err.to_string()),
        };
        match outcome {
            Outcome::Got(width, height, rgba) => return png(width, height, &rgba),
            Outcome::Wait if start.elapsed() < WAIT => continue,
            outcome => {
                // DXGI may refuse a window process; GDI reads the screen too
                #[cfg(windows)]
                if !tried_gdi && capturer.set_gdi() {
                    tried_gdi = true;
                    continue;
                }
                match outcome {
                    Outcome::Failed(err) => bail!(err),
                    _ => bail!("no picture of the screen came"),
                }
            }
        }
    }
}

/// The pixels as RGBA, row by row without padding.
fn rgba_of(f: &scrap::PixelBuffer) -> ResultType<Vec<u8>> {
    let (width, height) = (f.width(), f.height());
    let stride = f.stride().first().copied().unwrap_or(width * 4);
    let data = f.data();
    let bgra = matches!(f.pixfmt(), scrap::Pixfmt::BGRA);
    if !bgra && !matches!(f.pixfmt(), scrap::Pixfmt::RGBA) {
        bail!("the screen came in another pixel format");
    }
    rgba_rows(data, width, height, stride, bgra)
}

/// RGBA of `height` rows of `width` pixels, each row `stride` bytes long
/// in `data`, swapping red and blue when the pixels are BGRA.
fn rgba_rows(
    data: &[u8],
    width: usize,
    height: usize,
    stride: usize,
    bgra: bool,
) -> ResultType<Vec<u8>> {
    if stride < width * 4 || data.len() < stride * height.saturating_sub(1) + width * 4 {
        bail!("the picture of the screen is cut off");
    }
    let mut out = Vec::with_capacity(width * height * 4);
    for y in 0..height {
        let row = &data[y * stride..y * stride + width * 4];
        if bgra {
            for px in row.chunks_exact(4) {
                out.extend_from_slice(&[px[2], px[1], px[0], 255]);
            }
        } else {
            for px in row.chunks_exact(4) {
                out.extend_from_slice(&[px[0], px[1], px[2], 255]);
            }
        }
    }
    Ok(out)
}

fn png(width: usize, height: usize, rgba: &[u8]) -> ResultType<Vec<u8>> {
    // Fast: a 4K screen takes seconds at the smallest setting
    let mut png = Vec::new();
    let mut encoder = repng::Options::fastest(width as u32, height as u32).build(&mut png)?;
    encoder.write(rgba)?;
    encoder.finish()?;
    drop(encoder);
    Ok(png)
}

/// Saves the PNG as screen-<time>.png in the temporary folder.
fn save(png: &[u8]) -> ResultType<(String, u64)> {
    let dir = std::env::temp_dir().join("neodesk-screen");
    std::fs::create_dir_all(&dir)?;
    let name = chrono::Local::now().format("screen-%Y-%m-%d-%H%M%S.png").to_string();
    let path = dir.join(name);
    std::fs::write(&path, png)?;
    Ok((path.to_string_lossy().into_owned(), png.len() as u64))
}

#[cfg(test)]
mod tests {
    use super::rgba_rows;

    #[test]
    fn rows_lose_their_padding_and_bgra_turns_into_rgba() {
        // 2 x 2 pixels, rows of 12 bytes (4 bytes of padding)
        let data = [
            1, 2, 3, 0, 4, 5, 6, 0, 9, 9, 9, 9, //
            7, 8, 9, 0, 10, 11, 12, 0, 9, 9, 9, 9,
        ];
        assert_eq!(
            rgba_rows(&data, 2, 2, 12, true).unwrap(),
            [3, 2, 1, 255, 6, 5, 4, 255, 9, 8, 7, 255, 12, 11, 10, 255]
        );
        assert_eq!(
            rgba_rows(&data, 2, 2, 12, false).unwrap(),
            [1, 2, 3, 255, 4, 5, 6, 255, 7, 8, 9, 255, 10, 11, 12, 255]
        );
        assert!(rgba_rows(&data[..19], 2, 2, 12, true).is_err(), "cut off");
        assert!(rgba_rows(&data, 4, 2, 12, true).is_err(), "rows shorter than the width");
    }
}
