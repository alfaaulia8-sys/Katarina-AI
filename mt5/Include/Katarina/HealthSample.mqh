#ifndef __KATARINA_HEALTH_SAMPLE_MQH__
#define __KATARINA_HEALTH_SAMPLE_MQH__

struct SKatHealthSample
  {
   bool  terminal_connected;
   bool  terminal_trade_allowed;
   bool  mql_trade_allowed;
   bool  account_trade_allowed;
   bool  account_expert_allowed;
   long  terminal_ping_us;
   long  server_time_seconds;
   long  last_tick_time_msc;
   bool  latest_tick_available;
  };

bool KatSampleHealth(const string symbol,SKatHealthSample &sample)
  {
   sample.terminal_connected=(bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   sample.terminal_trade_allowed=(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   sample.mql_trade_allowed=(bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
   sample.account_trade_allowed=(bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
   sample.account_expert_allowed=(bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
   sample.terminal_ping_us=TerminalInfoInteger(TERMINAL_PING_LAST);
   sample.server_time_seconds=(long)TimeTradeServer();
   sample.last_tick_time_msc=0;
   sample.latest_tick_available=false;

   MqlTick tick;
   if(SymbolInfoTick(symbol,tick))
     {
      sample.latest_tick_available=true;
      sample.last_tick_time_msc=tick.time_msc;
     }

   return(sample.terminal_connected);
  }

#endif
