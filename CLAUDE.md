# Claude Tracker

Floating macOS widget (SwiftUI + AppKit, built with `swiftc`) that lists active Claude Code sessions.

## Rules

- Every button and clickable item must have a hover effect. Use the shared components in `Sources/Hover.swift` (`CircleIconButton`, `PillButtonStyle`, `ActionButtonStyle`, `PressScaleStyle`, `.hoverHighlight`). `bash tests/hover.sh` fails the build if a button or tap target has no hover style.
- Write code without comments.
- Never commit, push or release without the owner's explicit typed permission.
- Keep personal and company details out of the repo (it is public). Commits use the GitHub no-reply identity.
- Tests must never show windows on screen, steal focus or keystrokes, or change the user's real preferences. Use `--sample` mode.
- Screenshots in `docs/screenshots` come from sample data only.
- The shortcuts list in the README is generated from `Sources/Shortcuts.swift` by `scripts/update-readme.sh`. Do not edit it by hand.
- A new feature needs a test in `tests/` and an entry in `tests/run_all.sh`. Each suite must print "all passed".

## Commands

- Build: `scripts/build.sh`
- Test everything: `bash tests/run_all.sh`
- Install locally: `SKIP_BUILD=1 ./scripts/install-app.sh`
- Package a release: `scripts/package.sh`
