# RGR-248 Test Quality Audit

## Scope

Audited source scope:

- `Sources/Core/Models/CodexRateLimits.swift`
- `Sources/Features/Accounts/Application/AccountActionFlow.swift`
- `Sources/Features/Accounts/Application/InactiveAccountAvailabilityRanking.swift`
- `Sources/Features/Hosts/Application/RemoteRateLimitResolution.swift`

Audited matching tests:

- `Tests/Core/Models/CodexRateLimitWindowTests.swift`
- `Tests/Accounts/AccountActionFlowTests.swift`
- `Tests/Accounts/InactiveAccountAvailabilityRankingTests.swift`
- `Tests/Hosts/RemoteRateLimitResolutionTests.swift`

## Verification Artifacts

- Baseline command: `AGENT_NAME=symphony-RGR-248 make test`
- Baseline result: passed, 501 tests in 64 suites
- Baseline runtime reported by xcodebuild: 16.431 seconds in the final mutation wrapper run; 16.397 seconds in the standalone baseline run
- Baseline result bundle: `build/results/symphony-RGR-248/CodexPill.xcresult`
- Mutation command: `AGENT_NAME=symphony-RGR-248 make mutation`
- Mutation artifacts:
  - `build/verification/mutation/summary.md`
  - `build/verification/mutation/muter-report.json`
  - `build/verification/mutation/muter-report.txt`
- Durable audit report: `docs/quality/test-quality-audit-rgr-248.md`
- Mutation runtime reported by Muter JSON: `00:14:40.257`
- Mutation score: 0% in JSON; the human-readable report is derived from the JSON artifact
- Mutants introduced: 44
- Mutants killed: 0 in JSON
- Mutants survived: 44 in JSON
- Equivalent or ignored mutants: none proven; all survivors are treated as audit findings until strengthened tests or code-health review proves equivalence/dead code.

## Mutation Result Summary

Muter ran `xcodebuild test` for each mutant after the wrapper fix, and the current JSON artifact reports that every introduced mutant survived. The all-survive result includes obvious branch inversions such as `AccountActionFlow.swift:57`, so treat the mutation result as a valid produced artifact plus a test/tooling usefulness finding, not as proof that all four test files are worthless.

| Source file | Mutants | Killed | Survived | Score |
| --- | ---: | ---: | ---: | ---: |
| `CodexRateLimits.swift` | 13 | 0 | 13 | 0% |
| `AccountActionFlow.swift` | 1 | 0 | 1 | 0% |
| `InactiveAccountAvailabilityRanking.swift` | 26 | 0 | 26 | 0% |
| `RemoteRateLimitResolution.swift` | 4 | 0 | 4 | 0% |

## Test File Classifications

| Test file | Classification | Behavior-based reason |
| --- | --- | --- |
| `Tests/Core/Models/CodexRateLimitWindowTests.swift` | strengthen | Keep the file: it owns plan normalization, effective plan precedence, window duration classification, legacy positional fallback, and expired-window display behavior. Strengthen it because the assertions are useful behavior inventory, but the mutation run did not kill any of 13 related mutants and therefore does not yet prove boundary strength. |
| `Tests/Accounts/AccountActionFlowTests.swift` | strengthen | Keep the file: it is the narrow owner for Add Account UI step routing without file I/O or process control. Strengthen or tool-check the accepted/declined confirmation proof because Muter's `SwapTernary` mutant at `AccountActionFlow.swift:57` survived even though the source test should logically catch a swapped ternary. |
| `Tests/Accounts/InactiveAccountAvailabilityRankingTests.swift` | strengthen | Keep the file but split the audit mentally: the filename currently covers availability service, notification policy, and inactive-account ranking behavior. The ranking source had zero killed mutants across comparison order, threshold ranks, projected reset behavior, and tie-breakers, so this should be the first strengthening target after the Muter activation caveat is resolved. |
| `Tests/Hosts/RemoteRateLimitResolutionTests.swift` | strengthen | Keep the file: it owns remote-vs-fallback rate-limit selection, scoped saved-account matching, per-window merging, and expired remote reset fallback. Strengthen it because all 4 related mutants survived, especially meaningful-data checks and non-expired reset comparisons, while recognizing the all-survive caveat above. |

No `delete`, `merge`, `move`, or `quarantine` recommendation is made in this issue. The tests are useful as readable behavior inventory, but the mutation evidence says they are not yet strong enough as regression tripwires for this source scope.

## Surviving Mutants Routed To Owning Tests

| Source area | Surviving mutants | Owning behavior test route |
| --- | ---: | --- |
| Plan normalization and window modeling | `CodexRateLimits.swift:30,37,38,49,107,119,124,129` | Strengthen `CodexRateLimitWindowTests` with boundary examples for duration `nil` vs known duration, session `< 10080`, weekly `>= 10080`, unknown plan collapse, plus/pro/prolite precedence, and expired reset equality. |
| Add Account success confirmation | `AccountActionFlow.swift:57` | Strengthen `AccountActionFlowTests` so the accepted and declined confirmation assertions fail if the ternary is swapped. If the current equality should already catch this, investigate Swift Testing execution or enum equality assumptions before adding more examples. |
| Inactive account sorting and availability projection | `InactiveAccountAvailabilityRanking.swift:14,15,18,19,22,23,26,27,30,31,34,45,46,49,50,53,54,57,58,61,96,97,110` | Strengthen `InactiveAccountAvailabilityRankingTests` with focused ranking-policy tests for each ordered comparator: weekly constraint first, session readiness second, effective available time third, weekly usage fourth, session usage fifth, and name tie-break last. Add explicit boundary examples for 84/85/94/95 weekly usage, 9/10/39/40 session usage, and reset time equal-to-now. |
| Remote fallback and meaningful data selection | `RemoteRateLimitResolution.swift:58,68,75,78` | Strengthen `RemoteRateLimitResolutionTests` with focused examples for no matched candidate, matched candidate without meaningful rate data, one meaningful window being enough, both windows empty, expired reset equality, and zero usage without reset not counting as meaningful. |

## Equivalent / Ignored Mutants

None are marked equivalent or ignored from this run. Some survivors may become equivalent after closer inspection, especially comparator mutants that preserve ordering for symmetric or equal fixtures, but that has not been proven here. Also, because the near-all-survive pattern is suspicious, do not create 44 test-strengthening issues mechanically until a tiny seeded mutant proves Muter activation against the Swift Testing process.

## Duplicate Coverage

- `Tests/Accounts/InactiveAccountAvailabilityRankingTests.swift` contains multiple behavioral suites in one file: `AccountAvailabilityTests`, `AccountAvailabilityNotificationPolicyTests`, and ranking-related tests. That is not duplicate proof by itself, but it weakens ownership clarity. The ranking policy should have a tighter owning suite or section before any merge/delete cleanup is considered.
- `RemoteRateLimitResolutionTests` overlaps conceptually with broader remote host status tests, but it remains the stronger proof for per-window rate-limit resolution because it exercises the pure resolver directly.
- `CodexRateLimitWindowTests` remains the strongest proof for plan/window model rules. Do not merge it into UI, host, or account workflow suites.
- `AccountActionFlowTests` remains the strongest proof for UI-step routing from Add Account outcomes. Broader workflow tests may prove end-to-end behavior, but they are not a replacement for this pure routing table.

## Follow-up Candidates

1. Prove Muter activation against Swift Testing with one tiny seeded mutant before creating many strengthening issues mechanically. The all-survive result still includes mutants the current tests appear likely to catch.
2. Strengthen `CodexRateLimitWindowTests` around exact threshold and equality boundaries, then rerun the bounded mutation command.
3. Strengthen `InactiveAccountAvailabilityRankingTests` first among Accounts tests; it has the highest mutant count and directly affects which account is suggested.
4. Investigate why the `AccountActionFlow.swift:57` ternary swap survived despite accepted and declined tests. That may indicate Muter is not passing mutant activation environment through Xcode into the Swift Testing process, or that the mutation is not being compiled into the tested binary as expected.
5. Add targeted `RemoteRateLimitResolutionTests` for meaningful-data false positives before touching production code.
6. Route any later-proven dead or unreachable branches to code-health cleanup, not test deletion.

## Policy

Report-only audit. No tests were deleted, merged, quarantined, weakened, or moved. No CI threshold or mutation gate was added.
