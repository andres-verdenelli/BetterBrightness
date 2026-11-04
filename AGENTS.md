# Agent guide

## Updating the installed app

When the user asks to update the BetterBrightness installed on their Mac to the version on GitHub, run `bash scripts/update-local.sh` from this checkout. The user can simply ask “actualizá BetterBrightness”; use this entry point rather than asking them to locate the script.

Read [Personal updates from GitHub](README.md#personal-updates-from-github) before running it, troubleshooting installation, or restoring a backup. That section documents requirements, backup locations, and recovery. The script installs remote `main`, including changes already merged there; local edits and other branches are excluded.

For validation without replacing or opening the installed app, use `bash scripts/update-local.sh --build-only`. Editing, testing, or building the project alone does not imply a request to update the installed app.

After an update, verify the installed signature with `codesign --verify --deep --strict /Applications/BetterBrightness.app` and read the installed commit with `/usr/libexec/PlistBuddy -c Print:BetterBrightnessGitCommit /Applications/BetterBrightness.app/Contents/Info.plist`. Report the installed commit and the backup path printed by the script.

## Repository tooling

Keep reusable developer and local maintenance commands in `scripts/`, tracked in Git alongside their documentation. These tools support the project and are separate from the code shipped inside the app. Generated builds, caches, personal settings, and app backups stay outside version control.

Publishing changes to GitHub and updating the installed app are separate operations. State which operation was performed.
