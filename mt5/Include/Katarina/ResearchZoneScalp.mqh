// Research-only causal first-touch zones. No live execution authority.
#ifndef KATARINA_RESEARCH_ZONE_SCALP
#define KATARINA_RESEARCH_ZONE_SCALP
input ENUM_TIMEFRAMES InpZoneTF=PERIOD_H1;
input ENUM_TIMEFRAMES InpZoneConfirmTF=PERIOD_M15;
input bool InpZoneUseConfirmation=true;
input double InpZoneRiskCash=10.0;
input int InpZoneMaxHoldMinutes=45;
input int InpZoneSessionBufferMinutes=60;
input int InpZoneLifetimeBars=48;
input int InpZoneTriggerBars=3;

struct ResearchZone
  {
   int side;
   double low,high;
   datetime base_time,known_time,touch_time;
   bool active;
  };
ResearchZone g_demand,g_supply;
datetime g_zone_last=0;
double g_zone_buy_sl=0.0,g_zone_sell_sl=0.0;
int g_zone_audit=INVALID_HANDLE;

// rates are series; departure=1, base=2; scale excludes both.
bool ZoneDeparture(const MqlRates &z[],const int side,double &low,double &high)
  {
   if(ArraySize(z)<19) return false;
   double tr=0.0;
   for(int i=3;i<=16;i++)
      tr+=MathMax(z[i].high-z[i].low,
          MathMax(MathAbs(z[i].high-z[i+1].close),MathAbs(z[i].low-z[i+1].close)));
   tr/=14.0;
   if(tr<=0 || z[2].high-z[2].low>tr ||
      MathAbs(z[2].close-z[2].open)>0.5*tr ||
      side*(z[1].close-z[1].open)<tr) return false;
   double hi=z[2].high,lo=z[2].low;
   for(int i=3;i<=6;i++) { hi=MathMax(hi,z[i].high); lo=MathMin(lo,z[i].low); }
   if(side>0)
     {
      low=z[2].low; high=MathMax(z[2].open,z[2].close);
      return high>low && z[1].close>hi && z[1].close>high+0.5*tr;
     }
   low=MathMin(z[2].open,z[2].close); high=z[2].high;
   return high>low && z[1].close<lo && z[1].close<low-0.5*tr;
  }

datetime g_zone_session_end=0;
bool ZoneSessionRoom(const int start_sec,const int end_sec,const int offset,const int required)
  {
   int finish=end_sec;
   if(finish<=start_sec) finish+=86400;
   return offset>=start_sec && offset<finish && finish-offset>=required;
  }

bool ZoneTradingSessionAllows()
  {
   g_zone_session_end=0;
   const datetime now=TimeCurrent();
   MqlDateTime dt; if(!TimeToStruct(now,dt)) return false;
   const int tod=dt.hour*3600+dt.min*60+dt.sec;
   const datetime midnight=now-tod;
   for(int lag=0;lag<=1;lag++)
     {
      const ENUM_DAY_OF_WEEK day=(ENUM_DAY_OF_WEEK)((dt.day_of_week-lag+7)%7);
      for(uint i=0;i<32;i++)
        {
         datetime from,to;
         if(!SymbolInfoSessionTrade(_Symbol,day,i,from,to)) break;
         const int a=(int)((long)from%86400),b=(int)((long)to%86400);
         if(ZoneSessionRoom(a,b,tod+lag*86400,(InpZoneMaxHoldMinutes+InpZoneSessionBufferMinutes)*60))
           {
            g_zone_session_end=midnight-lag*86400+b+(b<=a?86400:0);
            return true;
           }
        }
     }
   return false;
  }

void WriteZoneSessions(const string run_tag)
  {
   int h=FileOpen("KatarinaZoneSessions_"+run_tag+".csv",FILE_WRITE|FILE_CSV|FILE_COMMON,';');
   if(h==INVALID_HANDLE) return;
   FileWrite(h,"day_of_week","session_index","start_second","end_second");
   for(int day=0;day<7;day++)
      for(uint i=0;i<32;i++)
        {
         datetime from,to;
         if(!SymbolInfoSessionTrade(_Symbol,(ENUM_DAY_OF_WEEK)day,i,from,to)) break;
         FileWrite(h,day,i,(long)from%86400,(long)to%86400);
        }
   FileClose(h);
  }

void UpdateResearchZones()
  {
   const datetime current=iTime(_Symbol,InpZoneTF,0);
   if(current<=0 || current==g_zone_last) return;
   MqlRates z[]; ArraySetAsSeries(z,true);
   if(CopyRates(_Symbol,InpZoneTF,0,19,z)!=19) return;
   if(z[1].time+PeriodSeconds(InpZoneTF)>TimeCurrent()) return;
   g_zone_last=current;
   double lo,hi;
   if(ZoneDeparture(z,1,lo,hi))
     {
      g_demand.side=1; g_demand.low=lo; g_demand.high=hi;
      g_demand.base_time=z[2].time; g_demand.known_time=current;
      g_demand.touch_time=0; g_demand.active=true;
     }
   if(ZoneDeparture(z,-1,lo,hi))
     {
      g_supply.side=-1; g_supply.low=lo; g_supply.high=hi;
      g_supply.base_time=z[2].time; g_supply.known_time=current;
      g_supply.touch_time=0; g_supply.active=true;
     }
  }

// Advance even while occupied: a missed first touch is not fresh again later.
bool ZoneWindow(ResearchZone &zone,const MqlRates &b,const int entry_seconds,
                const int zone_seconds,const int life_bars,const int trigger_bars)
  {
   if(!zone.active || b.time<zone.known_time) return false;
   if(b.time-zone.known_time>=life_bars*zone_seconds ||
      (zone.side>0 && b.close<zone.low) || (zone.side<0 && b.close>zone.high))
     { zone.active=false; return false; }
   if(zone.touch_time==0 && b.low<=zone.high && b.high>=zone.low)
      zone.touch_time=b.time;
   if(zone.touch_time==0) return false;
   if(b.time-zone.touch_time>=trigger_bars*entry_seconds)
     { zone.active=false; return false; }
   return true;
  }

bool ZoneConfirmation(const int side,datetime &known)
  {
   known=0;
   if(!InpZoneUseConfirmation) return true;
   MqlRates c[]; ArraySetAsSeries(c,true);
   if(CopyRates(_Symbol,InpZoneConfirmTF,0,3,c)!=3) return false;
   known=c[1].time+PeriodSeconds(InpZoneConfirmTF);
   if(known>TimeCurrent()) return false;
   if(side>0) return c[1].low>c[2].low && c[1].close>c[2].close && c[1].close>c[1].open;
   return c[1].high<c[2].high && c[1].close<c[2].close && c[1].close<c[1].open;
  }

bool ZoneSignal(ResearchZone &zone,const MqlRates &b,const double atr,double &stop)
  {
   stop=0;
   if(!ZoneWindow(zone,b,PeriodSeconds(_Period),PeriodSeconds(InpZoneTF),
                  InpZoneLifetimeBars,InpZoneTriggerBars)) return false;
   const bool candle=(zone.side>0?
      b.close>b.open && b.close>zone.high && b.close-b.low>=0.6*(b.high-b.low):
      b.close<b.open && b.close<zone.low && b.high-b.close>=0.6*(b.high-b.low));
   datetime confirmation_known;
   if(!candle || !ZoneConfirmation(zone.side,confirmation_known)) return false;
   stop=(zone.side>0?zone.low-0.2*atr:zone.high+0.2*atr);
   // One qualifying opportunity per zone, whether executed or missed while occupied.
   zone.active=false;
   return true;
  }

void AuditZoneFill(const string run_tag,const ResearchZone &zone,const datetime signal_time,
                   const double entry,const double sl,const double volume,const double cash_risk)
  {
   if(g_zone_audit==INVALID_HANDLE)
     {
      g_zone_audit=FileOpen("KatarinaZoneAudit_"+run_tag+".csv",FILE_WRITE|FILE_CSV|FILE_COMMON,';');
      if(g_zone_audit==INVALID_HANDLE) return;
      FileWrite(g_zone_audit,"run_tag","side","zone_tf","confirm_tf","entry_tf","base_time",
         "zone_known","first_touch","signal_time","entry_time","confirmation_known","confirmation_used",
         "zone_low","zone_high","entry","sl","volume","cash_risk","risk_budget","max_hold_minutes","seconds_to_session_close","session_buffer_minutes");
     }
   datetime ck; ZoneConfirmation(zone.side,ck);
   FileWrite(g_zone_audit,run_tag,zone.side,EnumToString(InpZoneTF),EnumToString(InpZoneConfirmTF),
      EnumToString(_Period),(long)zone.base_time,(long)zone.known_time,(long)zone.touch_time,
      (long)signal_time,(long)TimeCurrent(),(long)ck,InpZoneUseConfirmation,
      zone.low,zone.high,entry,sl,volume,cash_risk,InpZoneRiskCash,InpZoneMaxHoldMinutes,(long)(g_zone_session_end-TimeCurrent()),InpZoneSessionBufferMinutes);
  }

bool ZoneSelfTest()
  {
   if(!ZoneSessionRoom(3600,82800,80000,1800) ||
      ZoneSessionRoom(3600,82800,82000,1800) ||
      !ZoneSessionRoom(82800,3600,87000,1800) ||
      ZoneSessionRoom(3600,82800,0,1800)) return false;
   MqlRates z[]; ArrayResize(z,19); ZeroMemory(z);
   for(int i=0;i<19;i++)
     { z[i].open=100; z[i].close=100; z[i].high=101; z[i].low=99; }
   z[2].open=100; z[2].close=100.2; z[2].high=100.5; z[2].low=99.5;
   z[1].open=100; z[1].close=103; z[1].high=103; z[1].low=100;
   double lo,hi;
   if(!ZoneDeparture(z,1,lo,hi) || lo!=99.5 || hi!=100.2 || ZoneDeparture(z,-1,lo,hi)) return false;
   z[1].close=97; z[1].low=97; z[1].high=100;
   if(!ZoneDeparture(z,-1,lo,hi)) return false;
   z[1].close=100.1;
   if(ZoneDeparture(z,1,lo,hi)) return false;
   ResearchZone q; ZeroMemory(q);
   q.side=1; q.low=99; q.high=100; q.known_time=1000; q.active=true;
   MqlRates b; ZeroMemory(b); b.time=940; b.low=99.5; b.high=101; b.close=100.5;
   if(ZoneWindow(q,b,60,3600,48,3) || q.touch_time!=0) return false;
   b.time=1000;
   if(!ZoneWindow(q,b,60,3600,48,3) || q.touch_time!=1000) return false;
   b.time=1180;
   if(ZoneWindow(q,b,60,3600,48,3) || q.active) return false;
   q.active=true; q.touch_time=0; b.time=1060; b.close=98;
   if(ZoneWindow(q,b,60,3600,48,3) || q.active) return false;
   return true;
  }
#endif
