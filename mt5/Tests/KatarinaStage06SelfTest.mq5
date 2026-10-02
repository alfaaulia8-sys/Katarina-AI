#property strict
#property script_show_inputs

#include <Katarina/BarSource.mqh>
#include <Katarina/BridgeState.mqh>
#include <Katarina/BridgeIdentity.mqh>
#include <Katarina/BrokerCalc.mqh>
#include <Katarina/BrokerReason.mqh>
#include <Katarina/DealHistory.mqh>
#include <Katarina/EventBuffer.mqh>
#include <Katarina/ExecutionPreflight.mqh>
#include <Katarina/HealthSample.mqh>
#include <Katarina/InstanceGuard.mqh>
#include <Katarina/NativeFacts.mqh>
#include <Katarina/NativeSnapshot.mqh>
#include <Katarina/SessionState.mqh>
#include <Katarina/SymbolRegistry.mqh>
#include <Katarina/TestEvidence.mqh>
#include <Katarina/TransportPort.mqh>

void KatAssert(const bool condition,
               const string name,
               int &failures)
  {
   if(condition)
      Print("PASS: ",name);
   else
     {
      Print("FAIL: ",name);
      failures++;
     }
  }

void OnStart(void)
  {
   int failures=0;

   CKatBridgeState state;
   KatAssert(!state.CanAcceptNewRisk(),
             "bridge starts fail-closed",
             failures);

   state.EnterRecovering();
   state.SetExecutionArmed(true);
   KatAssert(!state.CanAcceptNewRisk(),
             "recovering never admits new risk",
             failures);

   state.Block(KAT_BLOCK_CRITICAL_QUEUE_OVERFLOW);
   KatAssert(!state.CriticalIntegrityOk(),
             "critical overflow breaks integrity",
             failures);
   KatAssert(!state.CanAcceptNewRisk(),
             "critical overflow disarms",
             failures);

   CKatTradeEventQueue queue;
   KatAssert(queue.Init(1),
             "queue initializes",
             failures);

   SKatCapturedTrade first;
   first.local_capture_id=1;
   SKatCapturedTrade second;
   second.local_capture_id=2;

   KatAssert(queue.Push(first),
             "first critical event accepted",
             failures);
   KatAssert(!queue.Push(second),
             "critical queue reports overflow",
             failures);

   SKatCapturedTrade popped;
   KatAssert(queue.Pop(popped) && popped.local_capture_id==1,
             "queue preserves FIFO order",
             failures);

   SKatSymbolFacts spec;
   spec.trade_mode=SYMBOL_TRADE_MODE_FULL;
   spec.order_mode=(SYMBOL_ORDER_MARKET |
                    SYMBOL_ORDER_LIMIT |
                    SYMBOL_ORDER_STOP |
                    SYMBOL_ORDER_SL |
                    SYMBOL_ORDER_TP);
   spec.volume_min=0.01;
   spec.volume_max=100.0;
   spec.volume_step=0.01;
   spec.stops_level_points=10;
   spec.point=0.01;

   SKatOpenPreflight request;
   request.symbol="XAUUSD";
   request.side=KAT_SIDE_BUY;
   request.entry_type=KAT_ENTRY_MARKET;
   request.volume=0.10;
   request.requested_price=0.0;
   request.sl=99.0;
   request.tp=102.0;

   ENUM_KAT_PREFLIGHT_REASON reason=
      KatValidateOpenPreflight(request,spec,true,99.90,100.00);

   KatAssert(reason==KAT_PREFLIGHT_STAGE06_EXECUTION_DISABLED,
             "valid shape remains execution-disabled in Stage 06",
             failures);

   request.sl=0.0;
   reason=KatValidateOpenPreflight(request,spec,true,99.90,100.00);
   KatAssert(reason==KAT_PREFLIGHT_NATIVE_SL_REQUIRED,
             "native SL is mandatory",
             failures);

   const bool passed=(failures==0);

   const int evidence=KatOpenEvidenceFile("self_test_result.txt");
   if(evidence!=INVALID_HANDLE)
     {
      KatEvidenceWrite(evidence,"schema_version","1.0");
      KatEvidenceWrite(evidence,"stage","06");
      KatEvidenceWrite(evidence,"proof_type","MQL_SELF_TEST");
      KatEvidenceWriteLong(evidence,"terminal_build",TerminalInfoInteger(TERMINAL_BUILD));
      KatEvidenceWriteLong(evidence,"failures",failures);
      KatEvidenceWrite(evidence,"result",(passed ? "PASS" : "FAIL"));
      FileClose(evidence);
      Print("Stage 06 self-test evidence: ",KatEvidenceCommonRoot());
     }
   else
     {
      PrintFormat("FAIL: unable to write Stage 06 self-test evidence, error=%d",GetLastError());
      failures++;
     }

   if(failures==0)
      Print("Katarina Stage 06 static MQL self-tests PASSED");
   else
      PrintFormat("Katarina Stage 06 static MQL self-tests FAILED: %d",failures);
  }
