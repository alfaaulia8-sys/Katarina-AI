#property strict
#property version   "7.138"
#property description "KATARINA research-only real-tick conformance scalper. No production authority."

#include <Trade/Trade.mqh>
#include <Katarina/ResearchExtraFeatures.mqh>

enum EKatarinaResearchMethod
  {
   KRM_PULLBACK=0,
   KRM_LQ_SWEEP=1,
   KRM_FIB_PULLBACK=2,
   KRM_HYBRID=3,
   KRM_SWEEP_REVERSAL=4,
   KRM_SR_REJECTION=5,
   KRM_BREAKOUT_RETEST=6,
   KRM_ZONE_SCALP=7
  };

enum EKatarinaSessionMode
  {
   KSM_ALL=0,
   KSM_LONDON=1,
   KSM_NEWYORK=2,
   KSM_LONDON_NEWYORK=3
  };

enum EKatarinaBuyResearchFilter
  {
   KBRF_NONE=0,
   KBRF_CLOSE_DEMAND=1,
   KBRF_DEMAND_SUPPORT=2,
   KBRF_CLOSE_SUPPORT=3,
   KBRF_CONTEXT_DEMAND_ONLY=4,
   KBRF_SESSION_VWAP_MAX=5,
   KBRF_CONTEXT_DEMAND_STRUCTURE_RANGE=6,
   KBRF_DEMAND_SUPPORT_ROUND=7
  };

input EKatarinaResearchMethod InpBuyMethod=KRM_HYBRID;
input EKatarinaResearchMethod InpSellMethod=KRM_HYBRID;
input bool   InpEnableBuy=true;
input bool   InpEnableSell=true;
input int    InpLookbackBars=20;
input double InpLot=0.01;
input long   InpMagic=77893501;
input int    InpFastEMA=10;
input int    InpSlowEMA=50;
input int    InpRSIPeriod=14;
input int    InpATRPeriod=14;
input int    InpADXPeriod=14;
input double InpMinADX=20.0;
input double InpPullbackToleranceATR=0.25;
input double InpSweepMinATR=0.05;
input double InpSweepMaxATR=0.80;
input double InpFibMin=0.382;
input double InpFibMax=0.618;
input double InpBuyRSIMin=45.0;
input double InpBuyRSIMax=65.0;
input double InpSellRSIMin=35.0;
input double InpSellRSIMax=55.0;
input double InpBuyReversalRSIMax=40.0;
input double InpSellReversalRSIMin=60.0;
input double InpReversalMaxADX=35.0;
input double InpBuySLATR=1.30;
input double InpSellSLATR=1.30;
input double InpBuyRR=2.20;
input double InpSellRR=2.20;
input double InpMaxSpreadATR=0.12;
input bool   InpUseHTFTrend=false;
input ENUM_TIMEFRAMES InpHTF=PERIOD_H1;
input int    InpHTFFastEMA=50;
input int    InpHTFSlowEMA=200;
input EKatarinaSessionMode InpSessionMode=KSM_ALL;
input int    InpLondonStartHour=7;
input int    InpLondonEndHour=12;
input int    InpNewYorkStartHour=13;
input int    InpNewYorkEndHour=18;
input bool   InpEnableFeatureJournal=true;
input bool   InpEnableStructureFeatures=true;
input int    InpStructureSwingLeft=3;
input int    InpStructureSwingRight=2;
input int    InpStructureLookback=120;
input double InpStructureToleranceATR=0.20;
input double InpRoundNumberStep=5.0;
input int    InpVolRegimeATRPeriod=50;
input ENUM_TIMEFRAMES InpContextTF=PERIOD_M15;
input int    InpContextFastEMA=10;
input int    InpContextSlowEMA=50;
input int    InpContextRSIPeriod=14;
input int    InpContextADXPeriod=14;
input int    InpContextATRPeriod=14;
input EKatarinaBuyResearchFilter InpBuyResearchFilter=KBRF_NONE;
input double InpFilterMinCloseFastATR=0.3575;
input double InpFilterMinContextDemandATR=2.1509;
input double InpFilterMinContextSupportATR=0.6312;
input double InpFilterCleanContextDemandATR=3.137023;
input double InpFilterMaxSessionVWAPATR=4.160768;
input double InpFilterMaxRoundATR=0.672309;
input string InpEntryStopTime="";
input string InpRunTag="baseline";
input bool InpEnableOpportunityJournal=false;
input string InpResearchContextGate="";
#include <Katarina/ResearchZoneScalp.mqh>
int g_opportunity_handle=INVALID_HANDLE;
double g_mae_r=0.0,g_mfe_r=0.0,g_actual_entry=0.0,g_initial_price_risk=0.0;
long g_exit_reason=-1;
string g_run_tag="";

CTrade g_trade;
int g_ema_fast=INVALID_HANDLE;
int g_ema_slow=INVALID_HANDLE;
int g_rsi=INVALID_HANDLE;
int g_atr=INVALID_HANDLE;
int g_adx=INVALID_HANDLE;
int g_atr_slow=INVALID_HANDLE;
int g_ctx_fast=INVALID_HANDLE;
int g_ctx_slow=INVALID_HANDLE;
int g_ctx_rsi=INVALID_HANDLE;
int g_ctx_adx=INVALID_HANDLE;
int g_ctx_atr=INVALID_HANDLE;
int g_htf_fast=INVALID_HANDLE;
int g_htf_slow=INVALID_HANDLE;
datetime g_last_bar=0;
string g_open_reason="";
int g_open_side=0;

datetime g_entry_time=0;
int g_entry_hour=-1;
string g_entry_session="";
string g_entry_htf_regime="";
double g_entry_rsi=0.0;
double g_entry_adx=0.0;
double g_entry_atr_pct=0.0;
double g_entry_ema_slope_atr=0.0;
double g_entry_close_fast_atr=0.0;
double g_entry_close_slow_atr=0.0;
double g_entry_htf_gap_pct=0.0;
double g_entry_htf_close_fast_pct=0.0;
double g_entry_ref_span_atr=0.0;
double g_entry_fib_retrace=0.0;
double g_entry_sweep_pen_atr=0.0;
double g_entry_spread_atr=0.0;
string g_entry_structure="UNKNOWN";
int g_entry_bos_side=0;
double g_entry_support_dist_atr=EMPTY_VALUE;
double g_entry_resistance_dist_atr=EMPTY_VALUE;
int g_entry_support_touches=0;
int g_entry_resistance_touches=0;
double g_entry_prev_high_dist_atr=EMPTY_VALUE;
double g_entry_prev_low_dist_atr=EMPTY_VALUE;
int g_entry_prev_high_swept=0;
int g_entry_prev_low_swept=0;
double g_entry_bull_fvg_dist_atr=EMPTY_VALUE;
double g_entry_bear_fvg_dist_atr=EMPTY_VALUE;
double g_entry_demand_dist_atr=EMPTY_VALUE;
double g_entry_supply_dist_atr=EMPTY_VALUE;
double g_entry_session_vwap_dist_atr=EMPTY_VALUE;
double g_entry_round_dist_atr=EMPTY_VALUE;
double g_entry_candle_pressure=0.0;
double g_entry_previous_day_adr_ratio=EMPTY_VALUE;
double g_entry_relative_tick_volume=EMPTY_VALUE;
double g_entry_chart_breakout=EMPTY_VALUE;
double g_entry_candle_pattern=EMPTY_VALUE;
string g_entry_vol_regime="UNKNOWN";
string g_entry_context_regime="UNKNOWN";
double g_entry_context_rsi=EMPTY_VALUE;
double g_entry_context_adx=EMPTY_VALUE;
double g_entry_context_atr_pct=EMPTY_VALUE;
double g_entry_context_ema_gap_atr=EMPTY_VALUE;
double g_entry_context_close_fast_atr=EMPTY_VALUE;
string g_entry_context_structure="UNKNOWN";
int g_entry_context_bos_side=0;
double g_entry_context_support_dist_atr=EMPTY_VALUE;
double g_entry_context_resistance_dist_atr=EMPTY_VALUE;
double g_entry_context_demand_dist_atr=EMPTY_VALUE;
double g_entry_context_supply_dist_atr=EMPTY_VALUE;
double g_entry_context_bull_fvg_dist_atr=EMPTY_VALUE;
double g_entry_context_bear_fvg_dist_atr=EMPTY_VALUE;
double g_entry_risk_cash=0.0;

int g_buy_trades=0,g_buy_wins=0,g_sell_trades=0,g_sell_wins=0;
int g_pullback_trades=0,g_pullback_wins=0;
int g_sweep_trades=0,g_sweep_wins=0;
int g_fibo_trades=0,g_fibo_wins=0;
int g_reversal_trades=0,g_reversal_wins=0;
double g_gross_profit=0.0,g_gross_loss=0.0,g_net_profit=0.0;
int g_entries_rejected_spread=0,g_entries_rejected_filter=0,g_signals_buy=0,g_signals_sell=0;

// Diagnostic-only counters. These never change entry eligibility.
int g_diag_bars_seen=0;
int g_diag_existing_position_skip=0;
int g_diag_copyrates_reject=0;
int g_diag_indicator_reject=0;
int g_diag_adx_reject=0;
int g_diag_reference_reject=0;
int g_diag_entry_stop_reject=0;
int g_diag_session_reject=0;
int g_diag_buy_trend_true=0;
int g_diag_buy_pullback_true=0;
int g_diag_buy_sweep_true=0;
int g_diag_buy_fibo_true=0;
int g_diag_buy_htf_true=0;
int g_diag_buy_method_true=0;
int g_diag_sell_trend_true=0;
int g_diag_sell_pullback_true=0;
int g_diag_sell_sweep_true=0;
int g_diag_sell_fibo_true=0;
int g_diag_sell_htf_true=0;
int g_diag_sell_method_true=0;
int g_diag_ambiguous_reject=0;

bool ReadValue(const int handle,const int buffer,const int shift,double &value)
  {
   double data[1];
   if(CopyBuffer(handle,buffer,shift,1,data)!=1)
      return false;
   value=data[0];
   return MathIsValidNumber(value);
  }

bool HasReason(const string reason,const string token)
  {
   return(StringFind(reason,token)>=0);
  }


bool HourInside(const int hour,const int start_hour,const int end_hour)
  {
   if(start_hour==end_hour)
      return true;
   if(start_hour<end_hour)
      return(hour>=start_hour && hour<end_hour);
   return(hour>=start_hour || hour<end_hour);
  }

bool SessionAllows(const datetime when)
  {
   if(InpSessionMode==KSM_ALL)
      return true;
   MqlDateTime dt;
   TimeToStruct(when,dt);
   const bool london=HourInside(dt.hour,InpLondonStartHour,InpLondonEndHour);
   const bool newyork=HourInside(dt.hour,InpNewYorkStartHour,InpNewYorkEndHour);
   if(InpSessionMode==KSM_LONDON)
      return london;
   if(InpSessionMode==KSM_NEWYORK)
      return newyork;
   if(InpSessionMode==KSM_LONDON_NEWYORK)
      return(london || newyork);
   return true;
  }


string ActualSessionLabel(const datetime when)
  {
   MqlDateTime dt;
   TimeToStruct(when,dt);
   const bool london=HourInside(dt.hour,InpLondonStartHour,InpLondonEndHour);
   const bool newyork=HourInside(dt.hour,InpNewYorkStartHour,InpNewYorkEndHour);
   if(london && newyork) return "OVERLAP";
   if(london) return "LONDON";
   if(newyork) return "NEWYORK";
   return "OTHER";
  }

string CurrentHTFRegime(double &gap_pct,double &close_fast_pct)
  {
   gap_pct=0.0;
   close_fast_pct=0.0;
   if(g_htf_fast==INVALID_HANDLE || g_htf_slow==INVALID_HANDLE)
      return "UNKNOWN";
   double fast1,slow1;
   if(!ReadValue(g_htf_fast,0,1,fast1) || !ReadValue(g_htf_slow,0,1,slow1))
      return "UNKNOWN";
   const double close1=iClose(_Symbol,InpHTF,1);
   if(close1<=0.0)
      return "UNKNOWN";
   gap_pct=100.0*(fast1-slow1)/close1;
   close_fast_pct=100.0*(close1-fast1)/close1;
   if(fast1>slow1 && close1>fast1)
      return "UP";
   if(fast1<slow1 && close1<fast1)
      return "DOWN";
   return "MIXED";
  }

string FeatureValue(const double value,const int digits=6)
  {
   if(value==EMPTY_VALUE || !MathIsValidNumber(value))
      return "";
   return DoubleToString(value,digits);
  }

bool IsConfirmedSwingHigh(const MqlRates &rates[],const int shift)
  {
   const int total=ArraySize(rates);
   if(shift<1+InpStructureSwingRight || shift+InpStructureSwingLeft>=total)
      return false;
   const double level=rates[shift].high;
   for(int j=shift-InpStructureSwingRight;j<=shift+InpStructureSwingLeft;j++)
     {
      if(j==shift) continue;
      if(rates[j].high>level) return false;
     }
   return true;
  }

bool IsConfirmedSwingLow(const MqlRates &rates[],const int shift)
  {
   const int total=ArraySize(rates);
   if(shift<1+InpStructureSwingRight || shift+InpStructureSwingLeft>=total)
      return false;
   const double level=rates[shift].low;
   for(int j=shift-InpStructureSwingRight;j<=shift+InpStructureSwingLeft;j++)
     {
      if(j==shift) continue;
      if(rates[j].low<level) return false;
     }
   return true;
  }

double ZoneDistanceATR(const double close_price,const double zone_low,
                       const double zone_high,const double atr)
  {
   if(atr<=0.0) return EMPTY_VALUE;
   if(close_price>=zone_low && close_price<=zone_high) return 0.0;
   if(close_price<zone_low) return(zone_low-close_price)/atr;
   return(close_price-zone_high)/atr;
  }

void FindStructureFeatures(const MqlRates &rates[],const double atr,
                           const double close_price,
                           double &support_dist,double &resistance_dist,
                           int &support_touches,int &resistance_touches,
                           string &structure,int &bos_side)
  {
   support_dist=EMPTY_VALUE;
   resistance_dist=EMPTY_VALUE;
   support_touches=0;
   resistance_touches=0;
   structure="UNKNOWN";
   bos_side=0;
   if(atr<=0.0 || !InpEnableStructureFeatures)
      return;

   const int total=ArraySize(rates);
   const int max_shift=MathMin(total-InpStructureSwingLeft-1,
                               InpStructureLookback+InpStructureSwingRight);
   if(max_shift<1+InpStructureSwingRight)
      return;

   double support=-DBL_MAX,resistance=DBL_MAX;
   double last_high=EMPTY_VALUE,prev_high=EMPTY_VALUE;
   double last_low=EMPTY_VALUE,prev_low=EMPTY_VALUE;

   for(int s=1+InpStructureSwingRight;s<=max_shift;s++)
     {
      if(IsConfirmedSwingHigh(rates,s))
        {
         const double level=rates[s].high;
         if(last_high==EMPTY_VALUE) last_high=level;
         else if(prev_high==EMPTY_VALUE) prev_high=level;
         if(level>=close_price && level<resistance)
            resistance=level;
        }
      if(IsConfirmedSwingLow(rates,s))
        {
         const double level=rates[s].low;
         if(last_low==EMPTY_VALUE) last_low=level;
         else if(prev_low==EMPTY_VALUE) prev_low=level;
         if(level<=close_price && level>support)
            support=level;
        }
     }

   const double tolerance=MathMax(atr*InpStructureToleranceATR,_Point);
   if(support>-DBL_MAX/2)
     {
      support_dist=(close_price-support)/atr;
      for(int s=1+InpStructureSwingRight;s<=max_shift;s++)
         if(IsConfirmedSwingLow(rates,s) && MathAbs(rates[s].low-support)<=tolerance)
            support_touches++;
     }
   if(resistance<DBL_MAX/2)
     {
      resistance_dist=(resistance-close_price)/atr;
      for(int s=1+InpStructureSwingRight;s<=max_shift;s++)
         if(IsConfirmedSwingHigh(rates,s) && MathAbs(rates[s].high-resistance)<=tolerance)
            resistance_touches++;
     }

   if(last_high!=EMPTY_VALUE && prev_high!=EMPTY_VALUE &&
      last_low!=EMPTY_VALUE && prev_low!=EMPTY_VALUE)
     {
      if(last_high>prev_high && last_low>prev_low) structure="UP";
      else if(last_high<prev_high && last_low<prev_low) structure="DOWN";
      else structure="RANGE";
     }

   if(last_high!=EMPTY_VALUE && close_price>last_high)
      bos_side=1;
   else if(last_low!=EMPTY_VALUE && close_price<last_low)
      bos_side=-1;
  }

void PreviousDayFeatures(const MqlRates &bar,const double atr,
                         double &high_dist,double &low_dist,
                         int &high_swept,int &low_swept)
  {
   high_dist=EMPTY_VALUE;
   low_dist=EMPTY_VALUE;
   high_swept=0;
   low_swept=0;
   if(atr<=0.0 || !InpEnableStructureFeatures)
      return;
   const double ph=iHigh(_Symbol,PERIOD_D1,1);
   const double pl=iLow(_Symbol,PERIOD_D1,1);
   if(ph<=0.0 || pl<=0.0 || ph<=pl)
      return;
   high_dist=(ph-bar.close)/atr;
   low_dist=(bar.close-pl)/atr;
   high_swept=(bar.high>ph && bar.close<ph)?1:0;
   low_swept=(bar.low<pl && bar.close>pl)?1:0;
  }

double CurrentSessionVWAP(const MqlRates &bar)
  {
   if(!InpEnableStructureFeatures)
      return EMPTY_VALUE;
   MqlDateTime dt;
   TimeToStruct(bar.time,dt);
   dt.hour=0;dt.min=0;dt.sec=0;
   const datetime start=StructToTime(dt);
   int seconds=PeriodSeconds((ENUM_TIMEFRAMES)_Period);
   if(seconds<=0) seconds=60;
   const datetime finish=bar.time+seconds-1;

   MqlRates m1[];
   ArraySetAsSeries(m1,false);
   const int copied=CopyRates(_Symbol,PERIOD_M1,start,finish,m1);
   if(copied<=0)
      return EMPTY_VALUE;

   double weighted=0.0,total_volume=0.0;
   for(int i=0;i<copied;i++)
     {
      const double v=(double)m1[i].tick_volume;
      if(v<=0.0) continue;
      const double typical=(m1[i].high+m1[i].low+m1[i].close)/3.0;
      weighted+=typical*v;
      total_volume+=v;
     }
   if(total_volume<=0.0)
      return EMPTY_VALUE;
   return weighted/total_volume;
  }

void FindActiveFVGFeatures(const MqlRates &rates[],const double atr,
                           const double close_price,
                           double &bull_dist,double &bear_dist)
  {
   bull_dist=EMPTY_VALUE;
   bear_dist=EMPTY_VALUE;
   if(!InpEnableStructureFeatures || atr<=0.0)
      return;
   const int total=ArraySize(rates);
   const int max_shift=MathMin(total-3,InpStructureLookback);
   double best_bull=DBL_MAX,best_bear=DBL_MAX;
   for(int s=1;s<=max_shift;s++)
     {
      const MqlRates newer=rates[s];
      const MqlRates older=rates[s+2];
      if(older.high<newer.low)
        {
         const double zlow=older.high,zhi=newer.low;
         bool mitigated=false;
         for(int j=s-1;j>=1;j--)
            if(rates[j].low<=zhi){mitigated=true;break;}
         if(!mitigated)
           {
            const double d=ZoneDistanceATR(close_price,zlow,zhi,atr);
            if(d<best_bull){best_bull=d;bull_dist=d;}
           }
        }
      if(older.low>newer.high)
        {
         const double zlow=newer.high,zhi=older.low;
         bool mitigated=false;
         for(int j=s-1;j>=1;j--)
            if(rates[j].high>=zlow){mitigated=true;break;}
         if(!mitigated)
           {
            const double d=ZoneDistanceATR(close_price,zlow,zhi,atr);
            if(d<best_bear){best_bear=d;bear_dist=d;}
           }
        }
     }
  }

void FindSupplyDemandFeatures(const MqlRates &rates[],const double atr,
                              const double close_price,
                              double &demand_dist,double &supply_dist)
  {
   demand_dist=EMPTY_VALUE;
   supply_dist=EMPTY_VALUE;
   if(!InpEnableStructureFeatures || atr<=0.0)
      return;
   const int total=ArraySize(rates);
   const int max_shift=MathMin(total-2,InpStructureLookback);
   double best_demand=DBL_MAX,best_supply=DBL_MAX;

   for(int s=1;s<=max_shift;s++)
     {
      const MqlRates impulse=rates[s];
      const MqlRates base=rates[s+1];
      const double base_body=MathAbs(base.close-base.open);
      const double impulse_body=MathAbs(impulse.close-impulse.open);
      if(base_body>0.45*atr || impulse_body<1.0*atr)
         continue;

      if(impulse.close>impulse.open && impulse.close>base.high)
        {
         bool invalid=false;
         for(int j=s-1;j>=1;j--)
            if(rates[j].low<base.low){invalid=true;break;}
         if(!invalid)
           {
            const double zlow=base.low;
            const double zhi=MathMax(base.open,base.close);
            const double d=ZoneDistanceATR(close_price,zlow,zhi,atr);
            if(d<best_demand){best_demand=d;demand_dist=d;}
           }
        }
      else if(impulse.close<impulse.open && impulse.close<base.low)
        {
         bool invalid=false;
         for(int j=s-1;j>=1;j--)
            if(rates[j].high>base.high){invalid=true;break;}
         if(!invalid)
           {
            const double zlow=MathMin(base.open,base.close);
            const double zhi=base.high;
            const double d=ZoneDistanceATR(close_price,zlow,zhi,atr);
            if(d<best_supply){best_supply=d;supply_dist=d;}
           }
        }
     }
  }

double CandlePressure(const MqlRates &rates[])
  {
   if(ArraySize(rates)<2)
      return 0.0;
   const MqlRates b=rates[1];
   const double span=MathMax(b.high-b.low,_Point);
   const int n=MathMin(20,ArraySize(rates)-1);
   double avg_volume=0.0;
   for(int i=1;i<=n;i++)
      avg_volume+=(double)rates[i].tick_volume;
   if(n>0) avg_volume/=n;
   const double ratio=(avg_volume>0.0?(double)b.tick_volume/avg_volume:1.0);
   return((b.close-b.open)/span)*MathLog(1.0+MathMax(0.0,ratio));
  }

void CaptureStructureFeatures(const MqlRates &rates[],const MqlRates &bar,
                              const double atr)
  {
   g_entry_structure="UNKNOWN";
   g_entry_bos_side=0;
   g_entry_support_dist_atr=EMPTY_VALUE;
   g_entry_resistance_dist_atr=EMPTY_VALUE;
   g_entry_support_touches=0;
   g_entry_resistance_touches=0;
   g_entry_prev_high_dist_atr=EMPTY_VALUE;
   g_entry_prev_low_dist_atr=EMPTY_VALUE;
   g_entry_prev_high_swept=0;
   g_entry_prev_low_swept=0;
   g_entry_bull_fvg_dist_atr=EMPTY_VALUE;
   g_entry_bear_fvg_dist_atr=EMPTY_VALUE;
   g_entry_demand_dist_atr=EMPTY_VALUE;
   g_entry_supply_dist_atr=EMPTY_VALUE;
   g_entry_session_vwap_dist_atr=EMPTY_VALUE;
   g_entry_round_dist_atr=EMPTY_VALUE;
   g_entry_candle_pressure=0.0;
   g_entry_previous_day_adr_ratio=KatPreviousDayADRRatio(_Symbol,bar.time);
   g_entry_relative_tick_volume=KatRelativeTickVolume(rates);
   g_entry_chart_breakout=KatConsolidationBreakout(rates,atr);
   g_entry_candle_pattern=KatCandlePattern(rates);
   g_entry_vol_regime="UNKNOWN";

   if(!InpEnableStructureFeatures || atr<=0.0)
      return;

   FindStructureFeatures(rates,atr,bar.close,
                         g_entry_support_dist_atr,g_entry_resistance_dist_atr,
                         g_entry_support_touches,g_entry_resistance_touches,
                         g_entry_structure,g_entry_bos_side);
   PreviousDayFeatures(bar,atr,
                       g_entry_prev_high_dist_atr,g_entry_prev_low_dist_atr,
                       g_entry_prev_high_swept,g_entry_prev_low_swept);
   FindActiveFVGFeatures(rates,atr,bar.close,
                         g_entry_bull_fvg_dist_atr,g_entry_bear_fvg_dist_atr);
   FindSupplyDemandFeatures(rates,atr,bar.close,
                            g_entry_demand_dist_atr,g_entry_supply_dist_atr);

   const double vwap=CurrentSessionVWAP(bar);
   if(vwap!=EMPTY_VALUE)
      g_entry_session_vwap_dist_atr=(bar.close-vwap)/atr;

   if(InpRoundNumberStep>0.0)
     {
      const double nearest=MathRound(bar.close/InpRoundNumberStep)*InpRoundNumberStep;
      g_entry_round_dist_atr=MathAbs(bar.close-nearest)/atr;
     }

   g_entry_candle_pressure=CandlePressure(rates);

   double slow_atr=0.0;
   if(g_atr_slow!=INVALID_HANDLE && ReadValue(g_atr_slow,0,1,slow_atr) && slow_atr>0.0)
     {
      const double ratio=atr/slow_atr;
      if(ratio>1.25) g_entry_vol_regime="HIGH";
      else if(ratio<0.75) g_entry_vol_regime="LOW";
      else g_entry_vol_regime="NORMAL";
     }
  }

void CaptureContextFeatures()
  {
   g_entry_context_regime="UNKNOWN";
   g_entry_context_rsi=EMPTY_VALUE;
   g_entry_context_adx=EMPTY_VALUE;
   g_entry_context_atr_pct=EMPTY_VALUE;
   g_entry_context_ema_gap_atr=EMPTY_VALUE;
   g_entry_context_close_fast_atr=EMPTY_VALUE;
   g_entry_context_structure="UNKNOWN";
   g_entry_context_bos_side=0;
   g_entry_context_support_dist_atr=EMPTY_VALUE;
   g_entry_context_resistance_dist_atr=EMPTY_VALUE;
   g_entry_context_demand_dist_atr=EMPTY_VALUE;
   g_entry_context_supply_dist_atr=EMPTY_VALUE;
   g_entry_context_bull_fvg_dist_atr=EMPTY_VALUE;
   g_entry_context_bear_fvg_dist_atr=EMPTY_VALUE;

   if(!InpEnableFeatureJournal || !InpEnableStructureFeatures)
      return;

   int need=InpStructureLookback+InpStructureSwingLeft+InpStructureSwingRight+5;
   MqlRates ctx[];
   ArraySetAsSeries(ctx,true);
   if(CopyRates(_Symbol,InpContextTF,0,need,ctx)<need)
      return;

   double fast1,slow1,rsi1,adx1,atr1;
   if(!ReadValue(g_ctx_fast,0,1,fast1) ||
      !ReadValue(g_ctx_slow,0,1,slow1) ||
      !ReadValue(g_ctx_rsi,0,1,rsi1) ||
      !ReadValue(g_ctx_adx,0,1,adx1) ||
      !ReadValue(g_ctx_atr,0,1,atr1) ||
      atr1<=0.0)
      return;

   const MqlRates b=ctx[1];
   if(b.close<=0.0)
      return;

   g_entry_context_rsi=rsi1;
   g_entry_context_adx=adx1;
   g_entry_context_atr_pct=100.0*atr1/b.close;
   g_entry_context_ema_gap_atr=(fast1-slow1)/atr1;
   g_entry_context_close_fast_atr=(b.close-fast1)/atr1;

   if(fast1>slow1 && b.close>fast1)
      g_entry_context_regime="UP";
   else if(fast1<slow1 && b.close<fast1)
      g_entry_context_regime="DOWN";
   else
      g_entry_context_regime="MIXED";

   int st=0,rt=0;
   FindStructureFeatures(ctx,atr1,b.close,
                         g_entry_context_support_dist_atr,
                         g_entry_context_resistance_dist_atr,
                         st,rt,
                         g_entry_context_structure,
                         g_entry_context_bos_side);
   FindActiveFVGFeatures(ctx,atr1,b.close,
                         g_entry_context_bull_fvg_dist_atr,
                         g_entry_context_bear_fvg_dist_atr);
   FindSupplyDemandFeatures(ctx,atr1,b.close,
                            g_entry_context_demand_dist_atr,
                            g_entry_context_supply_dist_atr);
  }

void CaptureEntryFeatures(const MqlRates &rates[],
                          const MqlRates &bar,
                          const double ema_fast,
                          const double ema_slow,
                          const double ema_slow_prev,
                          const double rsi,
                          const double atr,
                          const double adx,
                          const double ref_high,
                          const double ref_low,
                          const double fib_retrace,
                          const double sweep_pen)
  {
   if(!InpEnableFeatureJournal || atr<=0.0 || bar.close<=0.0)
      return;
   g_entry_time=bar.time;
   MqlDateTime dt;
   TimeToStruct(bar.time,dt);
   g_entry_hour=dt.hour;
   g_entry_session=ActualSessionLabel(bar.time);
   g_entry_rsi=rsi;
   g_entry_adx=adx;
   g_entry_atr_pct=100.0*atr/bar.close;
   g_entry_ema_slope_atr=(ema_slow-ema_slow_prev)/atr;
   g_entry_close_fast_atr=(bar.close-ema_fast)/atr;
   g_entry_close_slow_atr=(bar.close-ema_slow)/atr;
   g_entry_ref_span_atr=(ref_high-ref_low)/atr;
   g_entry_fib_retrace=fib_retrace;
   g_entry_sweep_pen_atr=sweep_pen;
   MqlTick tick;
   if(SymbolInfoTick(_Symbol,tick))
      g_entry_spread_atr=(tick.ask-tick.bid)/atr;
   else
      g_entry_spread_atr=0.0;
   g_entry_htf_regime=CurrentHTFRegime(g_entry_htf_gap_pct,g_entry_htf_close_fast_pct);
   CaptureStructureFeatures(rates,bar,atr);
   CaptureContextFeatures();
  }

void InitFeatureJournal()
  {
   if(!InpEnableFeatureJournal)
      return;
   const string name="KatarinaFeatureJournal_"+g_run_tag+".csv";
   const int h=FileOpen(name,FILE_WRITE|FILE_CSV|FILE_COMMON,';');
   if(h==INVALID_HANDLE)
     {
      PrintFormat("KAT_FEATURE_JOURNAL_INIT_FAIL err=%d",GetLastError());
      return;
     }
   string columns[];
   ArrayResize(columns,64);
   columns[0]=(string)("run_tag");
   columns[1]=(string)("entry_time");
   columns[2]=(string)("exit_time");
   columns[3]=(string)("side");
   columns[4]=(string)("reason");
   columns[5]=(string)("hour");
   columns[6]=(string)("session");
   columns[7]=(string)("htf_regime");
   columns[8]=(string)("rsi");
   columns[9]=(string)("adx");
   columns[10]=(string)("atr_pct");
   columns[11]=(string)("ema_slope_atr");
   columns[12]=(string)("close_fast_atr");
   columns[13]=(string)("close_slow_atr");
   columns[14]=(string)("htf_gap_pct");
   columns[15]=(string)("htf_close_fast_pct");
   columns[16]=(string)("ref_span_atr");
   columns[17]=(string)("fib_retrace");
   columns[18]=(string)("sweep_pen_atr");
   columns[19]=(string)("spread_atr");
   columns[20]=(string)("structure");
   columns[21]=(string)("bos_side");
   columns[22]=(string)("support_dist_atr");
   columns[23]=(string)("resistance_dist_atr");
   columns[24]=(string)("support_touches");
   columns[25]=(string)("resistance_touches");
   columns[26]=(string)("prev_high_dist_atr");
   columns[27]=(string)("prev_low_dist_atr");
   columns[28]=(string)("prev_high_swept");
   columns[29]=(string)("prev_low_swept");
   columns[30]=(string)("bull_fvg_dist_atr");
   columns[31]=(string)("bear_fvg_dist_atr");
   columns[32]=(string)("demand_dist_atr");
   columns[33]=(string)("supply_dist_atr");
   columns[34]=(string)("session_vwap_dist_atr");
   columns[35]=(string)("round_dist_atr");
   columns[36]=(string)("candle_pressure");
   columns[37]=(string)("vol_regime");
   columns[38]=(string)("context_tf");
   columns[39]=(string)("context_regime");
   columns[40]=(string)("context_rsi");
   columns[41]=(string)("context_adx");
   columns[42]=(string)("context_atr_pct");
   columns[43]=(string)("context_ema_gap_atr");
   columns[44]=(string)("context_close_fast_atr");
   columns[45]=(string)("context_structure");
   columns[46]=(string)("context_bos_side");
   columns[47]=(string)("context_support_dist_atr");
   columns[48]=(string)("context_resistance_dist_atr");
   columns[49]=(string)("context_demand_dist_atr");
   columns[50]=(string)("context_supply_dist_atr");
   columns[51]=(string)("context_bull_fvg_dist_atr");
   columns[52]=(string)("context_bear_fvg_dist_atr");
   columns[53]=(string)("previous_day_adr_ratio");
   columns[54]=(string)("relative_tick_volume");
   columns[55]=(string)("chart_breakout");
   columns[56]=(string)("candle_pattern");
   columns[57]=(string)("mae_r");
   columns[58]=(string)("mfe_r");
   columns[59]=(string)("exit_deal_reason");
   columns[60]=(string)("initial_risk_cash");
   columns[61]=(string)("r_multiple");
   columns[62]=(string)("net_profit");
   columns[63]=(string)("win");
   string csv_line="";
   for(int c=0;c<ArraySize(columns);c++)
     {
      if(c>0) csv_line+=";";
      csv_line+=columns[c];
     }
   FileWriteString(h,csv_line+"\r\n");
   FileClose(h);
  }

void AppendFeatureJournal(const double net,const datetime exit_time)
  {
   if(!InpEnableFeatureJournal || g_entry_time<=0 || g_open_side==0)
      return;
   const string name="KatarinaFeatureJournal_"+g_run_tag+".csv";
   const int h=FileOpen(name,FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON,';');
   if(h==INVALID_HANDLE)
     {
      PrintFormat("KAT_FEATURE_JOURNAL_APPEND_FAIL err=%d",GetLastError());
      return;
     }
   FileSeek(h,0,SEEK_END);
   string columns[];
   ArrayResize(columns,64);
   columns[0]=(string)(g_run_tag);
   columns[1]=(string)(TimeToString(g_entry_time,TIME_DATE|TIME_MINUTES));
   columns[2]=(string)(TimeToString(exit_time,TIME_DATE|TIME_MINUTES));
   columns[3]=(string)((g_open_side>0?"BUY":"SELL"));
   columns[4]=(string)(g_open_reason);
   columns[5]=(string)(g_entry_hour);
   columns[6]=(string)(g_entry_session);
   columns[7]=(string)(g_entry_htf_regime);
   columns[8]=(string)(DoubleToString(g_entry_rsi,4));
   columns[9]=(string)(DoubleToString(g_entry_adx,4));
   columns[10]=(string)(DoubleToString(g_entry_atr_pct,6));
   columns[11]=(string)(DoubleToString(g_entry_ema_slope_atr,6));
   columns[12]=(string)(DoubleToString(g_entry_close_fast_atr,6));
   columns[13]=(string)(DoubleToString(g_entry_close_slow_atr,6));
   columns[14]=(string)(DoubleToString(g_entry_htf_gap_pct,6));
   columns[15]=(string)(DoubleToString(g_entry_htf_close_fast_pct,6));
   columns[16]=(string)(DoubleToString(g_entry_ref_span_atr,6));
   columns[17]=(string)(DoubleToString(g_entry_fib_retrace,6));
   columns[18]=(string)(DoubleToString(g_entry_sweep_pen_atr,6));
   columns[19]=(string)(DoubleToString(g_entry_spread_atr,6));
   columns[20]=(string)(g_entry_structure);
   columns[21]=(string)(g_entry_bos_side);
   columns[22]=(string)(FeatureValue(g_entry_support_dist_atr));
   columns[23]=(string)(FeatureValue(g_entry_resistance_dist_atr));
   columns[24]=(string)(g_entry_support_touches);
   columns[25]=(string)(g_entry_resistance_touches);
   columns[26]=(string)(FeatureValue(g_entry_prev_high_dist_atr));
   columns[27]=(string)(FeatureValue(g_entry_prev_low_dist_atr));
   columns[28]=(string)(g_entry_prev_high_swept);
   columns[29]=(string)(g_entry_prev_low_swept);
   columns[30]=(string)(FeatureValue(g_entry_bull_fvg_dist_atr));
   columns[31]=(string)(FeatureValue(g_entry_bear_fvg_dist_atr));
   columns[32]=(string)(FeatureValue(g_entry_demand_dist_atr));
   columns[33]=(string)(FeatureValue(g_entry_supply_dist_atr));
   columns[34]=(string)(FeatureValue(g_entry_session_vwap_dist_atr));
   columns[35]=(string)(FeatureValue(g_entry_round_dist_atr));
   columns[36]=(string)(DoubleToString(g_entry_candle_pressure,6));
   columns[37]=(string)(g_entry_vol_regime);
   columns[38]=(string)(EnumToString(InpContextTF));
   columns[39]=(string)(g_entry_context_regime);
   columns[40]=(string)(FeatureValue(g_entry_context_rsi,4));
   columns[41]=(string)(FeatureValue(g_entry_context_adx,4));
   columns[42]=(string)(FeatureValue(g_entry_context_atr_pct));
   columns[43]=(string)(FeatureValue(g_entry_context_ema_gap_atr));
   columns[44]=(string)(FeatureValue(g_entry_context_close_fast_atr));
   columns[45]=(string)(g_entry_context_structure);
   columns[46]=(string)(g_entry_context_bos_side);
   columns[47]=(string)(FeatureValue(g_entry_context_support_dist_atr));
   columns[48]=(string)(FeatureValue(g_entry_context_resistance_dist_atr));
   columns[49]=(string)(FeatureValue(g_entry_context_demand_dist_atr));
   columns[50]=(string)(FeatureValue(g_entry_context_supply_dist_atr));
   columns[51]=(string)(FeatureValue(g_entry_context_bull_fvg_dist_atr));
   columns[52]=(string)(FeatureValue(g_entry_context_bear_fvg_dist_atr));
   columns[53]=(string)(FeatureValue(g_entry_previous_day_adr_ratio));
   columns[54]=(string)(FeatureValue(g_entry_relative_tick_volume));
   columns[55]=(string)(FeatureValue(g_entry_chart_breakout));
   columns[56]=(string)(FeatureValue(g_entry_candle_pattern));
   columns[57]=(string)(FeatureValue(g_mae_r));
   columns[58]=(string)(FeatureValue(g_mfe_r));
   columns[59]=(string)(IntegerToString(g_exit_reason));
   columns[60]=(string)(DoubleToString(g_entry_risk_cash,2));
   columns[61]=(string)(DoubleToString((g_entry_risk_cash>0.0?net/g_entry_risk_cash:0.0),6));
   columns[62]=(string)(DoubleToString(net,2));
   columns[63]=(string)((net>0.0?"1":"0"));
   string csv_line="";
   for(int c=0;c<ArraySize(columns);c++)
     {
      if(c>0) csv_line+=";";
      csv_line+=columns[c];
     }
   FileWriteString(h,csv_line+"\r\n");
   FileClose(h);
  }

bool HTFAllows(const int side)
  {
   if(!InpUseHTFTrend)
      return true;
   double fast1,slow1;
   if(!ReadValue(g_htf_fast,0,1,fast1) || !ReadValue(g_htf_slow,0,1,slow1))
      return false;
   const double close1=iClose(_Symbol,InpHTF,1);
   if(close1<=0.0)
      return false;
   if(side>0)
      return(fast1>slow1 && close1>fast1);
   return(fast1<slow1 && close1<fast1);
  }

bool MethodAllows(const EKatarinaResearchMethod method,
                  const bool pullback,
                  const bool sweep,
                  const bool fib,
                  const bool reversal)
  {
   if(method==KRM_PULLBACK)
      return pullback;
   if(method==KRM_LQ_SWEEP)
      return sweep;
   if(method==KRM_FIB_PULLBACK)
      return pullback && fib;
   if(method==KRM_HYBRID)
      return pullback && (sweep || fib);
   if(method==KRM_SWEEP_REVERSAL)
      return reversal;
   return false;
  }

string BuildReason(const bool pullback,const bool sweep,const bool fib)
  {
   string reason="";
   if(pullback) reason="PULLBACK";
   if(sweep) reason+=(reason==""?"":"+")+"LQ_SWEEP";
   if(fib) reason+=(reason==""?"":"+")+"FIBO";
   return reason;
  }

bool BuyResearchFilterAllows()
  {
   if(InpBuyResearchFilter==KBRF_NONE)
      return true;

   const bool has_close=MathIsValidNumber(g_entry_close_fast_atr);
   const bool has_demand=(g_entry_context_demand_dist_atr!=EMPTY_VALUE &&
                          MathIsValidNumber(g_entry_context_demand_dist_atr));
   const bool has_support=(g_entry_context_support_dist_atr!=EMPTY_VALUE &&
                           MathIsValidNumber(g_entry_context_support_dist_atr));
   const bool has_session_vwap=(g_entry_session_vwap_dist_atr!=EMPTY_VALUE &&
                                MathIsValidNumber(g_entry_session_vwap_dist_atr));
   const bool has_round=(g_entry_round_dist_atr!=EMPTY_VALUE &&
                         MathIsValidNumber(g_entry_round_dist_atr));

   if(InpBuyResearchFilter==KBRF_CLOSE_DEMAND)
      return(has_close && has_demand &&
             g_entry_close_fast_atr>=InpFilterMinCloseFastATR &&
             g_entry_context_demand_dist_atr>=InpFilterMinContextDemandATR);

   if(InpBuyResearchFilter==KBRF_DEMAND_SUPPORT)
      return(has_demand && has_support &&
             g_entry_context_demand_dist_atr>=InpFilterMinContextDemandATR &&
             g_entry_context_support_dist_atr>=InpFilterMinContextSupportATR);

   if(InpBuyResearchFilter==KBRF_CLOSE_SUPPORT)
      return(has_close && has_support &&
             g_entry_close_fast_atr>=InpFilterMinCloseFastATR &&
             g_entry_context_support_dist_atr>=InpFilterMinContextSupportATR);

   if(InpBuyResearchFilter==KBRF_CONTEXT_DEMAND_ONLY)
      return(has_demand &&
             g_entry_context_demand_dist_atr>=InpFilterCleanContextDemandATR);

   if(InpBuyResearchFilter==KBRF_SESSION_VWAP_MAX)
      return(has_session_vwap &&
             g_entry_session_vwap_dist_atr<=InpFilterMaxSessionVWAPATR);

   if(InpBuyResearchFilter==KBRF_CONTEXT_DEMAND_STRUCTURE_RANGE)
      return(has_demand &&
             g_entry_context_demand_dist_atr>=InpFilterCleanContextDemandATR &&
             g_entry_structure=="RANGE");

   if(InpBuyResearchFilter==KBRF_DEMAND_SUPPORT_ROUND)
      return(has_demand && has_support && has_round &&
             g_entry_context_demand_dist_atr>=InpFilterMinContextDemandATR &&
             g_entry_context_support_dist_atr>=InpFilterMinContextSupportATR &&
             g_entry_round_dist_atr<=InpFilterMaxRoundATR);

   return false;
  }

bool ExistingResearchPosition()
  {
   if(!PositionSelect(_Symbol))
      return false;
   const long magic=PositionGetInteger(POSITION_MAGIC);
   return(magic==InpMagic);
  }

bool GetReferenceRange(const MqlRates &rates[],double &ref_high,double &ref_low)
  {
   const int total=ArraySize(rates);
   if(total<InpLookbackBars+3)
      return false;
   ref_high=-DBL_MAX;
   ref_low=DBL_MAX;
   const int last=MathMin(total-1,InpLookbackBars+1);
   for(int i=2;i<=last;i++)
     {
      if(rates[i].high>ref_high) ref_high=rates[i].high;
      if(rates[i].low<ref_low) ref_low=rates[i].low;
     }
   return(ref_high>ref_low && ref_low>0.0);
  }

bool OpenResearchTrade(const int side,
                       const string reason,
                       const double atr)
  {
   if(!MQLInfoInteger(MQL_TESTER))
      return false;
   if(InpResearchContextGate!="" && g_entry_context_regime!=InpResearchContextGate)
     {
      g_entries_rejected_filter++;
      return false;
     }
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return false;
   const double spread=tick.ask-tick.bid;
   if(spread<0.0 || spread>InpMaxSpreadATR*atr)
     {
      g_entries_rejected_spread++;
      return false;
     }

   const int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   const double entry=(side>0?tick.ask:tick.bid);
   const double sl_mult=(side>0?InpBuySLATR:InpSellSLATR);
   const double rr=(side>0?InpBuyRR:InpSellRR);
   const bool zone_mode=(side>0?InpBuyMethod:InpSellMethod)==KRM_ZONE_SCALP;
   if(zone_mode && !ZoneTradingSessionAllows())
     { g_diag_session_reject++; return false; }
   const double zone_stop=(side>0?g_zone_buy_sl:g_zone_sell_sl);
   const double risk=(zone_mode?side*(entry-zone_stop):sl_mult*atr);
   if(zone_mode && (risk<atr || risk>3.0*atr || spread>0.1*risk))
      return false;
   if(risk<=0.0 || rr<=1.0)
      return false;

   const double sl=NormalizeDouble(entry-(side>0?1.0:-1.0)*risk,digits);
   const double tp=NormalizeDouble(entry+(side>0?1.0:-1.0)*risk*rr,digits);
   double volume=InpLot;
   if(zone_mode)
     {
      double projected;
      const double minlot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
      const double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
      const double maxlot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
      if(minlot<=0 || step<=0 || !OrderCalcProfit(side>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,
            _Symbol,minlot,entry,sl,projected) || projected>=0) return false;
      const double raw=InpZoneRiskCash/MathAbs(projected)*minlot;
      if(raw<minlot) return false;
      volume=NormalizeDouble(minlot+MathFloor((MathMin(raw,maxlot)-minlot)/step+1e-9)*step,8);
      double actual_risk;
      if(!OrderCalcProfit(side>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,volume,entry,sl,actual_risk) ||
         MathAbs(actual_risk)>InpZoneRiskCash+0.001) return false;
     }
   const string comment="KAT3:"+reason;

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);
   bool ok=false;
   if(side>0)
      ok=g_trade.Buy(volume,_Symbol,0.0,sl,tp,comment);
   else
      ok=g_trade.Sell(volume,_Symbol,0.0,sl,tp,comment);

   ok=ok && (g_trade.ResultRetcode()==TRADE_RETCODE_DONE ||
             g_trade.ResultRetcode()==TRADE_RETCODE_DONE_PARTIAL) && PositionSelect(_Symbol);
   if(ok)
     {
      g_mae_r=0.0; g_mfe_r=0.0; g_exit_reason=-1;
      g_actual_entry=PositionGetDouble(POSITION_PRICE_OPEN);
      g_initial_price_risk=MathAbs(g_actual_entry-PositionGetDouble(POSITION_SL));
      g_entry_time=(datetime)PositionGetInteger(POSITION_TIME);
      g_open_reason=reason;
      g_open_side=side;
      g_entry_risk_cash=0.0;
      if(PositionSelect(_Symbol))
        {
         const double actual_entry=PositionGetDouble(POSITION_PRICE_OPEN);
         const double actual_sl=PositionGetDouble(POSITION_SL);
         double projected=0.0;
         const ENUM_ORDER_TYPE order_type=(side>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
         if(actual_entry>0.0 && actual_sl>0.0 &&
            OrderCalcProfit(order_type,_Symbol,PositionGetDouble(POSITION_VOLUME),actual_entry,actual_sl,projected))
            g_entry_risk_cash=MathAbs(projected);
        }
     }
   if(ok && zone_mode)
     {
      if(side>0) AuditZoneFill(g_run_tag,g_demand,iTime(_Symbol,_Period,1),g_actual_entry,
         PositionGetDouble(POSITION_SL),PositionGetDouble(POSITION_VOLUME),g_entry_risk_cash);
      else AuditZoneFill(g_run_tag,g_supply,iTime(_Symbol,_Period,1),g_actual_entry,
         PositionGetDouble(POSITION_SL),PositionGetDouble(POSITION_VOLUME),g_entry_risk_cash);
     }
   return ok;
  }

bool ResearchSRRejection(const MqlRates &rates[],const double atr,const int side)
  {
   // Closest previously confirmed swing; current signal bar cannot confirm the pivot.
   double level=EMPTY_VALUE;
   for(int i=2+InpStructureSwingRight;i<MathMin(ArraySize(rates)-InpStructureSwingLeft,80);i++)
     {
      if(side>0 && IsConfirmedSwingLow(rates,i)) { level=rates[i].low; break; }
      if(side<0 && IsConfirmedSwingHigh(rates,i)) { level=rates[i].high; break; }
     }
   if(level==EMPTY_VALUE) return false;
   const MqlRates b=rates[1];
   if(side>0) return b.low<=level+0.2*atr && b.low>=level-0.5*atr &&
                       b.close>level && b.close>b.open && b.close-b.low>=0.6*(b.high-b.low);
   return b.high>=level-0.2*atr && b.high<=level+0.5*atr &&
          b.close<level && b.close<b.open && b.high-b.close>=0.6*(b.high-b.low);
  }

bool ResearchBreakoutRetest(const MqlRates &rates[],const double atr,const int side)
  {
   if(ArraySize(rates)<24) return false;
   // Breakout is bar 2; level derived from bars 3..22; bar 1 is the retest.
   double hi=rates[3].high,lo=rates[3].low;
   for(int i=4;i<=22;i++) { hi=MathMax(hi,rates[i].high); lo=MathMin(lo,rates[i].low); }
   const MqlRates b=rates[1], breakout=rates[2];
   if(side>0) return breakout.close>hi+0.1*atr &&
      b.low<=hi+0.2*atr && b.low>=hi-0.3*atr && b.close>hi && b.close>b.open;
   return breakout.close<lo-0.1*atr &&
      b.high>=lo-0.2*atr && b.high<=lo+0.3*atr && b.close<lo && b.close<b.open;
  }

void TrackResearchExcursion(const double price)
  {
   if(g_open_side==0 || g_initial_price_risk<=0.0 || price<=0.0) return;
   double r=g_open_side*(price-g_actual_entry)/g_initial_price_risk;
   g_mae_r=MathMax(g_mae_r,-r); g_mfe_r=MathMax(g_mfe_r,r);
  }

void LogResearchOpportunity(const datetime time,const bool occupied,const double adx,const int trend,
   const bool bp,const bool sp,const bool br,const bool sr,const bool bb,const bool sb,
   const bool buy_allowed,const bool sell_allowed)
  {
   if(!InpEnableOpportunityJournal) return;
   if(g_opportunity_handle==INVALID_HANDLE)
     {
      g_opportunity_handle=FileOpen("KatarinaOpportunity_"+g_run_tag+".csv",FILE_WRITE|FILE_CSV|FILE_COMMON,';');
      if(g_opportunity_handle==INVALID_HANDLE) return;
      FileWrite(g_opportunity_handle,"run_tag","signal_bar_time","observed_time","occupied","adx","trend",
         "buy_pullback","sell_pullback","buy_sr","sell_sr","buy_breakout","sell_breakout",
         "buy_method_allowed","sell_method_allowed","adx_gate","spread_gate");
     }
   MqlTick tick;
   double atr=0.0;
   bool spread_ok=ReadValue(g_atr,0,1,atr) && atr>0.0 && SymbolInfoTick(_Symbol,tick) &&
                  tick.ask>=tick.bid && tick.ask-tick.bid<=InpMaxSpreadATR*atr;
   FileWrite(g_opportunity_handle,g_run_tag,TimeToString(time,TIME_DATE|TIME_SECONDS),
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),occupied,DoubleToString(adx,4),trend,
      bp,sp,br,sr,bb,sb,buy_allowed,sell_allowed,adx>=InpMinADX,spread_ok);
   // Outcomes of unexecuted opportunities remain UNKNOWN, never fabricated as losses.
  }

void EvaluateClosedBar()
  {
   g_diag_bars_seen++;
   const bool occupied=ExistingResearchPosition();
   if(occupied) g_diag_existing_position_skip++;

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   int need=InpLookbackBars+5;
   if(InpEnableStructureFeatures)
      need=MathMax(need,InpStructureLookback+InpStructureSwingLeft+InpStructureSwingRight+5);
   if(CopyRates(_Symbol,_Period,0,need,rates)<need)
     {
      g_diag_copyrates_reject++;
      return;
     }

   double ema_fast1,ema_slow1,ema_slow2,rsi1,atr1,adx1;
   if(!ReadValue(g_ema_fast,0,1,ema_fast1) ||
      !ReadValue(g_ema_slow,0,1,ema_slow1) ||
      !ReadValue(g_ema_slow,0,2,ema_slow2) ||
      !ReadValue(g_rsi,0,1,rsi1) ||
      !ReadValue(g_atr,0,1,atr1) ||
      !ReadValue(g_adx,0,1,adx1))
     {
      g_diag_indicator_reject++;
      return;
     }
   if(atr1<=0.0)
     {
      g_diag_adx_reject++;
      return;
     }

   double ref_high,ref_low;
   if(!GetReferenceRange(rates,ref_high,ref_low))
     {
      g_diag_reference_reject++;
      return;
     }
   const double span=ref_high-ref_low;
   if(span<=0.0)
     {
      g_diag_reference_reject++;
      return;
     }

   const MqlRates b=rates[1];
   if(InpEntryStopTime!="")
     {
      const datetime stop_time=StringToTime(InpEntryStopTime);
      if(stop_time>0 && b.time>=stop_time)
        {
         g_diag_entry_stop_reject++;
         return;
        }
     }
   if(!SessionAllows(b.time))
     {
      g_diag_session_reject++;
      return;
     }

   const bool buy_trend=(ema_slow1>ema_slow2 && b.close>ema_slow1);
   const bool sell_trend=(ema_slow1<ema_slow2 && b.close<ema_slow1);
   if(buy_trend) g_diag_buy_trend_true++;
   if(sell_trend) g_diag_sell_trend_true++;

   const bool buy_pullback=buy_trend &&
      b.low<=ema_fast1+InpPullbackToleranceATR*atr1 &&
      b.close>=ema_fast1 && b.close>b.open &&
      rsi1>=InpBuyRSIMin && rsi1<=InpBuyRSIMax;

   const bool sell_pullback=sell_trend &&
      b.high>=ema_fast1-InpPullbackToleranceATR*atr1 &&
      b.close<=ema_fast1 && b.close<b.open &&
      rsi1>=InpSellRSIMin && rsi1<=InpSellRSIMax;
   if(buy_pullback) g_diag_buy_pullback_true++;
   if(sell_pullback) g_diag_sell_pullback_true++;

   const double buy_pen=MathMax(0.0,ref_low-b.low)/atr1;
   const double sell_pen=MathMax(0.0,b.high-ref_high)/atr1;
   const bool buy_sweep=buy_pen>=InpSweepMinATR && buy_pen<=InpSweepMaxATR &&
      b.low<ref_low && b.close>ref_low && b.close>b.open;
   const bool sell_sweep=sell_pen>=InpSweepMinATR && sell_pen<=InpSweepMaxATR &&
      b.high>ref_high && b.close<ref_high && b.close<b.open;
   if(buy_sweep) g_diag_buy_sweep_true++;
   if(sell_sweep) g_diag_sell_sweep_true++;

   const double buy_fib=(ref_high-b.close)/span;
   const double sell_fib=(b.close-ref_low)/span;
   const bool buy_fibo=buy_fib>=InpFibMin && buy_fib<=InpFibMax;
   const bool sell_fibo=sell_fib>=InpFibMin && sell_fib<=InpFibMax;
   if(buy_fibo) g_diag_buy_fibo_true++;
   if(sell_fibo) g_diag_sell_fibo_true++;

   const bool buy_reversal=buy_sweep && rsi1<=InpBuyReversalRSIMax &&
      adx1<=InpReversalMaxADX;
   const bool sell_reversal=sell_sweep && rsi1>=InpSellReversalRSIMin &&
      adx1<=InpReversalMaxADX;

   const bool buy_needs_htf=(InpBuyMethod!=KRM_SWEEP_REVERSAL);
   const bool sell_needs_htf=(InpSellMethod!=KRM_SWEEP_REVERSAL);
   const bool buy_htf_ok=(!buy_needs_htf || HTFAllows(1));
   const bool sell_htf_ok=(!sell_needs_htf || HTFAllows(-1));
   const bool buy_sr=ResearchSRRejection(rates,atr1,1);
   const bool sell_sr=ResearchSRRejection(rates,atr1,-1);
   const bool buy_break=ResearchBreakoutRetest(rates,atr1,1);
   const bool sell_break=ResearchBreakoutRetest(rates,atr1,-1);
   bool buy_zone=false,sell_zone=false;
   if(InpBuyMethod==KRM_ZONE_SCALP || InpSellMethod==KRM_ZONE_SCALP)
     {
      UpdateResearchZones();
      buy_zone=ZoneSignal(g_demand,b,atr1,g_zone_buy_sl);
      sell_zone=ZoneSignal(g_supply,b,atr1,g_zone_sell_sl);
     }
   const bool buy_method_ok=(InpBuyMethod==KRM_ZONE_SCALP?buy_zone:
      (InpBuyMethod==KRM_SR_REJECTION?buy_sr:
      (InpBuyMethod==KRM_BREAKOUT_RETEST?buy_break:
       MethodAllows(InpBuyMethod,buy_pullback,buy_sweep,buy_fibo,buy_reversal))));
   const bool sell_method_ok=(InpSellMethod==KRM_ZONE_SCALP?sell_zone:
      (InpSellMethod==KRM_SR_REJECTION?sell_sr:
      (InpSellMethod==KRM_BREAKOUT_RETEST?sell_break:
       MethodAllows(InpSellMethod,sell_pullback,sell_sweep,sell_fibo,sell_reversal))));
   if(buy_htf_ok) g_diag_buy_htf_true++;
   if(buy_method_ok) g_diag_buy_method_true++;
   if(sell_htf_ok) g_diag_sell_htf_true++;
   if(sell_method_ok) g_diag_sell_method_true++;
   const bool buy_allowed=InpEnableBuy && buy_htf_ok && buy_method_ok;
   const bool sell_allowed=InpEnableSell && sell_htf_ok && sell_method_ok;

   LogResearchOpportunity(b.time,occupied,adx1,ema_fast1>ema_slow1?1:-1,
      buy_pullback,sell_pullback,buy_sr,sell_sr,buy_break,sell_break,buy_allowed,sell_allowed);
   if(occupied) return;
   if(adx1<InpMinADX) { g_diag_adx_reject++; return; }
   if(buy_allowed && sell_allowed)
     {
      // Ambiguous bar: do not manufacture direction.
      g_diag_ambiguous_reject++;
      return;
     }

   if(buy_allowed)
     {
      g_signals_buy++;
      string reason=BuildReason(buy_pullback,buy_sweep,buy_fibo);
      if(InpBuyMethod==KRM_SR_REJECTION) reason="SR_REJECTION";
      if(InpBuyMethod==KRM_BREAKOUT_RETEST) reason="BREAKOUT_RETEST";
      if(InpBuyMethod==KRM_ZONE_SCALP) reason="ZONE_SCALP";
      if(buy_reversal && InpBuyMethod!=KRM_ZONE_SCALP) reason+=(reason==""?"":"+")+"REVERSAL";
      if(InpUseHTFTrend && buy_needs_htf) reason+="+HTF";
      if(InpSessionMode!=KSM_ALL) reason+="+SESSION";
      CaptureEntryFeatures(rates,b,ema_fast1,ema_slow1,ema_slow2,rsi1,atr1,adx1,
                           ref_high,ref_low,buy_fib,buy_pen);
      if(!BuyResearchFilterAllows())
        {
         g_entries_rejected_filter++;
         return;
        }
      OpenResearchTrade(1,reason,atr1);
     }
   else if(sell_allowed)
     {
      g_signals_sell++;
      string reason=BuildReason(sell_pullback,sell_sweep,sell_fibo);
      if(InpSellMethod==KRM_SR_REJECTION) reason="SR_REJECTION";
      if(InpSellMethod==KRM_BREAKOUT_RETEST) reason="BREAKOUT_RETEST";
      if(InpSellMethod==KRM_ZONE_SCALP) reason="ZONE_SCALP";
      if(sell_reversal && InpSellMethod!=KRM_ZONE_SCALP) reason+=(reason==""?"":"+")+"REVERSAL";
      if(InpUseHTFTrend && sell_needs_htf) reason+="+HTF";
      if(InpSessionMode!=KSM_ALL) reason+="+SESSION";
      CaptureEntryFeatures(rates,b,ema_fast1,ema_slow1,ema_slow2,rsi1,atr1,adx1,
                           ref_high,ref_low,sell_fib,sell_pen);
      OpenResearchTrade(-1,reason,atr1);
     }
  }

void RecordClosedTrade(const double net)
  {
   const bool win=(net>0.0);
   g_net_profit+=net;
   if(net>0.0) g_gross_profit+=net;
   else if(net<0.0) g_gross_loss+=MathAbs(net);

   if(g_open_side>0)
     {
      g_buy_trades++;
      if(win) g_buy_wins++;
     }
   else if(g_open_side<0)
     {
      g_sell_trades++;
      if(win) g_sell_wins++;
     }

   if(HasReason(g_open_reason,"PULLBACK"))
     {
      g_pullback_trades++;
      if(win) g_pullback_wins++;
     }
   if(HasReason(g_open_reason,"LQ_SWEEP"))
     {
      g_sweep_trades++;
      if(win) g_sweep_wins++;
     }
   if(HasReason(g_open_reason,"FIBO"))
     {
      g_fibo_trades++;
      if(win) g_fibo_wins++;
     }
   if(HasReason(g_open_reason,"REVERSAL"))
     {
      g_reversal_trades++;
      if(win) g_reversal_wins++;
     }

   g_open_reason="";
   g_open_side=0;
   g_entry_risk_cash=0.0;
  }

double Rate(const int wins,const int total)
  {
   if(total<=0) return 0.0;
   return 100.0*(double)wins/(double)total;
  }

int FindPositionIndex(const ulong &ids[],const ulong id)
  {
   const int n=ArraySize(ids);
   for(int i=0;i<n;i++)
      if(ids[i]==id)
         return i;
   return -1;
  }

void RebuildStatsFromHistory()
  {
   g_buy_trades=0; g_buy_wins=0; g_sell_trades=0; g_sell_wins=0;
   g_pullback_trades=0; g_pullback_wins=0;
   g_sweep_trades=0; g_sweep_wins=0;
   g_fibo_trades=0; g_fibo_wins=0;
   g_reversal_trades=0; g_reversal_wins=0;
   g_gross_profit=0.0; g_gross_loss=0.0; g_net_profit=0.0;

   if(!HistorySelect(0,TimeCurrent()))
      return;

   ulong ids[];
   int sides[];
   string reasons[];
   double nets[];
   bool closed[];

   const int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
     {
      const ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=InpMagic) continue;

      const ulong pid=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
      if(pid==0) continue;

      int idx=FindPositionIndex(ids,pid);
      if(idx<0)
        {
         idx=ArraySize(ids);
         ArrayResize(ids,idx+1);
         ArrayResize(sides,idx+1);
         ArrayResize(reasons,idx+1);
         ArrayResize(nets,idx+1);
         ArrayResize(closed,idx+1);
         ids[idx]=pid;
         sides[idx]=0;
         reasons[idx]="";
         nets[idx]=0.0;
         closed[idx]=false;
        }

      const long entry=HistoryDealGetInteger(ticket,DEAL_ENTRY);
      const long type=HistoryDealGetInteger(ticket,DEAL_TYPE);
      const string comment=HistoryDealGetString(ticket,DEAL_COMMENT);

      if(entry==DEAL_ENTRY_IN || entry==DEAL_ENTRY_INOUT)
        {
         if(type==DEAL_TYPE_BUY) sides[idx]=1;
         else if(type==DEAL_TYPE_SELL) sides[idx]=-1;
         if(StringFind(comment,"KAT3:")==0)
            reasons[idx]=StringSubstr(comment,5);
        }

      nets[idx]+=
         HistoryDealGetDouble(ticket,DEAL_PROFIT)+
         HistoryDealGetDouble(ticket,DEAL_COMMISSION)+
         HistoryDealGetDouble(ticket,DEAL_SWAP);

      if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)
         closed[idx]=true;
     }

   const int n=ArraySize(ids);
   for(int i=0;i<n;i++)
     {
      if(!closed[i] || sides[i]==0)
         continue;
      const double net=nets[i];
      const bool win=(net>0.0);
      g_net_profit+=net;
      if(net>0.0) g_gross_profit+=net;
      else if(net<0.0) g_gross_loss+=MathAbs(net);

      if(sides[i]>0)
        {
         g_buy_trades++;
         if(win) g_buy_wins++;
        }
      else
        {
         g_sell_trades++;
         if(win) g_sell_wins++;
        }

      if(HasReason(reasons[i],"PULLBACK"))
        {
         g_pullback_trades++;
         if(win) g_pullback_wins++;
        }
      if(HasReason(reasons[i],"LQ_SWEEP"))
        {
         g_sweep_trades++;
         if(win) g_sweep_wins++;
        }
      if(HasReason(reasons[i],"FIBO"))
        {
         g_fibo_trades++;
         if(win) g_fibo_wins++;
        }
      if(HasReason(reasons[i],"REVERSAL"))
        {
         g_reversal_trades++;
         if(win) g_reversal_wins++;
        }
     }
  }

void WriteSummary()
  {
   const string name="KatarinaResearchScalper_"+g_run_tag+".csv";
   const int h=FileOpen(name,FILE_WRITE|FILE_CSV|FILE_COMMON,';');
   if(h==INVALID_HANDLE)
     {
      PrintFormat("KAT3_SUMMARY_WRITE_FAIL err=%d",GetLastError());
      return;
     }
   FileWrite(h,
      "run_tag","symbol","period","buy_enabled","sell_enabled","buy_method","sell_method",
      "buy_trades","buy_wins","buy_winrate",
      "sell_trades","sell_wins","sell_winrate",
      "pullback_trades","pullback_wins","pullback_winrate",
      "sweep_trades","sweep_wins","sweep_winrate",
      "fibo_trades","fibo_wins","fibo_winrate",
      "reversal_trades","reversal_wins","reversal_winrate",
      "gross_profit","gross_loss","profit_factor","net_profit",
      "signals_buy","signals_sell","spread_rejects","filter_rejects",
      "diag_bars_seen","diag_existing_position_skip","diag_copyrates_reject",
      "diag_indicator_reject","diag_adx_reject","diag_reference_reject",
      "diag_entry_stop_reject","diag_session_reject",
      "diag_buy_trend_true","diag_buy_pullback_true","diag_buy_sweep_true",
      "diag_buy_fibo_true","diag_buy_htf_true","diag_buy_method_true",
      "diag_sell_trend_true","diag_sell_pullback_true","diag_sell_sweep_true",
      "diag_sell_fibo_true","diag_sell_htf_true","diag_sell_method_true",
      "diag_ambiguous_reject");
   const double pf=(g_gross_loss>0.0?g_gross_profit/g_gross_loss:(g_gross_profit>0.0?999.0:0.0));
   FileWrite(h,
      g_run_tag,_Symbol,EnumToString((ENUM_TIMEFRAMES)_Period),
      (InpEnableBuy?"1":"0"),(InpEnableSell?"1":"0"),
      EnumToString(InpBuyMethod),EnumToString(InpSellMethod),
      g_buy_trades,g_buy_wins,DoubleToString(Rate(g_buy_wins,g_buy_trades),2),
      g_sell_trades,g_sell_wins,DoubleToString(Rate(g_sell_wins,g_sell_trades),2),
      g_pullback_trades,g_pullback_wins,DoubleToString(Rate(g_pullback_wins,g_pullback_trades),2),
      g_sweep_trades,g_sweep_wins,DoubleToString(Rate(g_sweep_wins,g_sweep_trades),2),
      g_fibo_trades,g_fibo_wins,DoubleToString(Rate(g_fibo_wins,g_fibo_trades),2),
      g_reversal_trades,g_reversal_wins,DoubleToString(Rate(g_reversal_wins,g_reversal_trades),2),
      DoubleToString(g_gross_profit,2),DoubleToString(g_gross_loss,2),
      DoubleToString(pf,3),DoubleToString(g_net_profit,2),
      g_signals_buy,g_signals_sell,g_entries_rejected_spread,g_entries_rejected_filter,
      g_diag_bars_seen,g_diag_existing_position_skip,g_diag_copyrates_reject,
      g_diag_indicator_reject,g_diag_adx_reject,g_diag_reference_reject,
      g_diag_entry_stop_reject,g_diag_session_reject,
      g_diag_buy_trend_true,g_diag_buy_pullback_true,g_diag_buy_sweep_true,
      g_diag_buy_fibo_true,g_diag_buy_htf_true,g_diag_buy_method_true,
      g_diag_sell_trend_true,g_diag_sell_pullback_true,g_diag_sell_sweep_true,
      g_diag_sell_fibo_true,g_diag_sell_htf_true,g_diag_sell_method_true,
      g_diag_ambiguous_reject);
   FileClose(h);
   PrintFormat("KAT3_SUMMARY run=%s buy=%d/%d(%.2f%%) sell=%d/%d(%.2f%%) PF=%.3f net=%.2f",
               g_run_tag,g_buy_wins,g_buy_trades,Rate(g_buy_wins,g_buy_trades),
               g_sell_wins,g_sell_trades,Rate(g_sell_wins,g_sell_trades),pf,g_net_profit);
   PrintFormat("KAT3_DIAG_BUY bars=%d adx_reject=%d trend=%d pullback=%d sweep=%d fib=%d htf=%d method=%d signals=%d",
               g_diag_bars_seen,g_diag_adx_reject,g_diag_buy_trend_true,
               g_diag_buy_pullback_true,g_diag_buy_sweep_true,g_diag_buy_fibo_true,
               g_diag_buy_htf_true,g_diag_buy_method_true,g_signals_buy);
   PrintFormat("KAT3_DIAG_SELL bars=%d adx_reject=%d trend=%d pullback=%d sweep=%d fib=%d htf=%d method=%d signals=%d",
               g_diag_bars_seen,g_diag_adx_reject,g_diag_sell_trend_true,
               g_diag_sell_pullback_true,g_diag_sell_sweep_true,g_diag_sell_fibo_true,
               g_diag_sell_htf_true,g_diag_sell_method_true,g_signals_sell);
  }

int OnInit()
  {
   // This research EA may only execute simulated orders in Strategy Tester.
   if(!MQLInfoInteger(MQL_TESTER))
      return INIT_FAILED;
   if(InpResearchContextGate!="" && InpResearchContextGate!="UP" &&
      InpResearchContextGate!="DOWN" && InpResearchContextGate!="MIXED")
      return INIT_PARAMETERS_INCORRECT;
   g_run_tag="verified_"+IntegerToString((long)TimeLocal())+"_"+IntegerToString((long)GetTickCount64());
   Print("KATARINA_RESEARCH_RUN_TAG=",g_run_tag);
   if(InpLookbackBars<5 || InpLot<=0.0 || InpFibMin<0.0 || InpFibMax<=InpFibMin || InpFibMax>1.0)
      return INIT_PARAMETERS_INCORRECT;
   if(InpEnableStructureFeatures &&
      (InpStructureSwingLeft<1 || InpStructureSwingRight<1 ||
       InpStructureLookback<20 || InpStructureToleranceATR<=0.0 ||
       InpVolRegimeATRPeriod<=InpATRPeriod ||
       InpContextFastEMA<2 || InpContextSlowEMA<=InpContextFastEMA ||
       InpContextRSIPeriod<2 || InpContextADXPeriod<2 || InpContextATRPeriod<2))
      return INIT_PARAMETERS_INCORRECT;

   g_ema_fast=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   g_ema_slow=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   g_rsi=iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE);
   g_atr=iATR(_Symbol,_Period,InpATRPeriod);
   g_adx=iADX(_Symbol,_Period,InpADXPeriod);
   if(InpEnableStructureFeatures)
     {
      g_atr_slow=iATR(_Symbol,_Period,InpVolRegimeATRPeriod);
      g_ctx_fast=iMA(_Symbol,InpContextTF,InpContextFastEMA,0,MODE_EMA,PRICE_CLOSE);
      g_ctx_slow=iMA(_Symbol,InpContextTF,InpContextSlowEMA,0,MODE_EMA,PRICE_CLOSE);
      g_ctx_rsi=iRSI(_Symbol,InpContextTF,InpContextRSIPeriod,PRICE_CLOSE);
      g_ctx_adx=iADX(_Symbol,InpContextTF,InpContextADXPeriod);
      g_ctx_atr=iATR(_Symbol,InpContextTF,InpContextATRPeriod);
     }
   if(InpUseHTFTrend || InpEnableFeatureJournal)
     {
      g_htf_fast=iMA(_Symbol,InpHTF,InpHTFFastEMA,0,MODE_EMA,PRICE_CLOSE);
      g_htf_slow=iMA(_Symbol,InpHTF,InpHTFSlowEMA,0,MODE_EMA,PRICE_CLOSE);
     }
   if(g_ema_fast==INVALID_HANDLE || g_ema_slow==INVALID_HANDLE ||
      g_rsi==INVALID_HANDLE || g_atr==INVALID_HANDLE || g_adx==INVALID_HANDLE ||
      (InpEnableStructureFeatures &&
       (g_atr_slow==INVALID_HANDLE ||
        g_ctx_fast==INVALID_HANDLE || g_ctx_slow==INVALID_HANDLE ||
        g_ctx_rsi==INVALID_HANDLE || g_ctx_adx==INVALID_HANDLE ||
        g_ctx_atr==INVALID_HANDLE)) ||
      ((InpUseHTFTrend || InpEnableFeatureJournal) &&
       (g_htf_fast==INVALID_HANDLE || g_htf_slow==INVALID_HANDLE)))
      return INIT_FAILED;

   if(InpBuyMethod==KRM_ZONE_SCALP || InpSellMethod==KRM_ZONE_SCALP)
     {
      if(PeriodSeconds(InpZoneTF)<=PeriodSeconds(InpZoneConfirmTF) ||
         PeriodSeconds(InpZoneConfirmTF)<=PeriodSeconds(_Period) ||
         InpZoneRiskCash<=0 || InpZoneMaxHoldMinutes<=0 ||
         InpZoneSessionBufferMinutes<0 || InpZoneSessionBufferMinutes>1440 ||
         InpZoneLifetimeBars<1 || InpZoneTriggerBars<1 || !ZoneSelfTest())
         return INIT_PARAMETERS_INCORRECT;
      WriteZoneSessions(g_run_tag);
      Print("KATARINA_ZONE_SELFTEST=PASS");
     }
   InitFeatureJournal();
   g_trade.SetAsyncMode(false);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(!MQLInfoInteger(MQL_TESTER)) return;
   if(g_zone_audit!=INVALID_HANDLE) FileClose(g_zone_audit);
   if(g_opportunity_handle!=INVALID_HANDLE) FileClose(g_opportunity_handle);
   RebuildStatsFromHistory();
   WriteSummary();
   if(g_ema_fast!=INVALID_HANDLE) IndicatorRelease(g_ema_fast);
   if(g_ema_slow!=INVALID_HANDLE) IndicatorRelease(g_ema_slow);
   if(g_rsi!=INVALID_HANDLE) IndicatorRelease(g_rsi);
   if(g_atr!=INVALID_HANDLE) IndicatorRelease(g_atr);
   if(g_adx!=INVALID_HANDLE) IndicatorRelease(g_adx);
   if(g_atr_slow!=INVALID_HANDLE) IndicatorRelease(g_atr_slow);
   if(g_ctx_fast!=INVALID_HANDLE) IndicatorRelease(g_ctx_fast);
   if(g_ctx_slow!=INVALID_HANDLE) IndicatorRelease(g_ctx_slow);
   if(g_ctx_rsi!=INVALID_HANDLE) IndicatorRelease(g_ctx_rsi);
   if(g_ctx_adx!=INVALID_HANDLE) IndicatorRelease(g_ctx_adx);
   if(g_ctx_atr!=INVALID_HANDLE) IndicatorRelease(g_ctx_atr);
   if(g_htf_fast!=INVALID_HANDLE) IndicatorRelease(g_htf_fast);
   if(g_htf_slow!=INVALID_HANDLE) IndicatorRelease(g_htf_slow);
  }

void OnTick()
  {
   if(g_open_side!=0 && g_initial_price_risk>0.0)
     {
      MqlTick current;
      if(SymbolInfoTick(_Symbol,current))
         TrackResearchExcursion(g_open_side>0?current.bid:current.ask);
     }
   if((InpBuyMethod==KRM_ZONE_SCALP || InpSellMethod==KRM_ZONE_SCALP) &&
      ExistingResearchPosition() &&
      TimeCurrent()-(datetime)PositionGetInteger(POSITION_TIME)>=InpZoneMaxHoldMinutes*60)
     {
      static datetime last_close_trace=0;
      const ulong ticket=(ulong)PositionGetInteger(POSITION_TICKET);
      const bool closed=g_trade.PositionClose(ticket);
      if(!closed && TimeCurrent()-last_close_trace>=60)
        {
         PrintFormat("KAT_ZONE_TIMECLOSE_FAIL ticket=%I64u retcode=%u detail=%s",
            ticket,g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
         last_close_trace=TimeCurrent();
        }
      return;
     }
   const datetime bar=iTime(_Symbol,_Period,0);
   if(bar<=0 || bar==g_last_bar)
      return;
   g_last_bar=bar;
   EvaluateClosedBar();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   const long magic=HistoryDealGetInteger(trans.deal,DEAL_MAGIC);
   if(magic!=InpMagic)
      return;
   const long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY)
      return;
   TrackResearchExcursion(HistoryDealGetDouble(trans.deal,DEAL_PRICE));
   g_exit_reason=HistoryDealGetInteger(trans.deal,DEAL_REASON);
   const ulong position_id=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   double net=0.0;
   if(!HistorySelectByPosition(position_id)) return;
   for(int d=0;d<HistoryDealsTotal();d++)
     {
      const ulong deal=HistoryDealGetTicket(d);
      net+=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_COMMISSION)+
           HistoryDealGetDouble(deal,DEAL_SWAP)+HistoryDealGetDouble(deal,DEAL_FEE);
     }
   HistoryDealSelect(trans.deal);
   const datetime exit_time=(datetime)HistoryDealGetInteger(trans.deal,DEAL_TIME);
   AppendFeatureJournal(net,exit_time);
   RecordClosedTrade(net);
  }

double OnTester()
  {
   const double pf=(g_gross_loss>0.0?g_gross_profit/g_gross_loss:(g_gross_profit>0.0?999.0:0.0));
   return pf;
  }

