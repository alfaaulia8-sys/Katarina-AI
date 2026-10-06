from __future__ import annotations

from dataclasses import asdict, dataclass
from hashlib import sha256
import json
from math import floor
from typing import Any, Mapping

from katarina.engines.position import RRManagementPlan


@dataclass(frozen=True, slots=True)
class RecoveryCommand:
    command_id: str
    message_type: str
    position_id: str
    reduce_volume: float = 0.0
    new_stop: float|None = None


@dataclass(slots=True)
class _State:
    side: str
    target_remaining_volume: float
    desired_stop: float|None
    reduce_inflight: bool=False
    modify_inflight: bool=False
    last_volume: float|None=None
    last_stop: float|None=None


class ManagementRecoveryCoordinator:
    """Reconciles desired RR-management state against broker-observed state."""

    def __init__(self):
        self._states: dict[str,_State]={}

    @staticmethod
    def _id(kind:str,position_id:str,value:float)->str:
        raw=json.dumps([kind,position_id,round(value,8)],separators=(",",":"))
        return sha256(raw.encode()).hexdigest()[:32]

    @staticmethod
    def _floor(value:float,step:float)->float:
        return round(max(0.0,floor((value+1e-12)/step)*step),8)

    def apply_plan(self,plan:RRManagementPlan,*,side:str,current_stop:float)->None:
        s=self._states.get(plan.position_id)
        if s is None:
            s=_State(side,plan.target_remaining_volume,None)
            self._states[plan.position_id]=s
        s.target_remaining_volume=min(s.target_remaining_volume,plan.target_remaining_volume)
        if plan.new_stop is not None:
            if s.desired_stop is None:
                s.desired_stop=plan.new_stop
            elif side=="BUY":
                s.desired_stop=max(s.desired_stop,plan.new_stop)
            else:
                s.desired_stop=min(s.desired_stop,plan.new_stop)

    def reconcile(self,position_id:str,*,current_volume:float,current_stop:float,volume_step:float)->tuple[RecoveryCommand,...]:
        s=self._states.get(position_id)
        if s is None:return ()
        out=[]
        if s.reduce_inflight and s.last_volume is not None and current_volume < s.last_volume-1e-12:
            s.reduce_inflight=False
        if s.modify_inflight and s.last_stop is not None and abs(current_stop-s.last_stop)>1e-12:
            s.modify_inflight=False

        if current_volume <= s.target_remaining_volume+1e-12:
            s.reduce_inflight=False
        elif not s.reduce_inflight:
            amount=self._floor(current_volume-s.target_remaining_volume,volume_step)
            if amount>0:
                out.append(RecoveryCommand(self._id("REDUCE",position_id,amount),"REDUCE_INTENT",position_id,reduce_volume=amount))
                s.reduce_inflight=True

        if s.desired_stop is not None:
            satisfied=current_stop>=s.desired_stop-1e-12 if s.side=="BUY" else current_stop<=s.desired_stop+1e-12
            if satisfied:
                s.modify_inflight=False
            elif not s.modify_inflight:
                out.append(RecoveryCommand(self._id("SL",position_id,s.desired_stop),"MODIFY_PROTECTION_INTENT",position_id,new_stop=s.desired_stop))
                s.modify_inflight=True
        s.last_volume=float(current_volume)
        s.last_stop=float(current_stop)
        return tuple(out)

    def ack_failure(self,position_id:str,message_type:str)->None:
        s=self._states.get(position_id)
        if s is None:return
        if message_type=="REDUCE_INTENT":s.reduce_inflight=False
        elif message_type=="MODIFY_PROTECTION_INTENT":s.modify_inflight=False

    def timeout(self,position_id:str)->None:
        s=self._states.get(position_id)
        if s:
            s.reduce_inflight=False;s.modify_inflight=False

    def remove(self,position_id:str)->None:
        self._states.pop(position_id,None)

    def snapshot_state(self)->dict[str,Any]:
        return {k:asdict(v) for k,v in self._states.items()}

    def restore_state(self,state:Mapping[str,Any])->None:
        self._states={str(k):_State(**v) for k,v in state.items()}
