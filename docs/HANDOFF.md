# Menu and diagnostics handoff

This document describes the menu polish following the initial brightness-offset MVP. It is a behavior/verification reference, not a live release status or permission to publish or install.

## Accepted behavior

- Native Pause/Resume, Settings and Quit rows have icons and system selection behavior. Settings uses the SwiftUI Settings action through an invisible bridge.
- Independent lights and groups opted into Show in menu follow manual sidebar order. A small switch next to each name controls persisted Sync. Turning Sync off retains the row and offset, disables its slider and cancels pending sends; it does not power off the lamps.
- Sliders adjust visible brightness by −30 to +30 points. The filled track starts at zero and extends toward the thumb. Groups share one effective offset and Sync setting.
- A compact floating bubble shows only a signed number, or zero, during mouse pressure on the track or thumb. There is no persistent numeric label, Reset button, scale text, or inline blocking message. Native separators divide destinations.
- The first drag change sends immediately; further slider/monitor changes share a 300 ms destination throttle. Release flushes the final pending result, avoiding duplicate final values, and saves once. Failed saves restore persisted values and display an error.
- Debug only: Advanced Settings → Diagnostics opens one reusable live-state window with mode, monitor, last brightness, Pause and per-menu-destination Sync, offset and blocking reason. It stores no history and cannot confirm physical lamp brightness. Release excludes the diagnostic view, scene, access button and simulation fixture.

## Verification and boundaries

The user confirmed the latest menu changes worked with real home lights before requesting this closure. The user also confirmed Settings opens with its window closed, returns an existing window to the front, and the bubble appears during both track and thumb pressure and disappears on release. These are user-observed validations, not transport-based inferences. Controller tests cover timing, cancellation, membership and failed writes; repeat them when behavior changes. Check Settings from a launch with no Settings window, reopen/foreground behavior, track/thumb pressure and bubble cleanup, and live Diagnostics when touching those UI paths. Record the actual outcome in the PR rather than assuming this document proves a future build.

## Commands

From the repository root:

```bash
git status --short --branch
git log -5 --oneline
gh pr status
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Tests/run.sh
bash scripts/preview-ui.sh --groups-demo
```

The simulated preview resets its fixture on each launch, uses monitor brightness 60%, and sends no device commands. The default `bash scripts/preview-ui.sh` uses the real services and isolated preferences; it does not automatically copy the installed configuration. Use one controlling instance when testing real lights. Keep copied preferences and app backups outside Git.

Both CI checks, Release build and Debug build, must pass on the exact PR head before merge. Publishing, merging and installation are separately authorized operations. Only after installation is requested, read the README's Personal updates from GitHub section and run `bash scripts/update-local.sh`; report its backup path and verify installed signature and BetterBrightnessGitCommit. Never install an arbitrary feature build over the stable app.

## Continuing in a new chat

Read AGENTS.md, this document, and the current diff before editing. Use the Git commands above to discover the current branch/commit/PR state; do not assume a historical feature branch is still pending. The next potential topic is a reusable preview skill, which has not been created. The app/settings/CI are the source of truth if they evolve beyond this document.
