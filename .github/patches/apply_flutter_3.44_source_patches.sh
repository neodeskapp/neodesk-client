#!/usr/bin/env bash
# Applies the Flutter 3.44-only source/pubspec changes on the fly, in CI only.
#
# Windows arm64 needs Flutter >= 3.44 (the first stable release shipping an arm64 Dart SDK +
# engine), which takes DialogThemeData/TabBarThemeData/CardThemeData in ThemeData and needs newer
# extended_text/google_fonts. Every other platform is still on Flutter 3.24.5, where the old
# names/versions are required, so these changes are kept OUT of the committed sources and applied
# here instead.
#
# Used by BOTH the Windows arm64 build (flutter-build.yml) and its dedicated bridge artifact
# (bridge.yml) so they share an identical 3.44 source state -- the generated *.freezed.dart must
# compile against the same Flutter/freezed version the arm64 build resolves.
#
# Remove this script (and commit the changes) once upstream bumps Flutter across the board.
#
# Run from the repository root. sed is used (not a git-apply patch) because the checked-out
# sources are CRLF on the windows-11-arm runner; the substitutions below match within a line and
# are therefore CRLF-safe.
#
# Each substitution names a file, the text the committed sources have, the text Flutter 3.44
# needs, and how often it occurs. The script applies all of them, finds them all applied already,
# or stops when the sources match neither (a theme or pubspec change moved an anchor).
set -euo pipefail

readonly THEME=flutter/lib/common/theme/nd_theme.dart
readonly PUBSPEC=flutter/pubspec.yaml

# file | committed text | Flutter 3.44 text | occurrences
readonly SUBSTITUTIONS=(
  "$THEME|dialogTheme: DialogTheme(|dialogTheme: DialogThemeData(|1"
  "$THEME|tabBarTheme: TabBarTheme(|tabBarTheme: TabBarThemeData(|1"
  "$THEME|cardTheme: CardTheme(|cardTheme: CardThemeData(|1"
  "$PUBSPEC|extended_text: 14.0.0|extended_text: 15.0.2|1"
  "$PUBSPEC|google_fonts: ^6.2.1|google_fonts: ^8.1.0|1"
)

count() {
  grep -cF -- "$1" "$2" || true
}

# Prints "applied", "unpatched" or "drifted" for one substitution.
state_of() {
  local file old new expected old_count new_count
  IFS='|' read -r file old new expected <<<"$1"
  if [[ ! -r "$file" ]]; then
    echo "drifted"
    return
  fi
  old_count="$(count "$old" "$file")"
  new_count="$(count "$new" "$file")"
  if [[ "$old_count" -eq 0 && "$new_count" -eq "$expected" ]]; then
    echo "applied"
  elif [[ "$old_count" -eq "$expected" && "$new_count" -eq 0 ]]; then
    echo "unpatched"
  else
    echo "drifted"
  fi
}

all_in_state() {
  local wanted="$1" entry
  for entry in "${SUBSTITUTIONS[@]}"; do
    [[ "$(state_of "$entry")" == "$wanted" ]] || return 1
  done
}

report() {
  local entry file old new expected
  for entry in "${SUBSTITUTIONS[@]}"; do
    IFS='|' read -r file old new expected <<<"$entry"
    echo "  $(state_of "$entry"): $file: '$old' -> '$new' (expected $expected)" >&2
  done
}

# Escapes text for a sed pattern or replacement delimited by '|'.
escape() {
  printf '%s' "$1" | sed -e 's/[]\/$*.^[|&]/\\&/g'
}

if all_in_state applied; then
  echo "Flutter 3.44 source patches already applied."
  git --no-pager diff -- "$THEME" "$PUBSPEC"
  exit 0
fi

if ! all_in_state unpatched; then
  echo "Flutter 3.44 source patches are partially applied or their anchors have drifted:" >&2
  report
  exit 1
fi

for entry in "${SUBSTITUTIONS[@]}"; do
  IFS='|' read -r file old new expected <<<"$entry"
  sed -i "s|$(escape "$old")|$(escape "$new")|g" "$file"
done

# Fail loudly if any expected substitution did not produce the complete state.
if ! all_in_state applied; then
  echo "Flutter 3.44 source patches did not produce the expected state:" >&2
  report
  exit 1
fi

git --no-pager diff -- "$THEME" "$PUBSPEC"
