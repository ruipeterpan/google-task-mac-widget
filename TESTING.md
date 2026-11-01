# Verification

The development implementation has been checked with:

- Signed Xcode builds of both the companion and widget extension.
- Strict verification of bundle signatures and matching App Group entitlements.
- Native UI checks for the task composer, details editor and settings.
- Version 0.4.4: checked blue underlined HTTP/HTTPS links inside task details; clicking a temporary task link opened the default browser. Completed the test task afterward. Automated checks cover Unicode ranges, multiple URLs, query strings, punctuation and non-link text.
- Version 0.4.2: visually checked the settings gear without the overlapping dropdown indicator and verified its menu opens; inspected the new white checklist icon with blue accents.
- Version 0.4.1: Tab moves from the title directly to Details while the add button is enabled; Shift-Tab returns directly to the title. Checked using an unsaved draft.
- Version 0.4: launch and reopen focus the task title; Return submits from both composer fields; Shift-Return preserves multiline details; successful submission clears the draft and focuses the title again. Verified with temporary tasks, completed after checking.
- Version 0.3: closing the task window with Command-W leaves the process running; a single reopen restores the same task window. Settings opens separately, and the app declares LSUIElement from launch. Desktop-widget launch on the receiving Mac still needs user validation.
- Live task creation, editing of multiline details, completion and automatic synchronization.
- A live 30-second refresh setting check, plus tests for all six available intervals.
- Desktop widget interaction confirmed by a tester: larger Reminders-style layout and direct task completion.
- Rendering of long and short titles at all three widget sizes, including completion-feedback stages.
- Tests for OAuth form encoding, local callback listener startup, API error handling, date semantics, cache compatibility, completion state transitions, notes validation and refresh settings.

A portable development DMG is not equivalent to a notarized distribution release. Installation on another Mac, organization-specific policies and Gatekeeper approval must be validated separately. No claim of testing on a second physical Mac is made.
