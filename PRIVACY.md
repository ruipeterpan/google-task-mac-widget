# Privacy and packaging

TaskGlass talks directly to Google's OAuth and Google Tasks endpoints. There is no application backend or analytics service.

- The companion stores the imported Desktop OAuth client configuration and access/refresh tokens in macOS Keychain. These values are not stored in the application bundle or source repository.
- The selected list's task titles, details, dates, IDs and completion feedback are cached in the local App Group container for display by the widget.
- Settings such as refresh interval and Dock visibility are stored in local preferences.
- Disconnect removes local credentials and the task cache. Server-side access can also be revoked in [Google Account connections](https://myaccount.google.com/connections).
- Installing on another Mac does not transfer the first Mac's authorization, tasks or preferences. The second Mac signs in independently.

## Public source hygiene

The public project leaves the signing team unset. OAuth configuration files, token files, task caches, user preferences, Xcode user state, certificates/private keys and prebuilt installers are excluded. Test fixtures contain only synthetic data.

A signed macOS binary necessarily contains a public signing certificate chain identifying its publisher. That is distinct from a private signing key, which is never included. Development-signed personal installers are not published by this source repository.
