# KATARINA Scalper Entry V1

KATARINA Scalper Entry V1 is a deterministic, regime-routed entry layer for XAUUSD.

It combines three strategy families inspired by open GitHub implementations that were reviewed for this project, but the code here is an original KATARINA implementation and is deliberately separated from execution authority.

## Routing

| Market regime | Entry family |
|---|---|
| TREND_UP / TREND_DOWN | Trend Pullback |
| RANGE | RSI(2) + Bollinger Mean Reversion |
| HIGH_VOL | Momentum Breakout |
| UNKNOWN / OOD | NO_TRADE |

## 1. Trend Pullback

Core requirements:
- EMA50 slope in regime direction.
- Pullback to EMA10 followed by a closed-candle bounce/rejection.
- RSI14 sweet spot: 45-65 for BUY, 35-55 for SELL.
- ADX confirms a tradable trend.
- ATR is not in a dead-volatility state.
- MTF alignment and HTF direction must not conflict.
- Default expected RR: 2.2.

## 2. Range Mean Reversion

Core requirements:
- RANGE regime.
- RSI(2) < 10 + close at/below lower Bollinger band for BUY.
- RSI(2) > 90 + close at/above upper Bollinger band for SELL.
- ADX must remain low enough for a range.
- MTF trend must not be too strong.
- Target is conceptually the Bollinger midline; expected RR is derived from distance to the midline versus ATR stop distance.

## 3. Momentum Breakout

Core requirements:
- HIGH_VOL regime.
- Closed candle breaks a prior reference high/low.
- Expansion body >= configured ATR fraction.
- ADX, normalized tick velocity and order-flow imbalance confirm direction.
- VWAP context agrees.
- Strong HTF conflict blocks the trade.
- Default expected RR: 1.8.

## Hard gates

Every setup fails closed on stale data, high-impact news blackout, invalid session, invalid market input, or unacceptable spread.

The entry engine never sizes positions, never authorizes live risk, and never sends broker orders. A valid proposal still has to pass DecisionEngine, Risk Governor, position sizing, execution preflight, reconciliation and the Stage 38 live gate.

## Current status

Implementation baseline only. Performance claims from external repositories are not treated as KATARINA performance. KATARINA must establish its own win rate, profit factor, drawdown and robustness with real-tick backtests and demo forward tests.
