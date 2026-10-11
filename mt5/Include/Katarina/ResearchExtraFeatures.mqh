// Offline research telemetry. Input array is series ordered; index 0 is forming.
// Fixed hypotheses, not claims of predictive power. No broker orders.
#ifndef KATARINA_RESEARCH_EXTRA_FEATURES
#define KATARINA_RESEARCH_EXTRA_FEATURES
double KatRelativeTickVolume(const MqlRates &rates[])
  {
   if(ArraySize(rates)<22) return EMPTY_VALUE;
   double total=0.0;
   for(int i=2;i<=21;i++) total+=(double)rates[i].tick_volume;
   if(total<=0.0) return EMPTY_VALUE;
   return (double)rates[1].tick_volume/(total/20.0);
  }
// Last completed broker D1 range / mean of 20 earlier completed D1 ranges.
// This is a previous-day regime feature, NOT today's future total range.
double KatPreviousDayADRRatio(const string symbol,const datetime signal_time)
  {
   int shift=iBarShift(symbol,PERIOD_D1,signal_time,false);
   if(shift<0) return EMPTY_VALUE;
   MqlRates daily[];
   ArraySetAsSeries(daily,true);
   if(CopyRates(symbol,PERIOD_D1,shift+1,21,daily)!=21) return EMPTY_VALUE;
   double total=0.0;
   for(int i=1;i<21;i++)
     {
      if(daily[i].high<daily[i].low || daily[i].low<=0.0) return EMPTY_VALUE;
      total+=daily[i].high-daily[i].low;
     }
   if(total<=0.0 || daily[0].low<=0.0) return EMPTY_VALUE;
   return (daily[0].high-daily[0].low)/(total/20.0);
  }
// Signed engulfing or pin-bar confirmation; only fully closed bars.
double KatCandlePattern(const MqlRates &rates[])
  {
   if(ArraySize(rates)<3) return EMPTY_VALUE;
   MqlRates b=rates[1], p=rates[2];
   double span=b.high-b.low;
   if(span<=0.0) return 0.0;
   double body=MathAbs(b.close-b.open);
   double upper=b.high-MathMax(b.open,b.close);
   double lower=MathMin(b.open,b.close)-b.low;
   bool bull_engulf=b.close>b.open && p.close<p.open &&
                    b.open<=p.close && b.close>=p.open;
   bool bear_engulf=b.close<b.open && p.close>p.open &&
                    b.open>=p.close && b.close<=p.open;
   bool bull_pin=lower>=2.0*MathMax(body,span*0.1) && upper<=span*0.2 && b.close>b.open;
   bool bear_pin=upper>=2.0*MathMax(body,span*0.1) && lower<=span*0.2 && b.close<b.open;
   if(bull_engulf || bull_pin) return 1.0;
   if(bear_engulf || bear_pin) return -1.0;
   return 0.0;
  }
// One explicitly defined chart pattern: close breaking a 20-bar consolidation.
// Prior range <= 4 ATR; do not label this as all chart-pattern recognition.
double KatConsolidationBreakout(const MqlRates &rates[],const double atr)
  {
   if(ArraySize(rates)<22 || atr<=0.0) return EMPTY_VALUE;
   double hi=rates[2].high,lo=rates[2].low;
   for(int i=3;i<=21;i++)
     {
      hi=MathMax(hi,rates[i].high); lo=MathMin(lo,rates[i].low);
     }
   if(hi-lo>4.0*atr) return 0.0;
   if(rates[1].close>hi) return 1.0;
   if(rates[1].close<lo) return -1.0;
   return 0.0;
  }
#endif
