#property strict
#property version "1.000"
#property description "Katarina governed multi-symbol bridge extension laboratory"

#include <Katarina/MultiSymbolCatalog.mqh>
#include <Katarina/MultiSymbolMarketSource.mqh>
#include <Katarina/MultiSymbolExecutionGateway.mqh>

input string InpSymbolsCsv="";
input bool   InpUseMarketWatch=true;
input int    InpMaxSymbols=64;
input int    InpPollPerTimer=8;
input bool   InpExecutionArmed=false;

CKatMultiSymbolCatalog          g_multi_catalog;
CKatMultiSymbolMarketSource     g_multi_source;
CKatMultiSymbolExecutionGateway g_multi_gateway;
ulong                           g_observed_ticks=0;

int OnInit(void)
  {
   g_multi_catalog.Reset();
   if(!g_multi_catalog.Add(_Symbol))
      return(INIT_FAILED);
   if(InpSymbolsCsv!="" && !g_multi_catalog.AddCsv(InpSymbolsCsv,InpMaxSymbols))
      return(INIT_FAILED);
   if(InpUseMarketWatch)
      g_multi_catalog.AddMarketWatch(InpMaxSymbols);
   if(g_multi_catalog.Count()<=0)
      return(INIT_FAILED);
   if(!g_multi_source.Bind(g_multi_catalog) || !g_multi_gateway.Bind(g_multi_catalog))
      return(INIT_FAILED);
   if(!EventSetMillisecondTimer(50))
      return(INIT_FAILED);

   // This extension is never auto-armed. InpExecutionArmed is an explicit
   // deployment input and transport/reconciliation integration must still
   // prove command authority before SubmitOpen is called.
   PrintFormat("Katarina multi-symbol extension initialized symbols=%d execution_armed=%s",
               g_multi_catalog.Count(),(InpExecutionArmed ? "true" : "false"));
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   PrintFormat("Katarina multi-symbol extension stopped ticks=%I64u reason=%d",
               g_observed_ticks,reason);
  }

void OnTick(void)
  {
   // Chart OnTick is not used as proof of coverage for other symbols.
  }

void OnTimer(void)
  {
   const int budget=MathMax(1,MathMin(InpPollPerTimer,32));
   for(int i=0;i<budget;i++)
     {
      SKatMultiSymbolTick item;
      if(!g_multi_source.PollNext(item))
         break;
      g_observed_ticks++;
     }

   // Broker mutation is intentionally not initiated from local market data.
   // Only a validated KAT1 OPEN_INTENT may call g_multi_gateway.SubmitOpen().
  }
