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

   KatAssert(queue.HighWatermark()==1,
             "critical queue high-watermark observable",
             failures);
   KatAssert(queue.RejectedTotal()==1,
             "critical queue rejected counter observable",
             failures);

   SKatCapturedTrade popped;
   KatAssert(queue.Pop(popped) && popped.local_capture_id==1,
             "queue preserves FIFO order",
             failures);

   CKatLatestTickSlot tick_slot;
   MqlTick tick_a;
   tick_a.time=1;
   tick_a.time_msc=1000;
   tick_a.bid=100.0;
   tick_a.ask=100.1;
   tick_a.last=100.05;
   tick_a.volume=1;
   tick_a.volume_real=1.0;
   tick_a.flags=0;

   SKatCapturedTick captured_tick_a;
   KatCaptureTick("XAUUSD",tick_a,10,captured_tick_a);
   tick_slot.Capture(captured_tick_a);

   MqlTick tick_b=tick_a;
   tick_b.time_msc=1001;
   tick_b.bid=100.01;
   tick_b.ask=100.11;

   SKatCapturedTick captured_tick_b;
   KatCaptureTick("XAUUSD",tick_b,11,captured_tick_b);
   tick_slot.Capture(captured_tick_b);

   KatAssert(tick_slot.CaptureTotal()==2,
             "tick capture counter observable",
             failures);
   KatAssert(tick_slot.CoalescedTotal()==1,
             "tick coalescing counter observable",
             failures);

   CKatInstanceGuard guard_a;
   CKatInstanceGuard guard_b;
   const ulong guard_login=999000111;
   const string guard_server="KAT_STAGE06_SELFTEST";

   const bool guard_a_ok=guard_a.Acquire(guard_login,guard_server,5);
   const bool guard_b_blocked=!guard_b.Acquire(guard_login,guard_server,5);

   KatAssert(guard_a_ok,
             "first duplicate guard acquires test lease",
             failures);
   KatAssert(guard_b_blocked,
             "second duplicate guard is blocked",
             failures);

   guard_a.Release();

   const bool guard_b_after_release=guard_b.Acquire(guard_login,guard_server,5);
   KatAssert(guard_b_after_release,
             "duplicate guard can acquire after owner release",
             failures);
   guard_b.Release();

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
   spec.tick_size=0.01;

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

   request.sl=99.005;
   reason=KatValidateOpenPreflight(request,spec,true,99.90,100.00);
   KatAssert(reason==KAT_PREFLIGHT_PRICE_NOT_TICK_ALIGNED,
             "SL must align to broker tick size",
             failures);

   request.sl=99.0;
   request.side=(ENUM_KAT_SIDE)99;
   reason=KatValidateOpenPreflight(request,spec,true,99.90,100.00);
   KatAssert(reason==KAT_PREFLIGHT_INVALID_SIDE,
             "invalid trade side fails closed",
             failures);

   const bool passed=(failures==0);

   const int evidence=KatOpenEvidenceFile("self_test_result.txt");
   if(evidence!=INVALID_HANDLE)
     {
      KatEvidenceWrite(evidence,"schema_version","1.0");
      KatEvidenceWrite(evidence,"stage","06");
      KatEvidenceWrite(evidence,"design_version",KAT_STAGE06_DESIGN_VERSION);
      KatEvidenceWriteLong(evidence,"generated_epoch_seconds",(long)TimeGMT());
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

   if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
      TerminalClose(failures==0 ? 0 : 6);
  }
