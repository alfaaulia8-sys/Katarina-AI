#property strict
#property version   "0.15"
#property description "Katarina AI MT5 sensor / deterministic execution-gateway bridge"

#include <Katarina/BridgeState.mqh>
#include <Katarina/BridgeIdentity.mqh>
#include <Katarina/EventBuffer.mqh>
#include <Katarina/NativeFacts.mqh>
#include <Katarina/NativeSnapshot.mqh>
#include <Katarina/BrokerReason.mqh>
#include <Katarina/HealthSample.mqh>
#include <Katarina/SessionState.mqh>
#include <Katarina/InstanceGuard.mqh>
#include <Katarina/SymbolRegistry.mqh>
#include <Katarina/ExecutionPreflight.mqh>
#include <Katarina/TransportPort.mqh>

input string InpApprovedSymbols="";

#define KAT_STAGE06_TIMER_MS                  50
#define KAT_STAGE06_CRITICAL_QUEUE_CAPACITY 2048
#define KAT_STAGE06_DRAIN_BUDGET              64
#define KAT_STAGE06_SNAPSHOT_MIN_INTERVAL_MS 1000
#define KAT_STAGE06_HEALTH_INTERVAL_MS        250
#define KAT_STAGE06_INSTANCE_LEASE_SECONDS    10

CKatBridgeState      g_bridge_state;
CKatBridgeIdentity   g_identity;
CKatTradeEventQueue  g_trade_events;
CKatLatestTickSlot   g_latest_tick;
CKatNullTransport    g_transport;
CKatInstanceGuard    g_instance_guard;
CKatSymbolRegistry   g_symbol_registry;
CKatNativeSnapshot   g_snapshot;

SKatAccountFacts     g_account_facts;
SKatSymbolFacts      g_symbol_facts;
SKatHealthSample     g_health;
SKatSessionState     g_session;

ulong g_local_capture_id=0;
bool  g_timer_started=false;
bool  g_snapshot_dirty=true;
bool  g_snapshot_available=false;
ulong g_last_snapshot_attempt_ms=0;
ulong g_last_health_sample_ms=0;

ulong KatNextLocalObservationId(void)
  {
   g_local_capture_id++;
   if(g_local_capture_id==0)
      g_local_capture_id=1;
   return(g_local_capture_id);
  }

bool KatValidateApprovedSymbols(void)
  {
   const int total=g_symbol_registry.ApprovedCount();
   if(total<=0)
      return(false);

   for(int i=0;i<total;i++)
     {
      string symbol="";
      if(!g_symbol_registry.ApprovedAt(i,symbol))
         return(false);

      if(!SymbolSelect(symbol,true))
         return(false);

      SKatSymbolFacts facts;
      if(!KatReadSymbolFacts(symbol,facts))
         return(false);

      if(symbol==_Symbol)
         g_symbol_facts=facts;
     }

   return(true);
  }

bool KatObserveSnapshotSymbols(void)
  {
   const int positions=g_snapshot.PositionCount();
   for(int i=0;i<positions;i++)
     {
      SKatPositionFact position;
      if(!g_snapshot.PositionAt(i,position))
         return(false);
      if(!g_symbol_registry.Observe(position.symbol))
         return(false);
     }

   const int orders=g_snapshot.OrderCount();
   for(int i=0;i<orders;i++)
     {
      SKatOrderFact order;
      if(!g_snapshot.OrderAt(i,order))
         return(false);
      if(!g_symbol_registry.Observe(order.symbol))
         return(false);
     }

   return(true);
  }

bool KatValidateObservedSymbolFacts(void)
  {
   const int total=g_symbol_registry.ObservedCount();
   for(int i=0;i<total;i++)
     {
      string symbol="";
      if(!g_symbol_registry.ObservedAt(i,symbol))
         return(false);

      if(!SymbolSelect(symbol,true))
         return(false);

      SKatSymbolFacts facts;
      if(!KatReadSymbolFacts(symbol,facts))
         return(false);
     }

   return(true);
  }

bool KatRefreshSnapshot(void)
  {
   const ulong now_ms=GetTickCount64();
   if(!g_snapshot_dirty &&
      now_ms-g_last_snapshot_attempt_ms<KAT_STAGE06_SNAPSHOT_MIN_INTERVAL_MS)
      return(g_snapshot_available);

   if(now_ms-g_last_snapshot_attempt_ms<KAT_STAGE06_SNAPSHOT_MIN_INTERVAL_MS &&
      g_last_snapshot_attempt_ms!=0)
      return(g_snapshot_available);

   g_last_snapshot_attempt_ms=now_ms;

   if(!g_snapshot.BuildStable(KatNextLocalObservationId(),3))
     {
      g_snapshot_available=false;
      return(false);
     }

   SKatAccountFacts snapshot_account;
   if(!g_snapshot.Account(snapshot_account) ||
      snapshot_account.login!=g_account_facts.login ||
      snapshot_account.server!=g_account_facts.server)
     {
      g_snapshot_available=false;
      return(false);
     }

   if(!KatObserveSnapshotSymbols())
     {
      g_snapshot_available=false;
      return(false);
     }

   if(!KatValidateObservedSymbolFacts())
     {
      g_snapshot_available=false;
      return(false);
     }

   g_snapshot_available=true;
   g_snapshot_dirty=false;
   return(true);
  }

void KatEnrichCapturedTrade(SKatCapturedTrade &event)
  {
   SKatReasonEvidence evidence;
   KatEnrichReasonEvidence(event.order,event.deal,event.position,evidence);

   event.order_reason_valid=evidence.order_reason_valid;
   if(evidence.order_reason_valid)
      event.order_reason=evidence.order_reason;

   event.deal_reason_valid=evidence.deal_reason_valid;
   if(evidence.deal_reason_valid)
      event.deal_reason=evidence.deal_reason;

   event.position_reason_valid=evidence.position_reason_valid;
   if(evidence.position_reason_valid)
      event.position_reason=evidence.position_reason;
  }

bool KatRefreshHealthAndFacts(void)
  {
   const ulong now_ms=GetTickCount64();
   if(g_last_health_sample_ms!=0 &&
      now_ms-g_last_health_sample_ms<KAT_STAGE06_HEALTH_INTERVAL_MS)
      return(true);

   g_last_health_sample_ms=now_ms;

   SKatAccountFacts latest_account;
   if(!KatReadAccountFacts(latest_account))
      return(false);

   if(latest_account.login!=g_account_facts.login ||
      latest_account.server!=g_account_facts.server)
      return(false);

   g_account_facts=latest_account;

   KatSampleHealth(_Symbol,g_health);

   if(!KatReadSessionState(_Symbol,g_session))
     {
      g_session.scheduled_open=false;
      g_session.session_open=false;
      g_session.symbol_trade_allowed=false;
     }

   return(true);
  }

int OnInit(void)
  {
   g_bridge_state.Reset();
   g_symbol_registry.Reset();

   if(!KatReadAccountFacts(g_account_facts))
     {
      g_bridge_state.Block(KAT_BLOCK_ACCOUNT_BINDING);
      Print("KatarinaBridgeEA: unable to read required account facts");
      return(INIT_FAILED);
     }

   if(!g_instance_guard.Acquire(g_account_facts.login,
                                KAT_STAGE06_INSTANCE_LEASE_SECONDS))
     {
      g_bridge_state.Block(KAT_BLOCK_DUPLICATE_INSTANCE);
      Print("KatarinaBridgeEA: another bridge instance owns this terminal/account lease");
      return(INIT_FAILED);
     }

   if(!g_identity.Init(g_account_facts.login,g_account_facts.server))
     {
      g_instance_guard.Release();
      g_bridge_state.Block(KAT_BLOCK_LOCAL_INIT_FAILED);
      Print("KatarinaBridgeEA: unable to initialize stream/boot identity");
      return(INIT_FAILED);
     }

   if(!g_symbol_registry.AddApproved(_Symbol) ||
      !g_symbol_registry.AddApprovedCsv(InpApprovedSymbols))
     {
      g_instance_guard.Release();
      g_bridge_state.Block(KAT_BLOCK_SYMBOL_SPEC);
      Print("KatarinaBridgeEA: invalid approved symbol configuration");
      return(INIT_FAILED);
     }

   if(!KatValidateApprovedSymbols())
     {
      g_instance_guard.Release();
      g_bridge_state.Block(KAT_BLOCK_SYMBOL_SPEC);
      Print("KatarinaBridgeEA: unable to validate approved SymbolSpec set");
      return(INIT_FAILED);
     }

   if(!g_trade_events.Init(KAT_STAGE06_CRITICAL_QUEUE_CAPACITY))
     {
      g_instance_guard.Release();
      g_bridge_state.Block(KAT_BLOCK_LOCAL_INIT_FAILED);
      Print("KatarinaBridgeEA: failed to initialize critical event queue");
      return(INIT_FAILED);
     }

   g_snapshot_dirty=true;
   g_last_snapshot_attempt_ms=0;
   if(!KatRefreshSnapshot())
     {
      g_instance_guard.Release();
      g_bridge_state.Block(KAT_BLOCK_SNAPSHOT_UNAVAILABLE);
      Print("KatarinaBridgeEA: initial complete native snapshot unavailable");
      return(INIT_FAILED);
     }

   g_last_health_sample_ms=0;
   if(!KatRefreshHealthAndFacts())
     {
      g_instance_guard.Release();
      g_bridge_state.Block(KAT_BLOCK_HEALTH_INVALID);
      Print("KatarinaBridgeEA: initial health/account sample unavailable");
      return(INIT_FAILED);
     }

   if(!g_transport.Start())
     {
      g_instance_guard.Release();
      g_bridge_state.Block(KAT_BLOCK_LOCAL_INIT_FAILED);
      Print("KatarinaBridgeEA: failed to initialize Stage-06 transport port");
      return(INIT_FAILED);
     }

   if(!EventSetMillisecondTimer(KAT_STAGE06_TIMER_MS))
     {
      g_transport.Stop();
      g_instance_guard.Release();
      g_bridge_state.Block(KAT_BLOCK_LOCAL_INIT_FAILED);
      PrintFormat("KatarinaBridgeEA: EventSetMillisecondTimer failed, error=%d",GetLastError());
      return(INIT_FAILED);
     }

   g_timer_started=true;
   g_bridge_state.EnterRecovering();

   // Stage 06 has no external transport or broker mutation command path.
   // Never auto-arm live execution.
   g_bridge_state.SetExecutionArmed(false);

   PrintFormat("KatarinaBridgeEA Stage 06 initialized RECOVERING. Login=%I64u, currency=%s, chart_symbol=%s, approved_symbols=%d, positions=%d, orders=%d, stream_id=%I64u, boot_id=%I64u",
               g_account_facts.login,
               g_account_facts.currency,
               _Symbol,
               g_symbol_registry.ApprovedCount(),
               g_snapshot.PositionCount(),
               g_snapshot.OrderCount(),
               g_identity.StreamId(),
               g_identity.BootId());

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   g_bridge_state.BeginStopping();
   g_bridge_state.SetExecutionArmed(false);

   if(g_timer_started)
     {
      EventKillTimer();
      g_timer_started=false;
     }

   g_transport.Stop();
   g_instance_guard.Release();
   g_bridge_state.MarkStopped();

   PrintFormat("KatarinaBridgeEA stopped, reason=%d",reason);
  }

void OnTick(void)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   SKatCapturedTick captured;
   KatCaptureTick(_Symbol,tick,KatNextLocalObservationId(),captured);
   g_latest_tick.Capture(captured);
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   SKatCapturedTrade captured;
   KatCaptureTradeTransaction(trans,request,result,KatNextLocalObservationId(),captured);

   if(!g_trade_events.Push(captured))
     {
      // Trade lifecycle events are lossless-required. Once integrity cannot be
      // guaranteed, the bridge fails closed for future new-risk admission.
      g_bridge_state.Block(KAT_BLOCK_CRITICAL_QUEUE_OVERFLOW);
      return;
     }

   // Account/position/order state may now differ from the last complete snapshot.
   // Rebuild later from OnTimer, never inside the transaction handler.
   g_snapshot_dirty=true;
  }

void OnTimer(void)
  {
   if(!g_instance_guard.Refresh())
     {
      g_bridge_state.Block(KAT_BLOCK_DUPLICATE_INSTANCE);
      return;
     }

   if(!KatRefreshHealthAndFacts())
     {
      g_bridge_state.Block(KAT_BLOCK_ACCOUNT_BINDING);
      return;
     }

   // Stage 07 replaces the null transport with localhost adapters.
   // Critical trade lifecycle events are serviced before heavier snapshot work.
   g_transport.Pump(KAT_STAGE06_DRAIN_BUDGET);

   if(g_transport.IsReady())
     {
      int drained=0;
      while(drained<KAT_STAGE06_DRAIN_BUDGET)
        {
         SKatCapturedTrade event;
         if(!g_trade_events.Peek(event))
            break;

         // Reason lookup may touch current/history state, so it occurs here,
         // not inside OnTradeTransaction.
         KatEnrichCapturedTrade(event);

         if(!g_transport.PublishTrade(event))
            break;

         SKatCapturedTrade removed;
         if(!g_trade_events.Pop(removed))
            break;

         drained++;
        }
     }

   // Native snapshot refresh is deliberately outside OnTradeTransaction and
   // after critical event servicing. Failure leaves snapshot_available=false.
   if(g_snapshot_dirty)
      KatRefreshSnapshot();

   if(g_transport.IsReady())
     {
      SKatCapturedTick tick;
      if(g_latest_tick.Peek(tick))
        {
         if(g_transport.PublishTick(tick))
            g_latest_tick.Clear();
        }
     }

   // Remain RECOVERING in Stage 06. Local facts/snapshot alone do not prove
   // transport, durable journal, event cursor, or reconciliation readiness.
   g_bridge_state.SetExecutionArmed(false);
  }
