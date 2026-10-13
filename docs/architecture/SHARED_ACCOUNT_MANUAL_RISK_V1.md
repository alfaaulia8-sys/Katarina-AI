# Shared Account Manual Risk V1

KATARINA calculates manual and other non-KATARINA exposure inside the same account-wide Risk Governor budget.

## Authoritative runtime path

Only **Stage-08 ACCEPTED** broker state is allowed into this calculation:

`account.state + symbol.spec + position.state -> Kat1SharedAccountRiskRuntime -> AccountRiskAssessment -> RiskGovernor.evaluate_account()`

Rejected or quarantined state is ignored for authoritative risk updates.

The runtime understands the frozen KAT1 origin enums:
- KATARINA;
- MANUAL_DESKTOP;
- MANUAL_MOBILE;
- MANUAL_WEB;
- FOREIGN_EA;
- BROKER_OPERATION;
- UNKNOWN.

It also understands the frozen BUY/SELL side enum and stable POSITION_IDENTIFIER.

## Native-unit calculation

KAT1 scaled integers are converted exactly using the frozen protocol rules:

`price = price_units * 10^-price_scale`

`volume = volume_units * 10^-volume_scale`

`native_money = money_units * 10^-money_scale`

The account money scale is derived from ACCOUNT_CURRENCY_DIGITS. Tick loss value comes from broker-native SYMBOL_TRADE_TICK_VALUE_LOSS carried in SymbolSpec. No hard-coded USD/USC or standard/cent multiplier is used.

Preferred future precision path remains broker-native `OrderCalcProfit`; the engine already accepts that exact loss-to-SL value when supplied. The SymbolSpec calculation is the deterministic fallback.

## Dynamic behavior

POSITION UPSERT replaces the latest state for a stable position id. POSITION REMOVE deletes it. Therefore manual risk updates automatically when:
- a manual position opens;
- volume is added;
- a partial close occurs;
- SL changes;
- current price changes in a refreshed position state;
- the position closes.

## Risk meaning

Risk is measured as **remaining downside from current account equity to the position SL**, not merely original entry risk.

Example: BUY 2000, current 2010, SL 2005 still has giveback risk from 2010 down to 2005. It is not zero just because the SL is above entry.

## No SL / unquantifiable exposure

An open position without a valid SL, missing symbol economics, invalid account equity, or otherwise unquantifiable downside is marked **unbounded**.

`RiskGovernor.evaluate_account()` then returns `PAUSE / unbounded_open_risk`, so KATARINA cannot add new automated exposure until the account is quantifiable again.

KATARINA still does not acquire mutation authority over a manual/foreign position merely because it observes and counts its risk.

## Unified limits

All environments use the same profile:
- max 5% per new entry;
- max 8% aggregate open risk;
- 10%-23% caution, 23%-35% only independently qualified recovery;
- at 35%, shutdown for Katarina-caused or unknown-cause loss;
- Owner-caused 35% uses independently reconciled Extreme Survival gates.

Example:
- manual position risk = 3%;
- KATARINA requests 5%;
- aggregate = 8%, allowed.

If manual risk = 6%, KATARINA's requested 5% is reduced to 2%.

## Owner authority clarification — 14 October 2026

Manual positions are observed as account-wide risk; they are not modified by Katarina. Owner manual realized and floating losses must be independently reconciled to attribute the actual crossing of the DD 35% threshold. The Owner-caused exception does not increase per-entry/aggregate open risk limits, and no extreme entry is allowed when exposure is unbounded, reconciliation is missing, or the account has insufficient margin/equity headroom.

## Broker P/L reconciliation groundwork — 14 October 2026

`BrokerPnLReconciler` in the existing `manual_risk.py` checks realized+floating per-position P/L against **equity change minus external cash flow**. It rejects missing fee/commission deltas, duplicate position IDs, unknown/foreign origin, and nonfinite values. Owner/Katarina losses remain separate and include still-open floating losses. It is **arithmetic validation**, not independent authentication; broker deal history and floating snapshots are not yet connected to it.

Current KAT1 account state carries aggregate profit, while position state does **not** carry per-position realized+floating P/L. Therefore the reconciler cannot legitimately prove Owner causation using KAT1 alone. In the account-wide `AccountRiskCoordinator`, requests tagged `EXTREME_RECOVERY` remain PAUSE / `broker_origin_pnl_adapter_not_authenticated`. That is intentional until a trustworthy broker P/L provenance path and end-to-end reconciliation have been tested. A directly constructed DrawdownAuthority is not broker evidence.


## Offline MT5 native read-only P/L adapter (14 October 2026)

The existing Katarina adapter package contains `mt5_account_pnl.py`. It reads only
`account_info`, `positions_get`, and `history_deals_get` from an already initialized
MT5 client and never logs in or transmits an order. For a pair of same-account
snapshots it:

- Tracks per-position floating profit and swap, recognized deal realized profit,
  commission, fee and swap, closing trades, and explicit broker balance cash flows.
- Uses broker-supplied reason codes and Katarina magic to separate Owner,
  Katarina, and foreign/unknown positions; origin changes fail closed.
- Reconciles the resulting broker account-equity change using the existing
  `BrokerPnLReconciler`; duplicates, missing broker fields, stale account identity
  and unsupported ledger operations are rejected.
- Outputs `broker_history_complete_verified=False`,
  `server_trading_day_authenticated=False`, and
  `live_execution_authorized=False`. Python MT5 reads do NOT attest broker
  completeness, trading date, network authenticity, or transaction atomicity.

The adapter supports deterministic mocked testing without launching MT5. It is
not wired to `AccountRiskCoordinator`'s Owner Extreme Recovery permission:
**attribution must remain blocked** pending verified complete broker provenance
and safe read-only forward validation. Do not log into, change, or trade an
Owner account solely to test this adapter.

## Position-origin provenance hardening

For each MT5 broker deal, DEAL_ENTRY distinguishes opening deals from exit deals. The reason on a manual closure or broker-triggered SL/TP is NOT evidence that the Owner originally opened the position. The read-only adapter now derives ownership from the opening deal (DEAL_ENTRY_IN), or from a consistently marked open-position snapshot. Closing-only deals for a position absent from both snapshots remain UNKNOWN, and balanced attribution is denied. Netting reversals (DEAL_ENTRY_INOUT) and missing entry values fail closed until volume-weighted origin lineage is implemented. This rule applies even when account P/L arithmetic balances. MT5 reference: https://www.mql5.com/en/docs/constants/tradingconstants/dealproperties
