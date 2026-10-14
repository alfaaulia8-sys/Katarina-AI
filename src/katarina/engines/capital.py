from __future__ import annotations

from dataclasses import dataclass
from math import isfinite
from typing import Any, Mapping


@dataclass(frozen=True, slots=True)
class CapitalSnapshot:
    total_balance: float
    reserve_balance: float
    active_balance: float
    compounding_reference: float
    next_target_balance: float
    reserve_fraction: float
    growth_multiple: float
    milestone_count: int
    last_milestone_balance: float
    reserve_impaired: bool

    def effective_risk_capital(self, *, equity: float | None = None) -> float:
        base=max(0.0,self.active_balance)
        if equity is None:
            return base
        if not isfinite(equity) or equity <= 0:
            return 0.0
        return min(base,float(equity))


@dataclass(frozen=True, slots=True)
class CapitalEvent:
    event_type: str
    total_balance: float
    reserve_balance: float
    active_balance: float
    next_target_balance: float
    milestone_triggered: bool
    reserve_used: float
    active_used: float
    note: str


class CapitalCompoundingEngine:
    """KATARINA active-capital / reserve compounding.

    Rules:
    - Milestones are realized-balance doublings, adjusted for deposits/withdrawals.
    - When broker REALIZED BALANCE reaches the target, the logical reserve is
      25% of the entire realized balance, not 25% of just the profit.
    - Successive targets are cashflow-adjusted balance doubling milestones,
      not two times the post-reserve active trading balance.
    - Reserve is logical protected capital and is excluded from risk sizing.
    - Withdrawals consume reserve first. Only withdrawal excess reduces active.
    - If withdrawal exceeds reserve, compounding reference/target are recalculated
      from the remaining active balance.
    - External deposits are capital injections, not trading profit; they increase
      active capital and reset the next target to 2x active capital.
    - Ordinary realized trading P/L changes active balance as broker balance moves,
      but does not lower the existing target.
    """

    def __init__(self, *, reserve_fraction: float = 0.25, growth_multiple: float = 2.0):
        if not (0.0 < reserve_fraction < 1.0):
            raise ValueError("reserve_fraction")
        if not isfinite(growth_multiple) or growth_multiple <= 1.0:
            raise ValueError("growth_multiple")
        self.reserve_fraction=float(reserve_fraction)
        self.growth_multiple=float(growth_multiple)
        self.total_balance=0.0
        self.reserve_balance=0.0
        self.active_balance=0.0
        self.compounding_reference=0.0
        self.next_target_balance=0.0
        self.milestone_count=0
        self.last_milestone_balance=0.0
        self.reserve_impaired=False
        self.initialized=False

    def initialize(self, balance: float) -> CapitalEvent:
        self._valid_balance(balance)
        self.total_balance=float(balance)
        self.reserve_balance=0.0
        self.active_balance=float(balance)
        self.compounding_reference=float(balance)
        self.next_target_balance=self.compounding_reference*self.growth_multiple
        self.milestone_count=0
        self.last_milestone_balance=0.0
        self.reserve_impaired=False
        self.initialized=True
        return self._event("INITIALIZE",False,0.0,0.0,"initial_capital")

    @staticmethod
    def _valid_balance(balance: float) -> None:
        if not isfinite(balance) or balance < 0:
            raise ValueError("invalid_balance")

    def _event(
        self,
        event_type: str,
        milestone: bool,
        reserve_used: float,
        active_used: float,
        note: str,
    ) -> CapitalEvent:
        return CapitalEvent(
            event_type,self.total_balance,self.reserve_balance,self.active_balance,
            self.next_target_balance,milestone,reserve_used,active_used,note
        )

    def _sync_from_balance(self,balance:float)->None:
        self.total_balance=float(balance)
        if self.reserve_balance>self.total_balance:
            self.reserve_balance=self.total_balance
            self.reserve_impaired=True
        self.active_balance=max(0.0,self.total_balance-self.reserve_balance)

    def observe_balance(self, balance: float) -> CapitalEvent:
        """Observe broker realized BALANCE. Floating equity never triggers milestones."""
        self._valid_balance(balance)
        if not self.initialized:
            return self.initialize(balance)

        self._sync_from_balance(balance)
        if self.active_balance<=0:
            return self._event("BALANCE",False,0.0,0.0,"no_active_capital")

        if self.next_target_balance>0 and self.total_balance+1e-12>=self.next_target_balance:
            # Multiple thresholds may be crossed in one realized broker snapshot.
            # A reserve sweep never redefines the next doubling milestone.
            while self.next_target_balance>0 and self.total_balance+1e-12>=self.next_target_balance:
                threshold=self.next_target_balance
                self.compounding_reference=threshold
                self.last_milestone_balance=threshold
                self.next_target_balance=threshold*self.growth_multiple
                self.milestone_count+=1
            self.reserve_balance=round(self.total_balance*self.reserve_fraction,10)
            self.active_balance=max(0.0,self.total_balance-self.reserve_balance)
            self.reserve_impaired=False
            return self._event("MILESTONE",True,0.0,0.0,"reserve_25pct_from_realized_balance")

        return self._event("BALANCE",False,0.0,0.0,"balance_synced")

    def apply_external_flow(self, amount: float, *, balance_after: float) -> CapitalEvent:
        """Apply external balance flow. Positive=deposit-like, negative=withdrawal-like."""
        self._valid_balance(balance_after)
        if not isfinite(amount) or amount==0:
            raise ValueError("invalid_external_flow")
        if not self.initialized:
            # Initial funding is external capital, not profit.
            return self.initialize(balance_after)

        before_balance=self.total_balance
        before_active=self.active_balance
        before_reserve=self.reserve_balance
        expected_after=before_balance+amount
        trading_delta=float(balance_after)-expected_after

        reserve_used=0.0
        active_used=0.0
        if amount>0:
            # External positive capital belongs to active capital; preserve reserve.
            previous_cashflow_adjusted_target=self.next_target_balance
            self.total_balance=float(balance_after)
            self.reserve_balance=min(before_reserve,self.total_balance)
            self.active_balance=max(0.0,before_active+amount+trading_delta)
            # Reconcile to authoritative balance.
            self.active_balance=max(0.0,self.total_balance-self.reserve_balance)
            self.compounding_reference=self.active_balance
            new_capital_target=(self.compounding_reference*self.growth_multiple
                                if self.active_balance>0 else 0.0)
            # Deposit is not trading profit: its added cash must not lower
            # the previous realized-balance high-water milestone.
            self.next_target_balance=max(
                new_capital_target,previous_cashflow_adjusted_target+amount
            ) if previous_cashflow_adjusted_target>0 else new_capital_target
            self.reserve_impaired=self.reserve_balance>self.total_balance
            return self._event("DEPOSIT",False,0.0,0.0,"external_capital_resets_compounding_reference")

        withdrawn=abs(float(amount))
        reserve_used=min(before_reserve,withdrawn)
        excess=max(0.0,withdrawn-reserve_used)
        active_used=min(before_active,excess)

        new_reserve=max(0.0,before_reserve-reserve_used)
        new_active=max(0.0,before_active-active_used+trading_delta)
        self.total_balance=float(balance_after)

        # Authoritative balance reconciliation.
        if new_reserve>self.total_balance:
            new_reserve=self.total_balance
            self.reserve_impaired=True
        else:
            self.reserve_impaired=False
        new_active=max(0.0,self.total_balance-new_reserve)
        self.reserve_balance=new_reserve
        self.active_balance=new_active

        if excess>0:
            # User rule: WD beyond reserve resets active base and next 100% target.
            self.compounding_reference=self.active_balance
            self.next_target_balance=self.compounding_reference*self.growth_multiple if self.active_balance>0 else 0.0
            note="withdrawal_exceeded_reserve_rebased"
        else:
            # Withdrawal from reserve only: keep the old compounding target.
            note="withdrawal_funded_by_reserve"

        return self._event("WITHDRAWAL",False,reserve_used,active_used,note)

    def snapshot(self) -> CapitalSnapshot:
        return CapitalSnapshot(
            self.total_balance,self.reserve_balance,self.active_balance,
            self.compounding_reference,self.next_target_balance,
            self.reserve_fraction,self.growth_multiple,self.milestone_count,
            self.last_milestone_balance,self.reserve_impaired,
        )

    def snapshot_state(self)->dict[str,Any]:
        return {
            "reserve_fraction":self.reserve_fraction,
            "growth_multiple":self.growth_multiple,
            "total_balance":self.total_balance,
            "reserve_balance":self.reserve_balance,
            "active_balance":self.active_balance,
            "compounding_reference":self.compounding_reference,
            "next_target_balance":self.next_target_balance,
            "milestone_count":self.milestone_count,
            "last_milestone_balance":self.last_milestone_balance,
            "reserve_impaired":self.reserve_impaired,
            "initialized":self.initialized,
        }

    @classmethod
    def preview_legacy_migration(cls,state:Mapping[str,Any])->dict[str,Any]:
        """Offline 30%-to-25% policy preview; never modifies the old snapshot.

        Keep every dollar of old logical reserve locked, even though the new
        policy's fraction is lower. Releasing capital is a distinct Owner action.
        Reject incoherent historical state instead of guessing missing evidence.
        """
        if not isinstance(state,Mapping):
            raise ValueError("invalid_legacy_capital_state")
        try:
            f=float(state["reserve_fraction"])
            growth=float(state["growth_multiple"])
            total=float(state["total_balance"])
            reserve=float(state["reserve_balance"])
            active=float(state["active_balance"])
            target=float(state["next_target_balance"])
            ref=float(state["compounding_reference"])
            last=float(state["last_milestone_balance"])
            count=state["milestone_count"]
            initialized=state["initialized"]
        except (KeyError,TypeError,ValueError,OverflowError) as exc:
            raise ValueError("invalid_legacy_capital_state") from exc
        amounts=(f,growth,total,reserve,active,target,ref,last)
        if (any(not isfinite(x) for x in amounts)
                or abs(f-0.30)>1e-12 or abs(growth-2.0)>1e-12
                or min(total,reserve,active,target,ref,last)<0
                or abs(total-reserve-active)>max(1e-6,total*1e-8)
                or type(count) is not int or count<0
                or type(initialized) is not bool):
            raise ValueError("invalid_legacy_capital_state")
        if not initialized and (total!=0 or count!=0):
            raise ValueError("invalid_legacy_capital_state")
        proposal=dict(state)
        proposal["reserve_fraction"]=0.25
        # Target must not fall below the last reached milestone's doubling
        # and cannot be lowered by a policy migration.
        proposal["next_target_balance"]=max(target,last*growth) if count>0 else target
        proposal["compounding_reference"]=(
            proposal["next_target_balance"]/growth if proposal["next_target_balance"]>0 else ref
        )
        proposal["reserve_balance"]=reserve
        proposal["active_balance"]=active
        return proposal

    def restore_state(self,state:Mapping[str,Any])->None:
        """All-or-nothing validation: malformed snapshots never mutate capital."""
        if not state:
            return
        if not isinstance(state,Mapping):
            raise ValueError("invalid_capital_state")
        try:
            fraction=float(state["reserve_fraction"])
            multiple=float(state["growth_multiple"])
            total=float(state["total_balance"])
            reserve=float(state["reserve_balance"])
            active=float(state["active_balance"])
            reference=float(state["compounding_reference"])
            target=float(state["next_target_balance"])
            count=state["milestone_count"]
            last=float(state["last_milestone_balance"])
            impaired=state["reserve_impaired"]
            initialized=state["initialized"]
        except (KeyError,ValueError,TypeError,OverflowError) as exc:
            raise ValueError("invalid_capital_state") from exc
        values=(fraction,multiple,total,reserve,active,reference,target,last)
        if (any(not isfinite(v) for v in values)
                or not 0<fraction<1 or multiple<=1
                or min(total,reserve,active,reference,target,last)<0
                or type(count) is not int or count<0
                or type(impaired) is not bool or type(initialized) is not bool
                or abs(total-reserve-active)>max(1e-6,total*1e-8)
                or not initialized and (total!=0 or count!=0)
                or not initialized and (reserve!=0 or active!=0)):
            raise ValueError("invalid_capital_state")
        if abs(fraction-self.reserve_fraction)>1e-12:
            raise ValueError("reserve_fraction_mismatch")
        if abs(multiple-self.growth_multiple)>1e-12:
            raise ValueError("growth_multiple_mismatch")
        self.total_balance=total
        self.reserve_balance=reserve
        self.active_balance=active
        self.compounding_reference=reference
        self.next_target_balance=target
        self.milestone_count=count
        self.last_milestone_balance=last
        self.reserve_impaired=impaired
        self.initialized=initialized

class Kat1CapitalCompoundingRuntime:
    """Consumes ACCEPTED account.ledger + account.state for compounding.

    Milestones use balance_units (realized balance), never equity_units.
    Deposit/withdrawal ledger flows are applied only after the next authoritative
    ACCOUNT_STATE arrives.
    """

    EXTERNAL_POSITIVE_KINDS={1,3,6,8,9}
    EXTERNAL_NEGATIVE_KINDS={2,4,10}
    NEUTRAL_OTHER_KINDS={5,11}
    COMMISSION_KIND=7

    def __init__(self,engine:CapitalCompoundingEngine):
        self.engine=engine
        self._money_scale:int|None=None
        self._pending_external_flow=0.0

    def observe(self,result)->bool:
        from katarina.validation.engine import ValidationDisposition
        if result.disposition is not ValidationDisposition.ACCEPT:
            return False
        event=result.event
        payload=event.payload
        if not isinstance(payload,Mapping):
            return False

        if event.topic=="account.ledger":
            if self._money_scale is None:
                return False
            kind=int(payload.get("ledger_kind",0))
            if kind==self.COMMISSION_KIND:
                return True
            amount=float(int(payload.get("amount_units",0)))*(10.0**(-self._money_scale))
            if kind in self.EXTERNAL_POSITIVE_KINDS|self.EXTERNAL_NEGATIVE_KINDS|self.NEUTRAL_OTHER_KINDS:
                self._pending_external_flow+=amount
                return True
            return False

        if event.topic=="account.state":
            if "account_currency_digits" not in payload or "balance_units" not in payload:
                return False
            self._money_scale=int(payload["account_currency_digits"])
            balance=float(int(payload["balance_units"]))*(10.0**(-self._money_scale))
            if not self.engine.initialized:
                self.engine.initialize(balance)
                self._pending_external_flow=0.0
            elif abs(self._pending_external_flow)>1e-12:
                self.engine.apply_external_flow(self._pending_external_flow,balance_after=balance)
                self._pending_external_flow=0.0
            else:
                self.engine.observe_balance(balance)
            return True
        return False

    def snapshot_state(self)->dict[str,Any]:
        return {
            "money_scale":self._money_scale,
            "pending_external_flow":self._pending_external_flow,
        }

    def restore_state(self,state:Mapping[str,Any])->None:
        raw=state.get("money_scale")
        self._money_scale=None if raw is None else int(raw)
        self._pending_external_flow=float(state.get("pending_external_flow",0.0))
