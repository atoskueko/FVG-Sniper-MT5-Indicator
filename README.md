# FVG Sniper MT5 Indicator

MQL5 port of **FVG Sniper [JOAT]**: graded fair value gaps, mitigation and inversion tracking, rejection/IFVG signals, and virtual entry/stop/target plans.

<img width="1360" height="637" alt="fvgsniper_04" src="https://github.com/user-attachments/assets/141929c0-f3c7-43bd-901e-4f4aba36094c" />

## Primary project page

**Full documentation, settings, chart examples, and review:**

### [FVG Sniper MT5 Indicator on AlgoToolbox](https://algotoolbox.com/products/fvg-sniper-mt5/)

AlgoToolbox is the primary home for the MT5 project's documentation. This repository is the secondary source-code repository, not the full manual.

**Page status:** The product-page address is reserved; the article is being prepared. Until it is published, that link may return a not-found page.

## Source snapshot

- **Platform:** MetaTrader 5 desktop.
- **Version:** `1.02`, as declared in `FVGSniper.mq5`.
- **MT5 adaptation:** AlgoToolbox (atoskueko).
- **License:** [MPL-2.0](LICENSE).

This is a **source snapshot**, not a validated binary release. No `.ex5` is included. Exact-source compilation, terminal validation, and matched-data parity have not been established for this package. See [KNOWN_ISSUES.md](KNOWN_ISSUES.md) before relying on its outputs.

## Compile and attach

1. Put [FVGSniper.mq5](FVGSniper.mq5) in your terminal's `MQL5/Indicators/` folder.
2. Open it in MetaEditor, press **F7**, and review errors and warnings.
3. After successful compilation, refresh Navigator and attach the indicator to a chart with sufficient history.
4. Begin with the provided defaults, a dark chart, and one copy per chart. Native alerts are off by default.

The indicator does not execute broker orders or size account positions. TP1/TP2 are reference levels; virtual exits are SL, TP3, or timeout. Grade and result labels are not account-performance statistics. The Algo Trading switch is not required for its analysis.

## Origin and license

**Original work:** [FVG Sniper [JOAT]](https://www.tradingview.com/script/EYFR2g2G-FVG-Sniper-JOAT/), © officialjackofalltrades.

The AlgoToolbox page is the primary **MT5 project guide**, not the original work's publication. Original authorship is retained; no endorsement is implied. Read [NOTICE.md](NOTICE.md) for attribution.

Covered source and modifications remain under MPL-2.0. If distributing a compiled port, tell recipients how to obtain the corresponding covered source. Detailed behavior, inputs, and evaluation belong on the AlgoToolbox product page rather than being duplicated here.
