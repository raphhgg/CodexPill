# Beta Testing Guide

rusage is in beta. The goal of beta testing is to verify that the signed app
installs cleanly, handles local Codex account snapshots carefully, and makes
account switching easier without surprising the user.

## Who This Beta Is For

This beta is for technical macOS users who already use Codex locally and are
comfortable testing software that reads and writes local Codex auth state.

Best-fit testers:

- use Codex on macOS today;
- use more than one Codex account, or regularly hit Codex limits;
- can describe bugs clearly;
- are comfortable sharing screenshots and redacted logs when needed;
- understand that saved auth snapshots should be treated like credentials.

## Before Testing

Confirm:

- Codex, Claude Code or Cursor is installed and signed in on this Mac.
- You have a current backup or recovery path for anything important.
- You understand that rusage stores saved Codex auth snapshots locally under
  `~/Library/Application Support/rusage`, and only reads Claude Code's and
  Cursor's own sign-ins.
- You will not share raw auth payloads, tokens, refresh tokens, complete logs,
  or screenshots containing private account or host details.

Do not test rusage on a machine where account switching disruption would be
unacceptable.

Read [Uninstall And Reset](UNINSTALL_RESET.md) before testing so you know how to
remove rusage-owned beta state if needed.

## What To Test First

1. Download the signed beta from the GitHub Release.
2. Or install it with `brew install --cask raphhgg/tap/codexpill`.
3. Unzip and launch `rusage.app` if you used the GitHub Release zip. Releases
   from before the rename unzip to `CodexPill.app`.
4. Confirm the app opens without Gatekeeper bypass steps.
5. Confirm the menu bar item appears.
6. Check whether the active account and usage limits look believable.
7. Add a second account.
8. Confirm adding the account does not unexpectedly switch the active account.
9. Switch between saved accounts.
10. Confirm Codex uses the expected account after switching.
11. Remove a test account if you are comfortable doing so.

## What Feedback Is Most Useful

Useful beta feedback is specific and boring:

- what you expected;
- what happened instead;
- what you clicked or selected immediately before it happened;
- whether the issue reproduced;
- macOS version;
- rusage version.

Use the matching GitHub beta issue template for public bugs, confusion, or
feedback.

rusage also includes a diagnostics export. If a bug is hard to describe,
create a diagnostic report from the app and review it before sharing. The report
is designed to be redacted, but you should still avoid posting anything publicly
that contains account identity, hostnames, local paths, tokens, auth payloads, or
raw logs.

## What Not To Share Publicly

Never include these in public issues, screenshots, comments, or release
discussion:

- `~/.codex/auth.json` contents;
- saved snapshot contents;
- tokens, refresh tokens, API keys, or signing credentials;
- private hostnames;
- private local paths;
- complete unreviewed logs.

If a bug requires sensitive details, report it privately instead of opening a
public issue.

## Stop Testing And Report Privately If

- the active Codex account changes unexpectedly;
- an account snapshot appears lost or corrupted;
- a token, auth payload, or private account identifier appears in UI or logs;
- Gatekeeper, signing, or notarization behavior looks suspicious.
