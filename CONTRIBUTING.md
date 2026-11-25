# Contributing to NeoDesk Client

Changes come in as pull requests against `main`. Questions and ideas go to
the [NeoDesk Discord](https://discord.gg/nwERSawufr) or the
[Discussions of neodeskapp/neodesk](https://github.com/neodeskapp/neodesk/discussions).
This repository has no issue tracker. Report security problems privately,
as [SECURITY.md](SECURITY.md) describes.

## Build the client

[docs/BUILD_DESKTOP.md](docs/BUILD_DESKTOP.md) has the full steps for
Windows x64 and Linux x64, with the tool versions CI uses (Flutter 3.24.5,
Rust 1.75, vcpkg, LLVM/Clang). In short:

```sh
git submodule update --init --recursive
python build.py --flutter --hwcodec --vram --skip-portable-pack   # Windows
python3 ./build.py --flutter --hwcodec                            # Linux
```

On Windows, `scripts/check_desktop_env_windows.ps1` checks the toolchain
first.

## Check your change

- The colour check that CI runs on every change to `flutter/lib`:
  `python3 flutter/tool/check_colours.py`. Colours come from the tokens in
  `flutter/lib/common/theme/nd_theme.dart`.
- The Flutter tests and the analyzer, in `flutter/`: `flutter test` and
  `flutter analyze`. They need `flutter/lib/generated_bridge.dart`, which
  is not in the repository. Generate it with `flutter_rust_bridge_codegen`
  1.80.1 as `.github/workflows/bridge.yml` does, or take it from the
  bridge artifact of a CI run.
- Icons come from Material Symbols through `NdIcons`. To add one, add its
  line to `flutter/tool/nd_symbols.txt` and run
  `python3 tool/build_symbols.py` in `flutter/`.
- Add a test that fails without your change where a widget test can reach
  the code.

## Commit messages

Write the subject as `type: summary`, without a scope: `fix: keep the
window size after a restart`, not `fix(window): ...`. The types are
`feat`, `fix`, `refactor`, `chore`, `docs`, `test` and `ci`. Write the
summary in lowercase, in the imperative, without a full stop at the end,
and say what changes for the user. Keep each commit to one change.

## Licence

NeoDesk Client is licensed under the AGPL-3.0 (see [LICENCE](LICENCE)).
By sending a change, you agree that it is licensed under the same terms.
The client is built on RustDesk; keep its copyright and licence notices
in the files you change.
