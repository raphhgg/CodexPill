# Uninstall And Reset

Use this if you want to remove rusage or clear its saved beta state.

## Uninstall The App

1. Quit rusage from the menu bar.
2. Delete `rusage.app` from `Applications` or wherever you installed it. A
   release installed before the rename is `CodexPill.app`.

This removes the app but keeps rusage's settings and caches for a future reinstall.
It does not sign you out of Codex.

## Clear rusage State

Only do this if you want to delete rusage's folder, caches, and preferences from
this Mac, including any saved Codex accounts an earlier version left there:

```sh
rm -rf "$HOME/Library/Application Support/rusage"
rm -rf "$HOME/Library/Caches/rusage"
defaults delete com.raphhgg.rusage
defaults delete com.raphhgg.rusage.dev
```

Clearing rusage state also clears the record that rusage already copied
CodexPill's data. If CodexPill's folder is still there, the next launch copies
it again.

It is fine if `defaults delete` says the domain does not exist.

If you used `Sign in with Claude…`, choose `Settings › Providers › Claude › Sign Out…` first, so
Anthropic revokes the sign-in. Then remove rusage's own Claude sign-in and its
lock file:

```sh
security delete-generic-password -s "rusage Claude sign-in"
rm -f "$HOME/Library/Application Support/rusage/claude-sign-in.lock"
```

rusage never writes Claude Code's or Cursor's files or Keychain items, so
there is nothing of theirs to remove. Test builds could save Claude Code and
Cursor accounts. If you ran one, remove what it left. Run the first command
until it says the item could not be found:

```sh
security delete-generic-password -s "rusage Claude Code account"
security delete-generic-password -s "rusage Cursor accounts"
rm -f "$HOME/Library/Application Support/rusage/claude-code-accounts.json"
rm -rf "$HOME/Library/Application Support/rusage/claude-sign-in"
rm -rf "$HOME/Library/Application Support/rusage/cursor-sign-in"
```

A test build that crashed while adding a Claude account could also leave a
`Claude Code-credentials-<8 characters>` item. List them and delete each by its
exact name:

```sh
security dump-keychain | grep -o '"Claude Code-credentials-[0-9a-f]\{8\}"' | sort -u
security delete-generic-password -s "Claude Code-credentials-<8 characters>"
```

Only delete names with the 8-character suffix. The plain `Claude Code-credentials`
item is your real Claude Code sign-in. A suffixed item can also belong to a Claude
Code you run yourself with `CLAUDE_CONFIG_DIR` set.

This does not delete `~/.codex/auth.json`. Do not remove or edit that file unless
you intentionally want to sign out of Codex or repair Codex itself.

## Saved Codex Accounts From Earlier Versions

Earlier versions saved Codex sign-ins in
`~/Library/Application Support/rusage/accounts.json` and
`~/Library/Application Support/rusage/snapshots/`. This version shows only the
account `~/.codex/auth.json` signs in to and no longer reads them. They stay
until you delete them. They contain saved sign-ins, so delete them if you no
longer need them:

```sh
rm -f "$HOME/Library/Application Support/rusage/accounts.json"
rm -rf "$HOME/Library/Application Support/rusage/snapshots"
```

## Leftovers From CodexPill

rusage was called CodexPill before. On its first launch rusage copies
CodexPill's folder and preferences, without any saved Claude or Cursor accounts,
then leaves the originals in place as a backup. So after an upgrade there are two copies: rusage's (above)
and CodexPill's. CodexPill's copy also stays when rusage already had data and
copied nothing. CodexPill's folder holds its saved Codex sign-ins. Once rusage
works, remove CodexPill's copy:

```sh
rm -rf "$HOME/Library/Application Support/CodexPill"
rm -rf "$HOME/Library/Caches/CodexPill"
defaults delete com.raphhgg.codexpill
defaults delete com.raphhgg.codexpill.dev
security delete-generic-password -s "CodexPill Claude Code account"
security delete-generic-password -s "CodexPill Cursor accounts"
```

The two `security` commands remove what a CodexPill test build may have saved
for Claude Code and Cursor. Run the first until it says the item could not be found. It
is fine if a command says the item or domain does not exist.

## Remote Hosts From Earlier Versions

Earlier versions could copy selected snapshots to SSH hosts. If you used that, rusage may have left them in:

```text
~/.codexpill/snapshots
```

On each remote host, remove rusage-owned remote state only if you no longer
need it:

```sh
rm -rf "$HOME/.codexpill"
```

Do not delete `$HOME/.codex/auth.json` on a remote host unless you intentionally
want to sign out of Codex on that host.

## Sensitive Reports

Report privately if uninstalling or resetting reveals account mix-ups, misplaced
snapshots, auth data, tokens, private hostnames, or private paths.
