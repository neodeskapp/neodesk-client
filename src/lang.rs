use hbb_common::regex::Regex;
use std::ops::Deref;

mod ar;
mod be;
mod bg;
mod ca;
mod cn;
mod cs;
mod da;
mod de;
mod el;
mod en;
mod eo;
mod es;
mod et;
mod eu;
mod fa;
mod gu;
mod fr;
mod he;
mod hi;
mod hr;
mod hu;
mod id;
mod it;
mod ja;
mod ko;
mod kz;
mod lt;
mod lv;
mod nb;
mod nl;
mod pl;
mod ptbr;
mod ro;
mod ru;
mod sc;
mod sk;
mod sl;
mod sq;
mod sr;
mod sv;
mod th;
mod tr;
mod tw;
mod uk;
mod ur;
mod vi;
mod ta;
mod ge;
mod fi;
mod ml;

pub const LANGS: &[(&str, &str)] = &[
    ("en", "English"),
    ("it", "Italiano"),
    ("fr", "Français"),
    ("de", "Deutsch"),
    ("nl", "Nederlands"),
    ("nb", "Norsk bokmål"),
    ("zh-cn", "简体中文"),
    ("zh-tw", "繁體中文"),
    ("pt", "Português"),
    ("es", "Español"),
    ("et", "Eesti keel"),
    ("eu", "Euskara"),
    ("hu", "Magyar"),
    ("bg", "Български"),
    ("be", "Беларуская"),
    ("ru", "Русский"),
    ("sk", "Slovenčina"),
    ("id", "Indonesia"),
    ("cs", "Čeština"),
    ("da", "Dansk"),
    ("eo", "Esperanto"),
    ("tr", "Türkçe"),
    ("vi", "Tiếng Việt"),
    ("pl", "Polski"),
    ("ja", "日本語"),
    ("ko", "한국어"),
    ("kz", "Қазақ"),
    ("uk", "Українська"),
    ("ur", "اردو"),
    ("fa", "فارسی"),
    ("ca", "Català"),
    ("el", "Ελληνικά"),
    ("sv", "Svenska"),
    ("sq", "Shqip"),
    ("sr", "Srpski"),
    ("th", "ภาษาไทย"),
    ("sl", "Slovenščina"),
    ("ro", "Română"),
    ("lt", "Lietuvių"),
    ("lv", "Latviešu"),
    ("ar", "العربية"),
    ("he", "עברית"),
    ("hr", "Hrvatski"),
    ("sc", "Sardu"),
    ("ta", "தமிழ்"),
    ("ge", "ქართული"),
    ("fi", "Suomi"),
    ("ml", "മലയാളം"),
    ("hi", "हिंदी"),
    ("gu", "ગુજરાતી"),
];

pub(crate) fn cjk_ui_unavailable() -> bool {
    cfg!(all(
        target_os = "linux",
        target_arch = "aarch64",
        feature = "flutter"
    ))
}

pub(crate) fn is_cjk_lang(lang_or_locale: &str) -> bool {
    let lang = lang_or_locale
        .split(|c| c == '-' || c == '_')
        .next()
        .unwrap_or_default()
        .to_lowercase();
    matches!(lang.as_str(), "zh" | "ja" | "ko")
}

fn resolve_lang(saved_lang: &str, locale: &str, cjk_fallback: bool) -> String {
    let locale = locale.to_lowercase();
    let mut lang = saved_lang.to_lowercase();
    if cjk_fallback && is_cjk_lang(&lang) {
        return "en".to_owned();
    }
    if lang.is_empty() {
        // zh_CN on Linux, zh-Hans-CN on mac, zh_CN_#Hans on Android
        if locale.starts_with("zh") {
            lang = (if locale.contains("tw") {
                "zh-tw"
            } else {
                "zh-cn"
            })
            .to_owned();
        }
    }
    if lang.is_empty() {
        lang = locale
            .split("-")
            .next()
            .map(|x| x.split("_").next().unwrap_or_default())
            .unwrap_or_default()
            .to_owned();
    }
    if cjk_fallback && is_cjk_lang(&lang) {
        "en".to_owned()
    } else {
        lang
    }
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn translate(name: String) -> String {
    let locale = sys_locale::get_locale().unwrap_or_default();
    translate_locale(name, &locale)
}

pub fn translate_locale(name: String, locale: &str) -> String {
    let lang = resolve_lang(
        &hbb_common::config::LocalConfig::get_option("lang"),
        locale,
        cjk_ui_unavailable(),
    );
    let m = match lang.as_str() {
        "fr" => fr::T.deref(),
        "zh-cn" => cn::T.deref(),
        "it" => it::T.deref(),
        "zh-tw" => tw::T.deref(),
        "de" => de::T.deref(),
        "nb" => nb::T.deref(),
        "nl" => nl::T.deref(),
        "es" => es::T.deref(),
        "et" => et::T.deref(),
        "eu" => eu::T.deref(),
        "hu" => hu::T.deref(),
        "ru" => ru::T.deref(),
        "eo" => eo::T.deref(),
        "id" => id::T.deref(),
        "br" => ptbr::T.deref(),
        "pt" => ptbr::T.deref(),
        "tr" => tr::T.deref(),
        "cs" => cs::T.deref(),
        "da" => da::T.deref(),
        "sk" => sk::T.deref(),
        "vi" => vi::T.deref(),
        "pl" => pl::T.deref(),
        "ja" => ja::T.deref(),
        "ko" => ko::T.deref(),
        "kz" => kz::T.deref(),
        "uk" => uk::T.deref(),
        "fa" => fa::T.deref(),
        "fi" => fi::T.deref(),
        "ca" => ca::T.deref(),
        "el" => el::T.deref(),
        "sv" => sv::T.deref(),
        "sq" => sq::T.deref(),
        "sr" => sr::T.deref(),
        "th" => th::T.deref(),
        "sl" => sl::T.deref(),
        "ro" => ro::T.deref(),
        "lt" => lt::T.deref(),
        "lv" => lv::T.deref(),
        "ar" => ar::T.deref(),
        "bg" => bg::T.deref(),
        "be" => be::T.deref(),
        "he" => he::T.deref(),
        "hr" => hr::T.deref(),
        "ur" => ur::T.deref(),
        "sc" => sc::T.deref(),
        "ta" => ta::T.deref(),
        "ge" => ge::T.deref(),
        "ml" => ml::T.deref(),
        "hi" => hi::T.deref(),
        "gu" => gu::T.deref(),
        _ => en::T.deref(),
    };
    let (name, placeholder_value) = extract_placeholder(&name);
    let replace = |s: &&str| {
        let mut s = s.to_string();
        if let Some(value) = placeholder_value.as_ref() {
            s = s.replace("{}", &value);
        }
        if !crate::is_rustdesk() {
            s = with_app_name(&name, s, &crate::get_app_name());
        }
        s
    };
    if let Some(v) = m.get(&name as &str) {
        if !v.is_empty() {
            return replace(v);
        }
    }
    if lang != "en" {
        if let Some(v) = en::T.get(&name as &str) {
            if !v.is_empty() {
                return replace(v);
            }
        }
    }
    replace(&name.as_str())
}

/// Texts that credit RustDesk as upstream: they keep its name and its
/// copyright holder as upstream wrote them (the AGPL notice depends on it).
const UPSTREAM_CREDITS: &[&str] = &[
    "powered_by_me",
    "nd-about-copyright",
    "neodesk_fork_attribution_tip",
];

/// Puts the app's own name where a text says "RustDesk", except in the
/// credits and in the hints about RustDesk Server Pro.
fn with_app_name(name: &str, s: String, app_name: &str) -> String {
    if !s.contains("RustDesk")
        || name.starts_with("upgrade_rustdesk_server_pro")
        || UPSTREAM_CREDITS.contains(&name)
    {
        return s;
    }
    if !app_name.contains("RustDesk") {
        return s.replace("RustDesk", app_name);
    }
    // https://github.com/rustdesk/rustdesk-server-pro/issues/845
    // If app_name contains "RustDesk" (e.g., "RustDesk-Admin"), we need to avoid
    // replacing "RustDesk" within the already-substituted app_name, which would
    // cause duplication like "RustDesk-Admin" -> "RustDesk-Admin-Admin".
    //
    // app_name only contains alphanumeric and hyphen.
    const PLACEHOLDER: &str = "#A-P-P-N-A-M-E#";
    if s.contains(PLACEHOLDER) {
        // It's very unlikely to reach here.
        // Skip replacement to avoid incorrect result.
        return s;
    }
    s.replace(app_name, PLACEHOLDER)
        .replace("RustDesk", app_name)
        .replace(PLACEHOLDER, app_name)
}

// Matching pattern is {}
// Write {value} in the UI and {} in the translation file
//
// Example:
// Write in the UI: translate("There are {24} hours in a day")
// Write in the translation file: ("There are {} hours in a day", "{} hours make up a day")
fn extract_placeholder(input: &str) -> (String, Option<String>) {
    if let Ok(re) = Regex::new(r#"\{(.*?)\}"#) {
        if let Some(captures) = re.captures(input) {
            if let Some(inner_match) = captures.get(1) {
                let name = re.replace(input, "{}").to_string();
                let value = inner_match.as_str().to_string();
                return (name, Some(value));
            }
        }
    }
    (input.to_string(), None)
}

mod test {
    #[test]
    fn test_extract_placeholders() {
        use super::extract_placeholder as f;

        assert_eq!(f(""), ("".to_string(), None));
        assert_eq!(
            f("{3} sessions"),
            ("{} sessions".to_string(), Some("3".to_string()))
        );
        assert_eq!(f(" } { "), (" } { ".to_string(), None));
        // Allow empty value
        assert_eq!(
            f("{} sessions"),
            ("{} sessions".to_string(), Some("".to_string()))
        );
        // Match only the first one
        assert_eq!(
            f("{2} times {4} makes {8}"),
            ("{} times {4} makes {8}".to_string(), Some("2".to_string()))
        );
    }

    #[test]
    fn test_credits_keep_the_rustdesk_name() {
        use super::with_app_name as f;
        let langs = [("en", &*super::en::T), ("de", &*super::de::T), ("pl", &*super::pl::T)];
        for (lang, texts) in langs {
            for key in ["nd-about-copyright", "neodesk_fork_attribution_tip", "powered_by_me"] {
                let text = texts.get(key).copied().unwrap_or_default();
                assert_eq!(f(key, text.to_owned(), "NeoDesk Client"), text, "{lang} {key}");
            }
        }
        let credit = "Based on RustDesk, copyright Purslane Ltd. and the RustDesk contributors.";
        assert!(super::en::T["nd-about-copyright"].contains(credit));
        let status = "Connecting to the RustDesk network...".to_owned();
        assert_eq!(
            f("connecting_status", status, "NeoDesk Client"),
            "Connecting to the NeoDesk Client network..."
        );
        assert_eq!(
            f("connecting_status", "RustDesk".to_owned(), "RustDesk-Admin"),
            "RustDesk-Admin"
        );
    }

    /// The German texts address the reader with "du". "Sie" and the capitalised
    /// forms of "Ihr" are the formal address, except where a text means
    /// "they", "their" or "it"; those texts are listed with the word.
    #[test]
    fn test_german_says_du() {
        const NOT_YOU: &[(&str, &str)] = &[
            // The session toolbar's "their sound", "their cursor", "their
            // computer", "their sign-in password", "their active window" and
            // "their screens": the other computer's, at the start of the label.
            ("Mute", "Ihren"),
            ("Show remote cursor", "Ihren"),
            ("Insert Lock", "Ihren"),
            ("OS Password", "Ihr"),
            ("Follow remote cursor", "Ihrem"),
            ("Follow remote window focus", "Ihrem"),
            ("nd-tb-their-computer", "Ihr"),
            ("nd-set-row-show-their-screens-in-the-toolbar", "Ihre"),
            // "Let them control this computer".
            ("Switch Sides", "Sie"),
            // "It": the server address, then the invite.
            ("nd-invite-server-hint", "Sie"),
            ("nd-join-failed-next-refused", "Sie"),
        ];
        let formal =
            super::Regex::new(r"\b(Sie|Ihr|Ihre|Ihren|Ihrem|Ihrer|Ihres|Ihnen)\b").unwrap();
        let mut found = Vec::new();
        for (key, text) in super::de::T.iter() {
            for word in formal.find_iter(text) {
                if !NOT_YOU.contains(&(*key, word.as_str())) {
                    found.push(format!("{key}: {text}"));
                }
            }
        }
        found.sort();
        found.dedup();
        assert!(
            found.is_empty(),
            "formal address in de.rs:\n{}",
            found.join("\n")
        );
        for (key, word) in NOT_YOU {
            let text = super::de::T.get(key).copied().unwrap_or_default();
            assert!(
                formal.find_iter(text).any(|m| m.as_str() == *word),
                "{key} no longer has {word}, drop it from the list"
            );
        }
    }

    #[test]
    fn test_resolve_lang_forces_english_for_saved_cjk_when_target_disables_cjk() {
        use super::resolve_lang as f;

        assert_eq!(f("zh-cn", "en-US", true), "en");
        assert_eq!(f("zh-tw", "en-US", true), "en");
        assert_eq!(f("ja", "en-US", true), "en");
        assert_eq!(f("ko", "en-US", true), "en");
    }

    #[test]
    fn test_resolve_lang_forces_english_for_cjk_locale_when_target_disables_cjk() {
        use super::resolve_lang as f;

        assert_eq!(f("", "zh_CN", true), "en");
        assert_eq!(f("", "ja-JP", true), "en");
        assert_eq!(f("", "ko_KR", true), "en");
    }

    #[test]
    fn test_resolve_lang_preserves_cjk_when_target_allows_cjk() {
        use super::resolve_lang as f;

        assert_eq!(f("zh-cn", "en-US", false), "zh-cn");
        assert_eq!(f("", "zh_TW", false), "zh-tw");
        assert_eq!(f("", "ja-JP", false), "ja");
    }
}
