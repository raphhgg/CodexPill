# Validation

Validation is `make test` plus a short manual check of the built app.

## Automated

Run the test suite before opening a pull request:

```bash
make test
```

Tests use temporary directories, injected clients, and fakes for process side
effects. They never read or write the real `~/.codex/auth.json`, real CodexPill
data, or a running Codex app. Tests and fixtures use synthetic accounts and
emails, and never print auth snapshots, tokens, or device codes.

## Manual Checklist

Run these against a dev build started with the
[isolated launch](DEVELOPMENT.md#isolated-launch) unless the change needs real
accounts.

1. The menu bar item appears, and the menu opens with the active account card,
   the saved accounts, Add Account…, Refresh Time, Preferences, Diagnostics…,
   About, and Quit.
2. If the change touches switching, switch to another saved account and check
   that the active account card follows.
3. If the change touches Add Account, Rename, or Remove, run that flow once and
   cancel it once.
4. If the change touches the status item or Preferences, check the changed
   setting in the menu bar label.
5. Screenshots for a pull request show synthetic accounts only.
