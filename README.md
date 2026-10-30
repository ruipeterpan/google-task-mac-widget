# Google Tasks Mac Widget — TaskGlass

A native macOS desktop widget and menu bar companion for Google Tasks. Built with SwiftUI, WidgetKit and App Intents. Requires macOS 14 or later.

## Features

- Small, medium and large desktop widgets with a Reminders-inspired layout, task counts and a last-refreshed indicator.
- Interactive circles complete tasks in Google Tasks. The circle fills, the count decreases, and the checked row briefly remains before disappearing. Failed requests restore its unchecked state.
- Inline task creation: title above optional details. Press Enter from the title or Command-Return to add. Existing tasks can be edited with the pencil button.
- Refresh every 30 seconds, 1 minute, 3 minutes, 5 minutes, 10 minutes or 30 minutes. Settings are saved; the default is one minute.
- Keyboard-first task entry: opening focuses the title; Return submits from title or details, and Shift-Return inserts a details line.
- Always available in the menu bar, without a Dock icon. Widget clicks and the menu reuse one task window.
- Browser-based Google authorization with PKCE and state validation; credentials stay in macOS Keychain.
- Pagination for Google task lists and tasks, with local cached data retained during network errors.

The companion must remain running to fetch Google changes. It requests widget reloads after syncing; macOS controls when those reloads become visible.

## Install a prebuilt app

A prebuilt app does **not** require Xcode. Open its DMG, drag TaskGlass into Applications and launch it. A development build may need organizational approval on a managed Mac; a normal distribution build should be Developer ID signed and notarized. This source repository does not include a notarized installer.

You must configure Google authorization separately on each Mac. Tokens and OAuth client JSON are never bundled with the app.

## Connect Google Tasks

1. Create or select a project in [Google Cloud Console](https://console.cloud.google.com/).
2. Enable **Google Tasks API**.
3. Configure **Google Auth Platform** with an External audience. In Testing status, add your Google account under **Audience → Test users**.
4. Configure the scope `https://www.googleapis.com/auth/tasks`, then create an OAuth client with application type **Desktop app** and download its JSON.
5. In TaskGlass, choose **Connect Google Tasks → Import OAuth JSON**, then **Sign in with Google**.
6. Select the list you want to show.

Google may expire Testing-mode refresh tokens after seven days. Reauthorize if needed. Organization-managed Google accounts may require administrator approval.

## Add a widget

Control-click the desktop → **Edit Widgets** → search for **Google Tasks** or **TaskGlass**. Choose a size. The selected list is shared across the widgets. Clicking outside a circle opens the companion.

## Build from source

Building requires Xcode, unlike running a prebuilt app.

1. Open `TaskGlass.xcodeproj`.
2. Select the same signing team for **TaskGlass** and **TaskGlassWidget** under **Signing & Capabilities**.
3. Keep matching App Group entitlements in both targets. The project uses the macOS team-prefixed form `$(DEVELOPMENT_TEAM).local.taskglass`; the repository deliberately leaves the team unset.
4. Build and run the **TaskGlass** scheme. Install the app in Applications for normal widget discovery.

For a command-line Release build, select Xcode as your developer directory and set `TASKGLASS_TEAM_ID` to your own team ID, then run:

```sh
./scripts/build.sh
```

`TASKGLASS_SIGN_IDENTITY` defaults to `Apple Development`. For distribution, use an appropriate Developer ID identity and Apple's notarization workflow. The script creates Xcode App Intents metadata; compiling Swift files alone is insufficient for widget actions.

Package an already-built app:

```sh
./scripts/package-dmg.sh /path/to/TaskGlass.app /path/to/TaskGlass.dmg
```

## Tests

```sh
./test.sh
```

Tests cover OAuth encoding and listener startup, date preservation across time zones, cache compatibility, completion feedback and rollback state, task-details payloads, and refresh settings. The listener test uses a local loopback connection. Tests use synthetic data and do not connect to Google or read stored credentials.

## Privacy

There is no hosted backend, analytics or telemetry. Google credentials are stored in the companion's Keychain service. The widget receives task display data through a local App Group; it does not receive tokens. See [PRIVACY.md](PRIVACY.md).

## Limitations

Google's public Tasks API supports a task's scheduled date but [cannot read or write its scheduled time](https://developers.google.com/workspace/tasks/reference/rest/v1/tasks). This app does not invent a local-only time field. Recurrence editing, task reordering and per-widget list configuration are not implemented.
