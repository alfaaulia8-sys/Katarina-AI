#property strict
#property version   "0.10"
#property description "Katarina AI MT5 sensor / deterministic execution-gateway bridge"

#include <Katarina/BridgeState.mqh>
#include <Katarina/EventBuffer.mqh>
#include <Katarina/TransportPort.mqh>

#define KAT_STAGE06_TIMER_MS                  50
#define KAT_STAGE06_CRITICAL_QUEUE_CAPACITY 2048
#define KAT_STAGE06_DRAIN_BUDGET              64

CKatBridgeState    g_bridge_state;
CKatTradeEventQueue g_trade_events;
CKatLatestTickSlot  g_latest_tick;
CKatNullTransport   g_transport;

ulong g_capture_sequence=0;
bool  g_timer_started=false;

ulong KatNextCaptureSequence(void)
  {
   g_capture_sequence++;
   if(g_capture_sequence==0)
      g_capture_sequence=1;
   return(g_capture_sequence);
  }

int OnInit(void)
  {
   g_bridge_state.Reset();

   if(!g_trade_events.Init(KAT_STAGE06_CRITICAL_QUEUE_CAPACITY))
     {
      g_bridge_state.Block(KAT_BLOCK_LOCAL_INIT_FAILED);
      Print("KatarinaBridgeEA: failed to initialize critical event queue");
      return(INIT_FAILED);
     }

   if(!g_transport.Start())
     {
      g_bridge_state.Block(KAT_BLOCK_LOCAL_INIT_FAILED);
      Print("KatarinaBridgeEA: failed to initialize Stage-06 transport port");
      return(INIT_FAILED);
     }

   if(!EventSetMillisecondTimer(KAT_STAGE06_TIMER_MS))
     {
      g_transport.Stop();
      g_bridge_state.Block(KAT_BLOCK_LOCAL_INIT_FAILED);
      PrintFormat("KatarinaBridgeEA: EventSetMillisecondTimer failed, error=%d",GetLastError());
      return(INIT_FAILED);
     }

   g_timer_started=true;
   g_bridge_state.EnterRecovering();

   // Stage 06 has no external transport or execution command path yet.
   // It must never auto-arm live execution.
   g_bridge_state.SetExecutionArmed(false);

   Print("KatarinaBridgeEA Stage 06 initialized in RECOVERING / READ-ONLY mode");
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
   g_bridge_state.MarkStopped();

   PrintFormat("KatarinaBridgeEA stopped, reason=%d",reason);
  }

void OnTick(void)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   SKatCapturedTick captured;
   KatCaptureTick(_Symbol,tick,KatNextCaptureSequence(),captured);
   g_latest_tick.Capture(captured);
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   SKatCapturedTrade captured;
   KatCaptureTradeTransaction(trans,request,result,KatNextCaptureSequence(),captured);

   if(!g_trade_events.Push(captured))
     {
      // Trade lifecycle events are lossless-required. Once integrity cannot be
      // guaranteed, the bridge fails closed for all future new-risk admission.
      g_bridge_state.Block(KAT_BLOCK_CRITICAL_QUEUE_OVERFLOW);
     }
  }

void OnTimer(void)
  {
   // Stage 07 will replace the null transport with concrete localhost adapters.
   // Keep all work bounded so terminal event processing remains responsive.
   g_transport.Pump(KAT_STAGE06_DRAIN_BUDGET);

   if(g_transport.IsReady())
     {
      int drained=0;
      while(drained<KAT_STAGE06_DRAIN_BUDGET)
        {
         SKatCapturedTrade event;
         if(!g_trade_events.Peek(event))
            break;
         if(!g_transport.PublishTrade(event))
            break;
         if(!g_trade_events.Pop(event))
            break;
         drained++;
        }

      SKatCapturedTick tick;
      if(g_latest_tick.Peek(tick))
        {
         if(g_transport.PublishTick(tick))
            g_latest_tick.Clear();
        }
     }

   // Local bridge setup is valid, but Stage 06 deliberately remains read-only.
   if(g_bridge_state.State()==KAT_BRIDGE_RECOVERING &&
      g_bridge_state.CriticalIntegrityOk())
      g_bridge_state.EnterReadyReadonly();
  }
