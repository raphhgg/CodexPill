# Usage History Token Source Spike

Issue: RGR-352

Date: 2026-05-19

## Question

Can CodexPill safely fetch recent historical token usage for the currently
active Codex account, bucketed by day, using existing Codex auth?

## Recommendation

Defer the Usage History feature until Codex exposes an official/local history
surface or a documented backend contract. Do not build production Usage History
on the currently visible backend endpoints.

The local Codex app-server is the right integration boundary for CodexPill, but
the installed app-server surface does not expose account-level historical token
usage. The only backend usage endpoint found that answers with current active
auth returns current quota/rate-limit state, not daily token totals. A second
backend usage path is present in the installed Codex binary but did not accept
the active ChatGPT bearer auth in this probe.

## Probe Scope

The probe intentionally stayed inside Platform/Codex integration assumptions:

- inspected the existing Codex app-server JSON-RPC surface already used by
  CodexPill;
- inspected the installed Codex CLI binary for candidate usage endpoint names;
- made a redacted live probe against candidate backend paths using active Codex
  auth;
- summarized only HTTP status, JSON key names, method names, and field classes.

No raw auth payloads, tokens, cookies, emails, account IDs, hostnames, local
paths, or response samples were recorded in this document.

## Candidate Sources

### Local Codex app-server

Status: not sufficient for account-level historical token usage.

The local app-server advertised account and current rate-limit reads, including
the existing `account/read` and `account/rateLimits/read` methods CodexPill
already consumes. Candidate history method probes such as account usage and
token-usage reads returned JSON-RPC "unknown variant" errors. The advertised
method set included thread/session methods, but no account-level daily usage
history method.

Useful fields available through the existing app-server rate-limit path:

- active account metadata field classes;
- current rate-limit snapshots;
- named limit buckets, including a Codex-specific limit bucket when present;
- primary and secondary rate-limit windows;
- reset timing and window duration fields;
- credit/quota-like current-state fields through the backend payload that the
  app-server maps from.

Fields not available:

- daily token totals;
- historical buckets for roughly the last 30 days;
- per-day model split;
- per-day cost-like values;
- workspace/org-scoped historical totals.

The app-server does emit or reference thread token usage notifications for live
threads, but that is not the same as account-level history. It would at best
support local session/thread aggregation, which is incomplete, local-machine
scoped, vulnerable to missing history, and ambiguous across account switches.

### Backend `/wham/usage`

Status: reachable but not sufficient for historical token usage.

With active Codex auth, this endpoint returned current usage and quota shape.
Adding date or bucket query parameters did not change the response shape in this
probe.

Useful field classes observed:

- user/account metadata classes;
- plan class;
- current rate-limit fields;
- additional named rate-limit fields;
- credit/balance-like fields;
- spend-control fields;
- reset-credit availability fields.

Fields not observed:

- daily buckets;
- token totals;
- model split;
- timestamped usage rows;
- cost-like historical rows.

Scope appears Codex-specific for current limits because the payload includes
Codex limit buckets, but it is not a historical token source. Account/workspace
scope remains ambiguous without documented semantics.

### Backend `/api/codex/usage`

Status: candidate but not usable from CodexPill today.

The path is present in the installed Codex binary near backend-client usage
strings, making it the most plausible historical-usage candidate. In the live
probe, it returned HTTP 403 with active ChatGPT bearer auth across default,
day-count, date-range, and bucket query shapes.

Because the endpoint was not accessible, the probe could not prove:

- whether daily token totals are available;
- whether buckets cover roughly the last 30 days;
- whether rows are Codex-specific, ChatGPT/account-wide, workspace/org-scoped,
  or something else;
- whether model split, timestamps, token classes, or cost-like values exist.

Using this path would require a human product/security checkpoint. It is an
undocumented private backend assumption, may require additional Codex agent
identity auth instead of the normal ChatGPT bearer token, and may change without
notice.

## Active Account And Saved Accounts

The probe only checked the active account. Querying non-active saved accounts is
not supported by the current app-server history surface because no such surface
exists.

If a future official/local usage-history read appears, non-active saved-account
queries should not directly expose snapshot mechanics to features. The likely
options are:

- isolated auth, mirroring the existing saved-account status read pattern;
- temporarily switching auth snapshots only with explicit user intent and strong
  lifecycle control;
- not supporting non-active history if the upstream surface is active-account
  only.

Until an official surface exists, multi-account history import should remain out
of scope.

## Product Implication

No production menu UI, settings UI, graph, persistence, or background collector
should be added from this spike. The honest product answer is:

- use app-server only for current account and rate-limit visibility;
- stop/defer daily token Usage History for now;
- revisit when Codex exposes documented app-server or backend support for
  historical token buckets.

If the team chooses to pursue the private backend candidate anyway, do that as a
separate explicit-risk issue after human review. That follow-up should define
auth requirements, privacy handling, account/workspace scope, stability risk,
and an opt-in storage policy before any user-facing UI work begins.
