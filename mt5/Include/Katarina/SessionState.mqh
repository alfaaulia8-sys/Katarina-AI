#ifndef __KATARINA_SESSION_STATE_MQH__
#define __KATARINA_SESSION_STATE_MQH__

struct SKatSessionState
  {
   bool scheduled_open;
   bool session_open;
   bool symbol_trade_allowed;
   long server_time_seconds;
   long last_tick_time_msc;
   int  session_count_today;
  };

int KatSecondsOfDay(const datetime value)
  {
   MqlDateTime parts;
   TimeToStruct(value,parts);
   return(parts.hour*3600+parts.min*60+parts.sec);
  }

bool KatSessionContains(const int now_seconds,
                        const int from_seconds,
                        const int to_seconds_raw)
  {
   int to_seconds=to_seconds_raw;

   // MQL5 may report a session ending at 00:00. For a non-zero start,
   // interpret that endpoint as the end of the current broker day.
   if(to_seconds==0 && from_seconds>0)
      to_seconds=86400;

   if(from_seconds<=to_seconds)
      return(now_seconds>=from_seconds && now_seconds<to_seconds);

   // Defensive overnight handling.
   return(now_seconds>=from_seconds || now_seconds<to_seconds);
  }

bool KatReadSessionState(const string symbol,
                         SKatSessionState &state)
  {
   state.scheduled_open=false;
   state.session_open=false;
   state.symbol_trade_allowed=false;
   state.server_time_seconds=(long)TimeTradeServer();
   state.last_tick_time_msc=0;
   state.session_count_today=0;

   if(state.server_time_seconds<=0)
      return(false);

   long trade_mode_raw=0;
   if(!SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE,trade_mode_raw))
      return(false);

   state.symbol_trade_allowed=((ENUM_SYMBOL_TRADE_MODE)trade_mode_raw!=SYMBOL_TRADE_MODE_DISABLED);

   MqlTick tick;
   if(SymbolInfoTick(symbol,tick))
      state.last_tick_time_msc=tick.time_msc;

   MqlDateTime current;
   TimeToStruct((datetime)state.server_time_seconds,current);

   const ENUM_DAY_OF_WEEK day=(ENUM_DAY_OF_WEEK)current.day_of_week;
   const int now_seconds=current.hour*3600+current.min*60+current.sec;

   for(uint session_index=0;session_index<32;session_index++)
     {
      datetime from=0;
      datetime to=0;
      if(!SymbolInfoSessionTrade(symbol,day,session_index,from,to))
         break;

      state.scheduled_open=true;
      state.session_count_today++;

      const int from_seconds=KatSecondsOfDay(from);
      const int to_seconds=KatSecondsOfDay(to);

      if(KatSessionContains(now_seconds,from_seconds,to_seconds))
         state.session_open=true;
     }

   return(true);
  }

#endif
