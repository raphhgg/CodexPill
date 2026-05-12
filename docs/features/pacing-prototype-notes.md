# Pacing Prototype Notes

Status: selected direction is Marker Only.

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

Use the Marker Only option for the first implementation. It preserves the existing current-account card copy and adds only a neutral expected-pace marker inside the Session and Weekly progress bars.

Do not change the email color, account header layout, reset text, usage text, saved account rows, ranking, switching, notifications, or persistence.

## Rejected For V1

- Pacing on saved account rows remains out of scope for this prototype.
- Text-based pacing labels and colored overrun segments remain out of scope for the first production implementation.
