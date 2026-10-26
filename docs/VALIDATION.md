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
emails, and never print sign-ins, tokens, or device codes.

## Manual Checklist

Run these against a dev build started with the
[isolated launch](DEVELOPMENT.md#isolated-launch) unless the change needs real
accounts.

1. The menu bar item appears, and the menu opens with one card per visible tool,
   then Settings…, Diagnostics, About and Quit. With no card, it starts at Settings….
2. If the change touches Codex sign-in, run `Use Another Account…` in
   `Settings › Providers` once to the end and check that the Codex card follows
   the new account, and cancel it once at the confirmation and check that
   `auth.json` is unchanged.
3. If the change touches the status item or Settings, open `Settings…` (⌘,),
   check that the window comes to the front, and check the changed setting in
   the menu and the menu bar label.
4. Screenshots for a pull request show synthetic accounts only.
