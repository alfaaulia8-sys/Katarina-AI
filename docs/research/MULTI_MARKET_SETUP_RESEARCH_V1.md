# KATARINA Research Basis — Multi-Market Setup Hardening V1

This note records references used to strengthen **gating and validation**, not to claim that KATARINA already has profitable performance.

## 1. Multi-symbol MT5 engineering

MetaQuotes documents that:
- `OnTick` receives NewTick events only for the chart symbol;
- `SymbolInfoTick(symbol,...)` can read the latest quote for an explicitly named symbol;
- `SymbolSelect` adds symbols to Market Watch;
- `SymbolIsSynchronized` can verify terminal/server synchronization;
- `EventSetMillisecondTimer` provides bounded timer events;
- `OrderCheck` should precede broker submission;
- `OrderSend` / `OrderSendAsync` outcomes must still be reconciled through trade events.

Design implication: KATARINA keeps one account owner but uses a bounded timer-driven multi-symbol source instead of pretending that chart `OnTick` covers every market.

## 2. Trend evidence

Moskowitz, Ooi & Pedersen (2012), *Time Series Momentum*, Journal of Financial Economics, documents time-series momentum across equity-index, currency, commodity and bond futures. Hurst, Ooi & Pedersen (2017) extends trend-following evidence across a much longer historical sample.

Design implication: trend-following is treated as an **asset-class-general regime family**, not an XAUUSD-only rule. The papers do not establish KATARINA's intraday EMA/ADX thresholds; those remain empirical parameters requiring broker-specific validation.

## 3. Volatility-conditioned exposure

Moreira & Muir (2017), *Volatility-Managed Portfolios*, reports benefits from reducing exposure in high-volatility states in several factor portfolios. Bongaerts, Kang & van Dijk (2020), *Conditional Volatility Targeting*, argues that conditional adjustments in volatility extremes can reduce drawdowns/tail risk relative to naive continuous targeting.

Design implication: KATARINA's Setup Quality layer may **reduce** requested risk in extreme volatility but never increases risk above the requesting strategy or Risk Governor cap.

## 4. KATARINA implementation rule

Research references are prior evidence only. Promotion requires:
real broker ticks -> out-of-sample -> walk-forward -> Monte Carlo -> shadow/demo evidence.

No literature result is imported as a KATARINA win-rate claim.
