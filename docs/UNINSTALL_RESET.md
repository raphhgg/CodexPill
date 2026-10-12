# Uninstall And Reset

Use this if you want to remove CodexPill or clear its saved beta state.

## Uninstall The App

1. Quit CodexPill from the menu bar.
2. Delete `CodexPill.app` from `Applications` or wherever you installed it.

This removes the app but keeps saved CodexPill accounts for a future reinstall.

## Clear CodexPill State

Only do this if you want to delete CodexPill's saved accounts, snapshots, and
preferences from this Mac:

```sh
rm -rf "$HOME/Library/Application Support/CodexPill"
defaults delete com.raphhgg.codexpill
```

It is fine if `defaults delete` says the domain does not exist.

CodexPill never writes Claude Code's or Cursor's files or Keychain items, so
there is nothing of theirs to remove. Test builds could save Claude Code and
Cursor accounts. If you ran one, remove what it left. Run the first command
until it says the item could not be found:

```sh
security delete-generic-password -s "CodexPill Claude Code account"
security delete-generic-password -s "CodexPill Cursor accounts"
rm -f "$HOME/Library/Application Support/CodexPill/claude-code-accounts.json"
```

This does not delete `~/.codex/auth.json`. Do not remove or edit that file unless
you intentionally want to sign out of Codex or repair Codex itself.

## Remote Hosts From Earlier Versions

Earlier versions could copy selected snapshots to SSH hosts. If you used that, CodexPill may have left them in:

```text
~/.codexpill/snapshots
```

On each remote host, remove CodexPill-owned remote state only if you no longer
need it:

```sh
rm -rf "$HOME/.codexpill"
```

Do not delete `$HOME/.codex/auth.json` on a remote host unless you intentionally
want to sign out of Codex on that host.

## Sensitive Reports

Report privately if uninstalling or resetting reveals account mix-ups, misplaced
snapshots, auth data, tokens, private hostnames, or private paths.
