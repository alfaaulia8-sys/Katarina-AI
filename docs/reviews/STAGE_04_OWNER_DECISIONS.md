# STAGE 04 — OWNER DATA DECISIONS

**Status:** ALL OWNER DECISIONS RESOLVED  
**Stage:** 04/40  
**Reviewed:** 2026-10-02

## Decision 1 — Account Custody

### OWNER DECISION: SHARED ACCOUNT FOR OBSERVATIONAL LEARNING ✅

The account may contain Katarina-owned trades, manual user trades, and other explicitly observable activity.

Rules:

- full account activity is observable for risk, reconciliation, and learning;
- trade origin and trade ownership are separate concepts;
- manual trades are learnable but read-only by default;
- Katarina may mutate only explicitly Katarina-owned orders/positions unless a later governed assistance policy says otherwise;
- declared user reasoning and Katarina-inferred reasoning are stored separately.

## Decision 2 — MT5 Account Mode Certification

### OWNER DECISION: HEDGING + NETTING FROM V1 ✅

Katarina V1 must support:

- ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
- ACCOUNT_MARGIN_MODE_RETAIL_NETTING;
- exchange/netting-style account mode where broker capability permits.

Protocol/account snapshots carry the broker account mode explicitly.

Netting-specific safety requirements:

- position state is revisioned;
- entry intents bind to the approved position revision;
- pending LIMIT/STOP orders carry a netting-state guard;
- a material position change after approval invalidates or cancels stale pending intent according to policy;
- execution/reconciliation never assumes a hedging ticket model on a netting account.

## Decision 3 — New Entry Order Types

### OWNER DECISION: MARKET + LIMIT + STOP FROM V1 ✅

Supported entry classes:

- MARKET;
- LIMIT;
- STOP.

BUY/SELL remains a separate side field.

Stop-Limit is reserved for a future capability and is not required for V1.

All order types are capability-gated using current broker symbol properties, including order mode, filling mode, expiration mode, stops/freeze rules, and current account mode.

Pending orders must preserve:

- originating decision/risk lineage;
- setup/pending validity time;
- broker expiration policy;
- current symbol specification revision;
- relevant position/account revision guards.

A stale or invalidated setup must not remain active merely because price has not reached it.

## Decision 4 — Protective Stop Requirement

### OWNER DECISION: BROKER-NATIVE PROTECTIVE SL IS MANDATORY ✅

Every new live Katarina-owned position/order that can create exposure must carry an approved broker-native Stop Loss.

Rules:

- risk approval includes the SL;
- the broker-native SL must be representable under current stop/freeze/order rules;
- LIMIT/STOP pending entries must also contain the approved protective SL;
- if the broker cannot accept the required native SL safely, the entry is rejected;
- Katarina must not create intentional naked live exposure and promise to add the SL later.

Manual user trades without SL may still be observed and learned from, but Katarina does not reinterpret them as compliant Katarina-owned execution.

## Decision 5 — Visibility of External Positions and Orders

### OWNER DECISION: FULL ACCOUNT VISIBILITY ✅

Katarina observes all open positions, pending orders, relevant orders/deals, and account-wide exposure needed for correct risk and learning.

Rules:

- manual/foreign activity contributes to account-wide exposure;
- origin and ownership are classified;
- visibility does not grant mutation authority;
- risk calculations must include external activity where it affects margin/exposure.

## Decision 6 — Deposit / Withdrawal / Credit Ledger

### OWNER DECISION: FIRST-CLASS ACCOUNT LEDGER FROM V1 ✅

Katarina records non-trading account operations separately from trading P/L.

Required classes include:

- BALANCE / DEPOSIT / WITHDRAWAL classification where determinable;
- CREDIT;
- CHARGE;
- CORRECTION;
- BONUS;
- COMMISSION variants;
- INTEREST;
- DIVIDEND / TAX where the broker reports them;
- OTHER_BALANCE_OPERATION.

The raw MT5 DEAL_TYPE remains preserved so normalized classification never destroys the broker fact.

## Additional Owner Requirement — Standard + Cent Accounts

### OWNER DECISION: BOTH MUST BE SUPPORTED ✅

Katarina must operate on both standard and cent account economics.

Rules:

- no hard-coded "cent = divide/multiply by 100" logic;
- native account currency and ACCOUNT_CURRENCY_DIGITS are preserved;
- broker-native symbol contract/tick/volume properties drive sizing;
- standard/cent marketing labels are informational only;
- cross-account learning compares normalized R/percentage metrics or explicitly validated reporting conversion;
- Stage 36/38 validation must include both standard-like and cent-like fixtures/accounts before production compatibility is claimed.

Canonical compatibility contract:

- `docs/architecture/STANDARD_CENT_ACCOUNT_COMPATIBILITY.md`

## Final Owner Configuration

~~~text
SHARED ACCOUNT                         YES
MANUAL TRADE LEARNING                 YES
FULL ACCOUNT VISIBILITY               YES

HEDGING                               YES
NETTING                               YES

MARKET ENTRY                          YES
LIMIT ENTRY                           YES
STOP ENTRY                            YES
STOP-LIMIT V1                         NO / RESERVED

BROKER-NATIVE SL FOR KATARINA ENTRY   REQUIRED

ACCOUNT LEDGER                        REQUIRED

STANDARD ACCOUNT                      REQUIRED
CENT ACCOUNT                          REQUIRED
~~~

## Result

No owner operating decisions remain open for Stage 04.

Engineering may now finalize exact payload layouts, enums, compatibility rules and golden fixtures before Stage 04 freeze.
