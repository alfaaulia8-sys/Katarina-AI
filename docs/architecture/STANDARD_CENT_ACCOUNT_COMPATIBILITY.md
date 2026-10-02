# STANDARD / CENT ACCOUNT COMPATIBILITY CONTRACT V1

**Status:** FROZEN / STAGE 04  
**Version:** 1.0.0  
**Stage:** 04/40

## Requirement

Katarina must be designed to operate correctly on both broker **standard** accounts and broker **cent** accounts.

Compatibility must not depend on account names such as "Standard", "Cent", "Standard Cent", "USC", or other broker marketing labels.

## Core Rule

Katarina never assumes:

- one displayed account unit equals one USD;
- a cent account always uses a 100x multiplier;
- a symbol has the same contract size across brokers/account types;
- 0.01 lot represents the same economic exposure across all account types;
- a symbol name alone identifies its contract specification.

Instead, all risk and execution calculations are driven by broker-reported account and symbol specifications.

## Authoritative MT5 Inputs

### Account-unit facts

Read and preserve:

- ACCOUNT_CURRENCY;
- ACCOUNT_CURRENCY_DIGITS;
- ACCOUNT_BALANCE;
- ACCOUNT_EQUITY;
- ACCOUNT_CREDIT;
- ACCOUNT_PROFIT;
- ACCOUNT_MARGIN;
- ACCOUNT_MARGIN_FREE;
- ACCOUNT_MARGIN_MODE;
- ACCOUNT_LEVERAGE.

All broker monetary values are treated in the broker's **native deposit-currency unit**.

### Symbol/economic exposure facts

For every tradable instrument, read and version:

- SYMBOL_TRADE_CONTRACT_SIZE;
- SYMBOL_TRADE_TICK_SIZE;
- SYMBOL_TRADE_TICK_VALUE;
- SYMBOL_TRADE_TICK_VALUE_PROFIT;
- SYMBOL_TRADE_TICK_VALUE_LOSS;
- SYMBOL_POINT;
- SYMBOL_DIGITS;
- SYMBOL_VOLUME_MIN;
- SYMBOL_VOLUME_MAX;
- SYMBOL_VOLUME_STEP;
- SYMBOL_VOLUME_LIMIT;
- margin/calculation mode;
- relevant stops/freeze/filling/order-mode properties.

## Why This Works for Cent Accounts

Risk sizing uses coherent broker-native units.

Example concept:

~~~text
risk_budget_native
        ÷
loss_per_lot_native
        =
raw_lot
~~~

Both values are expressed in the same broker deposit-currency unit.

Therefore Katarina does not need to guess whether the broker displays USD, USC, cents, or another account denomination in order to calculate percentage risk correctly.

## Canonical Money Representation

KAT1 stores broker monetary values as scaled signed integers:

~~~text
native_money = money_units × 10^(-money_scale)
~~~

Where:

- `money_scale` is derived from ACCOUNT_CURRENCY_DIGITS;
- `account_currency` is preserved exactly as reported by MT5;
- the native account unit remains authoritative for risk/accounting.

No automatic conversion from a broker cent denomination to a major currency is allowed unless an explicit, validated conversion profile exists.

## Optional Reporting Conversion

For dashboards and reports only, a broker/account profile may define:

- reporting_currency;
- native_unit_to_reporting_multiplier;
- provenance/source;
- effective version.

Example:

~~~text
native account currency = USC
reporting currency       = USD
conversion multiplier    = broker-profile-defined
~~~

This conversion is **not** allowed to change execution sizing or broker-native accounting unless validated and explicitly approved.

## Standard/Cent Detection

Katarina does not require a binary STANDARD/CENT guess to trade safely.

Instead it maintains:

~~~text
account_unit_profile
symbol_spec_revision
broker/account identity
~~~

A diagnostic classification may be:

- STANDARD_LIKE;
- CENT_LIKE;
- UNKNOWN;

but classification is informational only.

If broker metadata is ambiguous, Katarina remains fully functional in native account units and marks reporting conversion as UNKNOWN.

## Risk Sizing Invariant

Position sizing must use broker-native economics, not hard-coded pip-value tables.

Conceptually:

~~~text
approved_risk_native
÷
broker_native_loss_for_1_lot_to_SL
=
candidate_lot
↓
quantize to SYMBOL_VOLUME_STEP
↓
validate against min/max/limit
↓
OrderCheck
↓
final revalidation
~~~

This is mandatory for both standard and cent accounts.

## Learning Invariant

Manual/Katarina trade outcomes store:

- native P/L;
- account currency/unit;
- account-unit profile version;
- percentage return/risk;
- R-multiple when defined.

Cross-account learning should compare normalized metrics such as percentage, R, or explicitly converted reporting values rather than blindly comparing raw money numbers.

Thus:

~~~text
+100 native units on Account A
≠ automatically equal economic value to
+100 native units on Account B
~~~

## Broker Variance

Some brokers may use:

- different symbol suffixes;
- different contract sizes;
- different tick values;
- different minimum lot/lot step;
- different margin models;
- different account currency codes;
- different cent-account conventions.

Katarina must treat each `account_id + instrument_id + spec_revision` as its own economic contract.

## Fail-Closed Conditions

NO NEW LIVE RISK if:

- account currency or currency digits are unavailable/inconsistent;
- required symbol economic properties are unavailable;
- tick value/tick size/contract rules are invalid for sizing;
- volume constraints cannot be represented;
- symbol specification changed after RiskDecision;
- account-unit profile changed unexpectedly;
- OrderCheck/final broker validation fails.

## Acceptance Criterion

"Supports standard and cent accounts" means:

1. no hard-coded standard/cent monetary multiplier in core risk logic;
2. all sizing derives from current broker account/symbol facts;
3. account monetary unit is explicit and versioned;
4. golden tests cover at least one standard-like and one cent-like fixture;
5. Stage 36/38 validation includes both account classes before production claims are made.

Until those tests are completed, this is an architectural compatibility guarantee, not a claim of broker-by-broker production certification.
