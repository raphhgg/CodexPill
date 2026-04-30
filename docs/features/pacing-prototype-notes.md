# Pacing Prototype Notes

Issue: RGR-147

Status: prototype-only. Do not treat this document as a production decision until the current-account-card variants have been reviewed.

## Prototype Data

- The prototype keeps the current account card structure: account header, updated/email row, Session row, Weekly row, existing progress bar geometry, usage text on the left, reset text on the right.
- Prototype data is intentionally fixed so each visual option can be compared against the same baseline.
- Session demonstrates an over-pace case; Weekly demonstrates a below-pace case.

## Variants Reviewed

- Current Baseline: unchanged card for side-by-side comparison.
- Text Beside Usage: adds compact pacing text next to the used percentage on the left.
- Text Under Usage: puts pacing detail under the used percentage on the left.
- Text Under Reset: puts pacing detail under the reset timing on the right.
- Marker Only: keeps text unchanged and adds only an expected-pace marker in the bar.
- Two-Tone Overrun: keeps text unchanged and highlights the over-pace bar segment.

## Recommended Direction

No production direction is selected yet. The next review should compare the prototype screenshots against the current card and choose whether pacing should be text-first, bar-first, or deferred.

## Rejected For V1

- Pacing on saved account rows remains out of scope for this prototype.
- Production current-account cards must stay unchanged until a variant is explicitly selected.
