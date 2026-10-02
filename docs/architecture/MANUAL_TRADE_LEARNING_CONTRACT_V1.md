# MANUAL TRADE LEARNING CONTRACT V1

**Status:** FROZEN / STAGE 04  
**Version:** 1.0.0

## Purpose

Katarina must be able to learn from manual user trades without confusing those trades with Katarina-owned execution.

A manual trade is treated as an observed human decision with:

1. broker-observed facts;
2. market context captured at/around entry;
3. optional user-declared reasoning;
4. lifecycle and risk-management changes;
5. final outcome;
6. Katarina's own independent post-hoc analysis.

## Trade Origin Classes

Each observed trade is classified into one of:

- KATARINA;
- MANUAL_DESKTOP;
- MANUAL_MOBILE;
- MANUAL_WEB;
- FOREIGN_EA;
- BROKER_OPERATION;
- UNKNOWN.

The raw MT5 order/deal/position reason remains preserved. Katarina derives the normalized origin class without deleting the original broker fact.

## Ownership Is Separate From Origin

A manual trade may be visible to Katarina but is not Katarina-owned.

~~~text
OBSERVABLE = YES
LEARNABLE  = YES
RISK-AWARE = YES
MUTABLE BY KATARINA = NO (default)
~~~

This separation is mandatory.

## Automatic Data Captured From MT5

For a manual trade Katarina can automatically capture:

- account and instrument identity;
- order/deal/position identifiers;
- entry time;
- entry price;
- side;
- volume;
- SL/TP at entry when present;
- later SL/TP modifications;
- partial closes;
- add-on entries;
- exit time and exit price;
- commission/swap;
- realized P/L;
- whether exit was SL, TP, manual, broker, stop-out, or other broker reason where observable;
- concurrent account exposure;
- market ticks/bars and symbol specification around the event.

## Market Context Snapshot

At first detection of the manual entry, Katarina creates an immutable observation snapshot.

It may later derive:

- H4/H1/M15/M5/M1 structure;
- regime;
- volatility;
- spread;
- technical features;
- demand/supply;
- economic-event context;
- model outputs;
- what Katarina itself would have decided.

Derived analysis is clearly labeled as Katarina inference, not the user's declared reason.

## User-Declared Reasoning

MT5 cannot reliably know why a human clicked Buy or Sell.

Therefore actual user reasoning requires an annotation channel.

A ManualTradeAnnotation contains logical equivalents of:

- annotation_id: Id128;
- actor_id: pseudonymous Id128;
- account_id: Id128;
- broker position/order/deal reference;
- annotation_phase;
- annotation_time_ns;
- reason_tags;
- primary_timeframe;
- thesis_text;
- invalidation_text;
- planned_sl / planned_tp when supplied;
- confidence when supplied;
- setup_name when supplied;
- free-form notes;
- consent_scope when multi-user learning is enabled;
- revision;
- source = USER_DECLARED.

## Annotation Phase

To control hindsight bias:

- PRE_ENTRY;
- AT_ENTRY;
- POST_ENTRY_PRE_EXIT;
- POST_EXIT.

The record must also state whether the final outcome was already known when the annotation was created.

Post-exit explanations are valuable for review but must not be treated as if they were pre-entry information.

## Reason Tags

Initial extensible categories may include:

- TREND_FOLLOWING;
- BREAKOUT;
- PULLBACK;
- SUPPORT_RESISTANCE;
- SUPPLY_DEMAND;
- LIQUIDITY_SWEEP;
- REVERSAL;
- NEWS_MACRO;
- INDICATOR_CONFIRMATION;
- PRICE_ACTION;
- SCALP_MOMENTUM;
- MANUAL_DISCRETION;
- OTHER.

Tags do not replace thesis_text.

## Learning Outcome Record

After trade closure Katarina creates a separate immutable learning record containing:

- origin class;
- declared user reason if available;
- Katarina-inferred context;
- entry and exit facts;
- max favorable excursion;
- max adverse excursion;
- realized R when risk baseline is known;
- realized P/L after costs;
- SL/TP/manual-exit classification;
- duration;
- whether the original thesis invalidated before exit;
- whether Katarina agreed/disagreed at entry;
- data-quality/confidence flags.

A profitable trade is not automatically labeled a good decision, and a losing trade is not automatically labeled a bad decision.

Decision quality and outcome are stored separately.

## Multi-User Learning

If Katarina later learns from many users:

- each user/source uses a pseudonymous actor_id;
- explicit training/consent scope must be recorded;
- raw personally identifying data is not required for the learning record;
- one user's private annotations must not leak to another user;
- performance must be evaluable per actor and in aggregate;
- user behavior must not overwrite Katarina production policy directly.

## Safety

Manual trades increase available observational data but also introduce behavioral bias and inconsistent skill levels.

Therefore manual-trade examples enter the research/learning pipeline as a distinct source population.

They do not automatically become production truth.

Production influence still requires validation, OOS testing, robustness checks, shadow evaluation, and governed promotion under the Constitution.
