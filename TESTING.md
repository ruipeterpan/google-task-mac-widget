# Verification

The development implementation has been checked with:

- Signed Xcode builds of both the companion and widget extension.
- Strict verification of bundle signatures and matching App Group entitlements.
- Native UI checks for the task composer, details editor and settings.
- Live task creation, editing of multiline details, completion and automatic synchronization.
- A live 30-second refresh setting check, plus tests for all six available intervals.
- Desktop widget interaction confirmed by a tester: larger Reminders-style layout and direct task completion.
- Rendering of long and short titles at all three widget sizes, including completion-feedback stages.
- Tests for OAuth form encoding, local callback listener startup, API error handling, date semantics, cache compatibility, completion state transitions, notes validation and refresh settings.

A portable development DMG is not equivalent to a notarized distribution release. Installation on another Mac, organization-specific policies and Gatekeeper approval must be validated separately. No claim of testing on a second physical Mac is made.
