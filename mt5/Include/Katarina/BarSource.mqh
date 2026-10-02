#ifndef __KATARINA_BAR_SOURCE_MQH__
#define __KATARINA_BAR_SOURCE_MQH__

struct SKatBarFact
  {
   string          symbol;
   ENUM_TIMEFRAMES timeframe;
   int             shift;
   datetime        open_time_seconds;
   double          open;
   double          high;
   double          low;
   double          close;
   long            tick_volume;
   int             spread_points;
   long            real_volume;
   bool            forming;
  };

bool KatReadBar(const string symbol,
                const ENUM_TIMEFRAMES timeframe,
                const int shift,
                SKatBarFact &bar)
  {
   if(symbol=="" || shift<0)
      return(false);

   MqlRates rates[];
   ArrayResize(rates,1);
   ArraySetAsSeries(rates,true);

   if(CopyRates(symbol,timeframe,shift,1,rates)!=1)
      return(false);

   bar.symbol=symbol;
   bar.timeframe=timeframe;
   bar.shift=shift;
   bar.open_time_seconds=rates[0].time;
   bar.open=rates[0].open;
   bar.high=rates[0].high;
   bar.low=rates[0].low;
   bar.close=rates[0].close;
   bar.tick_volume=rates[0].tick_volume;
   bar.spread_points=rates[0].spread;
   bar.real_volume=rates[0].real_volume;
   bar.forming=(shift==0);

   return(true);
  }

#endif
