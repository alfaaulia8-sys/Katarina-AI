# RR Profit Management V1

KATARINA-owned positions now use target-RR-driven partial close and profit protection.

## Trigger

For a trade with target RR `1:N`:

`management_trigger_R = N - 1`

Example target `1:3`:
- initial risk = 1R;
- management trigger = +2R;
- final TP remains +3R.

## At the trigger

When the highest observed profit first reaches the trigger:
- target remaining volume = 20% of the originally authorized volume;
- KATARINA issues a KAT1 `REDUCE_INTENT` for the broker-valid amount needed to reach that runner;
- KATARINA also issues `MODIFY_PROTECTION_INTENT`;
- new SL locks 30% of the **highest observed running profit distance**.

Example BUY:
- entry 2000;
- initial risk distance 10;
- +2R = 2020;
- running profit distance = 20;
- 30% of 20 = 6;
- new SL = 2006 (+0.6R).

## Ratchet / high-water behavior

The manager stores a per-position peak-R high-water mark.

If price rises from +2R to +2.5R:
- peak profit distance becomes 25;
- 30% = 7.5;
- BUY SL ratchets from 2006 to 2007.5.

If price then falls to +2.2R:
- peak remains +2.5R;
- the SL does **not** move down;
- KATARINA never loosens an existing SL.

The peak state can be snapshotted/restored through Stage-10 persistence, preventing a process restart from resetting the trailing high-water mark.

## Partial close

The 80% close is based on the **original Risk-Governor-authorized volume**, not the latest remaining volume.

Actual close quantity is quantized to broker volume step and must leave at least broker minimum volume. Example:
- authorized 0.10;
- desired runner 0.02;
- close 0.08.

If authorized volume is 0.01 and broker minimum/step is 0.01, an 80% partial is impossible. KATARINA keeps the valid 0.01 runner and still applies the 30% profit-protection SL rather than sending an invalid reduction.

Repeated reductions are prevented using reconciled broker volume: once the actual current volume has reached the target runner volume, no new REDUCE_INTENT is generated.

## SELL

All calculations are symmetric:
- profit R increases as price falls;
- protected SL ratchets downward;
- it never moves upward again.

## Ownership

Automatic reduction and SL modification applies only to KATARINA-owned positions. Manual/foreign positions remain risk-aware but non-mutable unless a separate explicit authority policy is introduced.
