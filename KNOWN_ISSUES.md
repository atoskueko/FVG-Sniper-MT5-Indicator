# Source-snapshot notes — 1.02

This release records the uploaded source after its attribution/header update. The underlying indicator logic is unchanged from the earlier source review. These are source-review observations, not claims of completed native terminal tests.

## Implementation items still open

- **Input validation:** parameter ranges and cross-parameter consistency are not checked in `OnInit()`. Negative gap/history limits can cause removal-loop or array-access problems; invalid risk/target settings can produce invalid reference geometry. Keep defaults while evaluating this snapshot.
- **HTF data availability:** an unavailable HTF lookup returns zero bias, which permits both directional checks even when the filter is enabled. A separate unavailable-data state and entry gate are still needed.
- **Candidate handling:** long/short signal flags share gap boundaries, grade, and tag. If opposing directions qualify together, selected-direction metadata can be inconsistent. This edge case is inherited from the Pine implementation.
- **HTF timing:** MT5 reads the previous closed HTF bar. That policy is not equivalent to the original unoffset Pine `lookahead_off` request. The old equivalence comment remains inside the supplied file; the revised header states the intended distinction.
- **Annotation redraws:** historical entry-label vertical offsets use the ATR supplied at redraw, rather than a stored entry-bar offset.
- **Multiple copies:** chart-based object names can collide between copies on one chart. Use separate charts.

## Model limits, not account results

- Gap-Protected stops are reconstructed after the ATR risk clamp; the cap can move a stop inside its triggering gap. This is inherited behavior.
- TP1/TP2 are reference levels, not partial closes or break-even actions. Virtual exits are SL, TP3, or timeout, with SL priority when both boundaries are touched on one bar.
- Buy/sell buffers are raw signal events, not separate virtual-entry events.
- The gap cap removes stored state as well as drawings. Gap totals are detector counts, not trade or P/L statistics.
- Grading uses broker tick volume; VWAP uses broker-day anchoring. Different feeds/history and HTF conventions can change outputs.

Full settings, examples, and discussion will be documented on the primary AlgoToolbox page. Compilation, reload behavior, and matched-data parity still require their own evidence before this snapshot is described as a validated release.
