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

If you saved Claude Code accounts, also remove CodexPill's Keychain items for
them. Run this until it says the item could not be found:

```sh
security delete-generic-password -s "CodexPill Claude Code account"
```

This leaves Claude Code's own sign-in, the `Claude Code-credentials` item, as it
is. CodexPill never deletes that item.

While you add a Claude account, or while Claude Code renews a saved one, Claude
Code keeps that sign-in in a temporary `Claude Code-credentials-<8 characters>`
item for a folder under `~/Library/Application Support/CodexPill/claude-sign-in`.
CodexPill deletes both when the run ends, and on its next launch after a crash.
If you remove CodexPill right after a crash, list what is left and delete each
item by its exact name:

```sh
security dump-keychain | grep -o '"Claude Code-credentials-[0-9a-f]\{8\}"' | sort -u
security delete-generic-password -s "Claude Code-credentials-<8 characters>"
```

Only delete names with the 8-character suffix. The plain `Claude Code-credentials`
item is your real Claude Code sign-in. A suffixed item can also belong to a Claude
Code you run yourself with `CLAUDE_CONFIG_DIR` set.

If you saved Cursor accounts, remove the one Keychain item that holds them all:

```sh
security delete-generic-password -s "CodexPill Cursor accounts"
```

Cursor stays signed in as it is. CodexPill never deletes Cursor's own data.

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
