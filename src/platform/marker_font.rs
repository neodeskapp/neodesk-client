//! The marker font an installed client puts on the computer. The console's
//! support page measures text in its family, "NeoDesk Marker", to tell that
//! NeoDesk is installed and offer to open the support link in it. The font
//! (res/marker-font) has one empty glyph and draws nothing.
//!
//! This file uses nothing but std, so its tests also run on their own:
//! `rustc --edition 2021 --test src/platform/marker_font.rs`.

use std::{fs, io, path::Path};

/// The font file, the same bytes on every platform.
pub const FONT: &[u8] = include_bytes!("../../res/marker-font/NeoDeskMarker.ttf");

/// Its file name in the fonts folder.
pub const FILE_NAME: &str = "NeoDeskMarker.ttf";

/// Puts the font into `fonts_dir` (a user's fonts folder) unless a file of
/// that name is there already. Writes a temporary file first and renames it,
/// so a font loader never sees half a font. True when it wrote the font.
pub fn ensure_in(fonts_dir: &Path) -> io::Result<bool> {
    let target = fonts_dir.join(FILE_NAME);
    if target.exists() {
        return Ok(false);
    }
    fs::create_dir_all(fonts_dir)?;
    let temporary = fonts_dir.join(format!(".{FILE_NAME}.{}", std::process::id()));
    let written = fs::write(&temporary, FONT).and_then(|_| fs::rename(&temporary, &target));
    if written.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    written.map(|_| true)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn empty_dir(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "neodesk_marker_font_{name}_{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        dir
    }

    fn utf16be(text: &str) -> Vec<u8> {
        text.encode_utf16().flat_map(|unit| unit.to_be_bytes()).collect()
    }

    #[test]
    fn the_font_is_the_marker_the_support_page_measures() {
        assert_eq!(&FONT[..4], &[0, 1, 0, 0], "not a TrueType font");
        for name in ["NeoDesk Marker", "NeoDesk Marker Regular"] {
            let encoded = utf16be(name);
            assert!(
                FONT.windows(encoded.len()).any(|window| window == encoded),
                "the font's name table has no {name:?}"
            );
        }
    }

    #[test]
    fn the_font_goes_into_a_fonts_folder_that_does_not_exist_yet() {
        let dir = empty_dir("new");
        let fonts = dir.join("Library").join("Fonts");
        assert!(ensure_in(&fonts).unwrap());
        assert_eq!(fs::read(fonts.join(FILE_NAME)).unwrap(), FONT);
        let left: Vec<_> = fs::read_dir(&fonts).unwrap().collect();
        assert_eq!(left.len(), 1, "a temporary file stayed behind");
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn a_font_that_is_there_is_left_alone() {
        let dir = empty_dir("there");
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join(FILE_NAME), b"kept").unwrap();
        assert!(!ensure_in(&dir).unwrap());
        assert_eq!(fs::read(dir.join(FILE_NAME)).unwrap(), b"kept");
        fs::remove_dir_all(dir).unwrap();
    }
}
