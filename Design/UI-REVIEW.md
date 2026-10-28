# BetterBrightness: UI review and design study

## Confirmed direction

- The main task in Settings is editing brightness ranges.
- The user wants the clarity and restraint of Apple's macOS apps, with Notes and Calendar as references.
- Move Discover Lights and discovery results (lights found and IP addresses updated) to the menu bar.
- Preserve existing brightness synchronization, discovery behavior, and saved configuration.

## Observed baseline — 2026-10-28

Reviewed the installed app with eight configured lights, both collapsed and expanded, and the user's screenshot of Settings and the menu bar.

1. Expanding one light pushes other lights and some mapping fields outside the visible list area.
2. Monitor ID and discovery tuning permanently consume vertical space, despite range editing being the primary task.
3. Each row repeats “Send brightness commands”, competing with light names.
4. Multiple lights have identical names; collapsed rows have no secondary identifier.
5. Four mapping values are spread across separate full-width rows; the input/output relationship requires reading explanatory help.

These are observed layout and clarity issues, not evidence of a failure in SwiftUI or networking. The gray controls in the screenshot belong to an inactive window; they are not evidence that the controls are disabled.

## Two proposals to compare

The study uses real SwiftUI controls and fictional, in-memory data. It does not import the production controller or store and cannot discover or control real lights. IP addresses use the documentation-only 192.0.2.0/24 range.

- **Compact list:** one scrolling grouped form, at most one expanded light, short toggle labels, paired minimum/maximum fields, technical settings in a separate sheet.
- **List and detail:** a sidebar keeps the eight lights accessible while the selected light's mapping stays in a dedicated editor. Selected by the user on 2026-10-28 and implemented in Settings.
- Both propose **Discover Lights** and a last-scan summary in a native menu. The separate menu is named **BB Demo** so it is distinguishable from the real app. Scanning there is simulated and labeled as example data.

The original study is archived in the local branch `design/ui-study-2026-10-28`, commit `928dff9e0da404d0663ce965f796aa2a92b62851`. Its `Design/Prototypes/build.sh` builds the isolated app. The bottom segmented control switches designs; state remains in memory across switches. Closing the study discards edits.

The implementation branch keeps the selected interface and this decision record, rather than the discarded variations.

## Implemented behavior

- Settings has native list/detail navigation, one range slider each for Monitor and Light, visible IP/MAC identity, and a toolbar action for manual addition.
- Each range uses two native AppKit slider thumbs on a shared, ungraduated track. The selected interval is highlighted; the minimum and maximum are read-only text at the left and right. Values advance by 1%, stay within 0–100% for the monitor and 1–100% for the light, and cannot cross. Changes update during dragging and persist on release; keyboard/accessibility changes commit immediately.
- Sync brightness and Brightness mapping each have a question-mark button. Hover opens explanatory help and clicking keeps it open until dismissed. Mapping help explains input/output ranges, gives examples from the current settings, and describes behavior below/above the selected monitor range. It replaces the permanent explanatory text.
- Names are edited inline in the sidebar with double-click or right-click → Rename. Enter or focus loss confirms; Escape cancels. New manual lights can be named before entering an IP address. Remove Light exists only in the sidebar context menu, with the existing confirmation and final-light protection.
- Monitor ID and discovery tuning are in an Advanced Settings sheet. Existing validation and per-light enable behavior are retained.
- Discovery is owned outside the Settings view, and launch/manual scans share progress and results. Incoming identity/address changes merge into drafts without replacing in-progress range/name edits.
- The user requested that Discover Lights keep the menu open. SwiftUI's menu-action dismissal override is unavailable on macOS 26.5, so the implementation uses the native window-style MenuBarExtra with standard controls. No custom menu-tracking workaround is used.

## Verification and remaining feedback

- All production Swift files compile and link using the macOS 26.5 SDK.
- `bash Tests/run.sh` passes five discovery scenarios and four range-control scenarios. Range checks cover crossing prevention, one-percent accessibility changes, monitor/light bounds, no ticks, updates during tracking with a single release commit, and hit testing for both widely spaced and adjacent thumbs.
- The real Settings view was opened in a separate preview app with eight example lights, isolated preferences and a simulated discovery runner. The user confirmed that its menu panel stays open and shows the result after clicking Discover Lights.
- UI checks confirmed that a discovery updates the displayed IP addresses, a range edit survives switching to another light and back, and adding/removing an incomplete manual light returns selection to an existing light.
- All production sources, including the range control, compile/link with MainActor default isolation and SDK 26.5. The preview shows two shared tracks, four accessible thumbs, read-only percentages and no detail-pane name/removal controls. A mapping-help popover and sidebar name changes were observed in the updated preview. No real lights were used.
- The user confirmed that both range thumbs work and that the question-mark help opens on both hover and click in the updated preview.
- Sidebar rename contrast: the editor uses an opaque system text-background color with system text and accent colors, preventing the selected row's blue surface from becoming the text-field background. Visual checks covered active editing and selected text in both light and dark appearance; Escape was used to leave the existing name unchanged. Production sources compile/link after the correction.
- The full Xcode Release build passed on 2026-10-28 with the installed macOS 27.0 SDK and `CODE_SIGNING_ALLOWED=NO`. The restricted execution failed to start the SwiftUI macro plugin; rerunning the same build with normal access to Xcode's plugins succeeded. No toolchain or system configuration was changed.
- `Tests/run.sh` uses the active macOS SDK (or `BETTERBRIGHTNESS_TEST_SDK` when supplied), and GitHub Actions runs the nine regression scenarios before its Release build.
- No real-LAN or brightness-delivery validation has been performed for this UI change. Further review should cover dark appearance, narrow windows, invalid ranges, keyboard navigation, and editing while discovery runs.

The final slider request on 2026-10-28 supersedes editable percentages: one two-thumb range per Monitor/Light, read-only endpoint percentages, no tick marks, and explanations behind question-mark buttons. Discovery results describe replies and address updates, not brightness-command delivery.

## Reference

[Apple Human Interface Guidelines: Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars) — system-provided navigation and persistent access to selection. The choice of a two-column editor is a proposal for this app, not a requirement from Apple.

[Apple: MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) — the system window style supports standard controls in a menu bar panel.

[Apple: NSSliderCell](https://developer.apple.com/documentation/appkit/nsslidercell) — documented cell drawing hooks preserve the system thumb rendering while the container draws the single range track.
