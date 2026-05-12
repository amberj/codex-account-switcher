# Codex Multiusage

Codex Multiusage is a macOS menu bar app for checking Codex account usage across multiple `auth.json` files.

It shows the currently active Codex auth file from `~/.codex/auth.json`, then scans a folder of additional auth profiles and displays each profile's remaining 5-hour and weekly usage. The menu bar title uses the active account's compact `5H/weekly` percentage pair so you can see your current account status at a glance.

## What It Does

- Displays the active Codex account usage from `~/.codex/auth.json`.
- Watches a folder containing additional auth profile directories.
- Reads each child profile's `auth.json` and lists its 5-hour and weekly remaining limits.
- Shows reset times for both buckets when Codex reports them.
- Marks accounts as available, low, or empty with status icons.
- Refreshes automatically on a configurable interval.
- Provides a manual refresh button.
- Can start automatically when you log in.

The app does not edit or switch your active Codex account. It is a monitor for comparing usage across saved Codex auth files.

## Supported Platforms

- macOS 14 Sonoma or newer.
- Swift 5.10 or newer for building from source.
- Codex CLI installed and available on `PATH`, or configured with `CODEX_CLI_PATH`.

This is a native macOS menu bar app. Windows, Linux, and older macOS versions are not supported.

## Requirements

Install and sign in to the Codex CLI first. The app expects your active Codex auth file at:

```text
~/.codex/auth.json
```

Codex Multiusage launches:

```bash
codex app-server --listen stdio://
```

for each auth file it checks. If the app cannot find the `codex` executable, set `CODEX_CLI_PATH` to the full path of the CLI binary before launching the app.

## Auth Folder Layout

The optional auth folder should contain one subfolder per saved Codex profile. Each subfolder must include an `auth.json` file:

```text
~/CodexAccounts/
  work/
    auth.json
  personal/
    auth.json
  backup/
    auth.json
```

The subfolder name is used as the display name in the menu.

## Install

### Install From a DMG

If you have a packaged build, open the DMG in `dist/` and copy `CodexMultiusage.app` to your Applications folder.

Then launch `CodexMultiusage.app`. Because local development builds are not notarized, macOS may require you to approve the app in System Settings > Privacy & Security the first time you open it.

### Build and Run From Source

Clone the repository, then run:

```bash
script/build_and_run.sh
```

This builds the Swift package, creates `dist/CodexMultiusage.app`, and launches the app.

To create a release-style DMG:

```bash
script/package_dmg.sh
```

The generated DMG is written to `dist/`.

## Use

1. Launch `CodexMultiusage.app`.
2. If prompted, open Settings and choose the folder that contains your additional Codex auth profiles.
3. Click the menu bar item to view usage for the active account and each saved profile.
4. Use Refresh Now to update immediately.
5. Open Settings to change the auth folder, choose a refresh interval, or enable Start on login.

Refresh intervals currently available: 5 seconds, 10 seconds, 30 seconds, 1 minute, 2 minutes, and 5 minutes.

## Status Indicators

- Green check: usage is available.
- Yellow warning: at least one reported bucket is below 25%.
- Red x: at least one reported bucket is empty.
- `NA`: Codex did not return a value for that bucket.

## Privacy and Safety

Codex Multiusage copies each auth file into a temporary isolated `CODEX_HOME` directory before querying Codex. Temporary directories are removed after each check.

The app does not upload auth files to a separate service and does not persist copied auth files. It relies on the local Codex CLI to report rate-limit data.

## Development

Common commands:

```bash
swift build
swift test
script/build_and_run.sh
script/build_and_run.sh --verify
script/package_dmg.sh
```

Useful environment variable:

```bash
CODEX_CLI_PATH=/absolute/path/to/codex script/build_and_run.sh
```

The package contains:

- `CodexMultiusage`: the menu bar app.
- `CodexMultiusageCore`: shared scanning, parsing, and Codex app-server integration.
- `CodexMultiusageCoreChecks`: a small executable target for core checks.

## Troubleshooting

If the app says Codex is not installed in the default location, confirm that `~/.codex/auth.json` exists.

If usage rows show Codex launch errors, confirm that `codex` is available from one of the app's search paths, or launch with `CODEX_CLI_PATH` set.

If no child profiles appear, confirm that the selected auth folder contains subfolders and that each subfolder contains an `auth.json` file.
