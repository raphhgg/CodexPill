# Validation

Validation is `make test` plus a short manual check of the built app.

## Automated

Run the test suite before opening a pull request:

```bash
make test
```

Tests use temporary directories, injected clients, and fakes for process side
effects. They never read or write the real `~/.codex/auth.json`, real rusage
data, or a running Codex app. Tests and fixtures use synthetic accounts and
emails, and never print auth snapshots, tokens, or device codes.

## Manual Checklist

Run these against a dev build started with the
[isolated launch](DEVELOPMENT.md#isolated-launch) unless the change needs real
accounts.

1. The menu bar item appears, and the menu opens with one card per visible tool,
   then Add Account, Appearance, Refresh Every, Hide Emails, Launch at Login,
   Diagnostics, About and Quit. With no card, it starts at Add Account.
2. If the change touches switching, switch from a card's side menu and check
   that the card follows.
3. If the change touches Add Account or Remove, run that flow once and cancel it
   once.
4. If the change touches the status item or Appearance, check the
   changed setting in the menu bar label.
5. Screenshots for a pull request show synthetic accounts only.
