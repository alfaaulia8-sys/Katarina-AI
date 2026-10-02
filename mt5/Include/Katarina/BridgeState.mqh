#ifndef __KATARINA_BRIDGE_STATE_MQH__
#define __KATARINA_BRIDGE_STATE_MQH__

enum ENUM_KAT_BRIDGE_STATE
  {
   KAT_BRIDGE_BOOTING=0,
   KAT_BRIDGE_RECOVERING=1,
   KAT_BRIDGE_READY_READONLY=2,
   KAT_BRIDGE_READY_ARMABLE=3,
   KAT_BRIDGE_BLOCKED=4,
   KAT_BRIDGE_STOPPING=5,
   KAT_BRIDGE_STOPPED=6
  };

enum ENUM_KAT_BLOCK_REASON
  {
   KAT_BLOCK_NONE=0,
   KAT_BLOCK_CRITICAL_QUEUE_OVERFLOW=1,
   KAT_BLOCK_LOCAL_INIT_FAILED=2,
   KAT_BLOCK_ACCOUNT_BINDING=3,
   KAT_BLOCK_SYMBOL_SPEC=4,
   KAT_BLOCK_SNAPSHOT_UNAVAILABLE=5,
   KAT_BLOCK_TRANSPORT=6,
   KAT_BLOCK_RECONCILIATION=7,
   KAT_BLOCK_EXECUTION_UNKNOWN=8,
   KAT_BLOCK_DUPLICATE_INSTANCE=9,
   KAT_BLOCK_HEALTH_INVALID=10
  };

class CKatBridgeState
  {
private:
   ENUM_KAT_BRIDGE_STATE m_state;
   ENUM_KAT_BLOCK_REASON m_block_reason;
   bool                  m_critical_integrity_ok;
   bool                  m_execution_armed;

public:
                     CKatBridgeState(void)
     {
      Reset();
     }

   void              Reset(void)
     {
      m_state=KAT_BRIDGE_BOOTING;
      m_block_reason=KAT_BLOCK_NONE;
      m_critical_integrity_ok=true;
      m_execution_armed=false;
     }

   void              EnterRecovering(void)
     {
      m_state=KAT_BRIDGE_RECOVERING;
      m_execution_armed=false;
     }

   void              EnterReadyReadonly(void)
     {
      if(m_state!=KAT_BRIDGE_BLOCKED)
         m_state=KAT_BRIDGE_READY_READONLY;
      m_execution_armed=false;
     }

   void              EnterReadyArmable(void)
     {
      if(m_state!=KAT_BRIDGE_BLOCKED)
         m_state=KAT_BRIDGE_READY_ARMABLE;
     }

   void              SetExecutionArmed(const bool armed)
     {
      // Stage 06 callers keep this false. Later stages may arm only after
      // the complete readiness/reconciliation chain is proven.
      m_execution_armed=armed;
     }

   void              Block(const ENUM_KAT_BLOCK_REASON reason)
     {
      m_block_reason=reason;
      m_state=KAT_BRIDGE_BLOCKED;
      m_execution_armed=false;
      if(reason==KAT_BLOCK_CRITICAL_QUEUE_OVERFLOW)
         m_critical_integrity_ok=false;
     }

   void              BeginStopping(void)
     {
      m_execution_armed=false;
      m_state=KAT_BRIDGE_STOPPING;
     }

   void              MarkStopped(void)
     {
      m_execution_armed=false;
      m_state=KAT_BRIDGE_STOPPED;
     }

   bool              CanAcceptNewRisk(void) const
     {
      return(m_state==KAT_BRIDGE_READY_ARMABLE &&
             m_execution_armed &&
             m_critical_integrity_ok);
     }

   bool              CriticalIntegrityOk(void) const
     {
      return(m_critical_integrity_ok);
     }

   ENUM_KAT_BRIDGE_STATE State(void) const
     {
      return(m_state);
     }

   ENUM_KAT_BLOCK_REASON BlockReason(void) const
     {
      return(m_block_reason);
     }
  };

#endif
