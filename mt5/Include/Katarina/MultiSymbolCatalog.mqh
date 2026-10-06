#ifndef __KATARINA_MULTI_SYMBOL_CATALOG_MQH__
#define __KATARINA_MULTI_SYMBOL_CATALOG_MQH__

#include <Katarina/NativeFacts.mqh>
#include <Katarina/SessionState.mqh>

struct SKatMultiSymbolEntry
  {
   string           symbol;
   uint             instrument_id;
   uint             spec_revision;
   uchar            price_scale;
   uchar            volume_scale;
   SKatSymbolFacts  facts;
   SKatSessionState session;
   long             last_tick_msc;
  };

uint KatFnv1a32(const string value)
  {
   uchar bytes[];
   const int copied=StringToCharArray(value,bytes,0,WHOLE_ARRAY,CP_UTF8);
   int size=ArraySize(bytes);
   if(copied>0 && size>0 && bytes[size-1]==0)
      size--;
   uint hash=2166136261;
   for(int i=0;i<size;i++)
     {
      hash^=(uint)bytes[i];
      hash*=16777619;
     }
   return(hash==0 ? 1 : hash);
  }

uint KatStableInstrumentId(const string symbol)
  {
   return(KatFnv1a32("KAT1/instrument/v1|"+symbol));
  }

uint KatMaterialFactsFingerprint(const SKatSymbolFacts &f)
  {
   string material=
      f.symbol+"|"+
      IntegerToString(f.digits)+"|"+
      IntegerToString((long)f.calc_mode)+"|"+
      IntegerToString((long)f.trade_mode)+"|"+
      IntegerToString(f.order_mode)+"|"+
      IntegerToString(f.filling_mode)+"|"+
      IntegerToString(f.expiration_mode)+"|"+
      IntegerToString(f.stops_level_points)+"|"+
      IntegerToString(f.freeze_level_points)+"|"+
      DoubleToString(f.point,12)+"|"+
      DoubleToString(f.tick_size,12)+"|"+
      DoubleToString(f.tick_value,12)+"|"+
      DoubleToString(f.tick_value_profit,12)+"|"+
      DoubleToString(f.tick_value_loss,12)+"|"+
      DoubleToString(f.contract_size,8)+"|"+
      DoubleToString(f.volume_min,8)+"|"+
      DoubleToString(f.volume_max,8)+"|"+
      DoubleToString(f.volume_step,8)+"|"+
      DoubleToString(f.volume_limit,8)+"|"+
      f.base_currency+"|"+f.profit_currency+"|"+f.margin_currency;
   return(KatFnv1a32(material));
  }

uint KatPersistentSpecRevision(const uint instrument_id,
                               const SKatSymbolFacts &facts)
  {
   const string key=StringFormat("%08X",instrument_id);
   const string rev_name="KAT_MS_REV_"+key;
   const string fp_name="KAT_MS_FP_"+key;
   const uint fingerprint=KatMaterialFactsFingerprint(facts);

   uint revision=1;
   if(GlobalVariableCheck(rev_name) && GlobalVariableCheck(fp_name))
     {
      const double raw_rev=GlobalVariableGet(rev_name);
      const double raw_fp=GlobalVariableGet(fp_name);
      if(raw_rev>=1.0 && raw_rev<=4294967295.0 &&
         raw_fp>=0.0 && raw_fp<=4294967295.0)
        {
         revision=(uint)raw_rev;
         if((uint)raw_fp!=fingerprint)
           {
            if(revision==0xFFFFFFFF)
               return(0);
            revision++;
           }
        }
     }
   if(!GlobalVariableSet(rev_name,(double)revision))
      return(0);
   if(!GlobalVariableSet(fp_name,(double)fingerprint))
      return(0);
   return(revision);
  }

int KatVolumeScaleFromStep(const double step)
  {
   if(!MathIsValidNumber(step) || step<=0.0)
      return(-1);
   double factor=1.0;
   for(int scale=0;scale<=8;scale++)
     {
      const double scaled=step*factor;
      if(MathAbs(scaled-MathRound(scaled))<=1e-8)
         return(scale);
      factor*=10.0;
     }
   return(-1);
  }

bool KatCloseDouble(const double left,const double right)
  {
   const double scale=MathMax(1.0,MathMax(MathAbs(left),MathAbs(right)));
   return(MathAbs(left-right)<=scale*1e-10);
  }

bool KatMaterialSymbolFactsEqual(const SKatSymbolFacts &a,
                                 const SKatSymbolFacts &b)
  {
   return(
      a.digits==b.digits &&
      a.calc_mode==b.calc_mode &&
      a.trade_mode==b.trade_mode &&
      a.order_mode==b.order_mode &&
      a.filling_mode==b.filling_mode &&
      a.expiration_mode==b.expiration_mode &&
      a.stops_level_points==b.stops_level_points &&
      a.freeze_level_points==b.freeze_level_points &&
      KatCloseDouble(a.point,b.point) &&
      KatCloseDouble(a.tick_size,b.tick_size) &&
      KatCloseDouble(a.tick_value,b.tick_value) &&
      KatCloseDouble(a.tick_value_profit,b.tick_value_profit) &&
      KatCloseDouble(a.tick_value_loss,b.tick_value_loss) &&
      KatCloseDouble(a.contract_size,b.contract_size) &&
      KatCloseDouble(a.volume_min,b.volume_min) &&
      KatCloseDouble(a.volume_max,b.volume_max) &&
      KatCloseDouble(a.volume_step,b.volume_step) &&
      KatCloseDouble(a.volume_limit,b.volume_limit) &&
      a.base_currency==b.base_currency &&
      a.profit_currency==b.profit_currency &&
      a.margin_currency==b.margin_currency
   );
  }

class CKatMultiSymbolCatalog
  {
private:
   SKatMultiSymbolEntry m_items[];

   int FindSymbol(const string symbol) const
     {
      for(int i=0;i<ArraySize(m_items);i++)
         if(m_items[i].symbol==symbol)
            return(i);
      return(-1);
     }

   int FindInstrument(const uint instrument_id) const
     {
      for(int i=0;i<ArraySize(m_items);i++)
         if(m_items[i].instrument_id==instrument_id)
            return(i);
      return(-1);
     }

public:
   void Reset(void)
     {
      ArrayResize(m_items,0);
     }

   int Count(void) const
     {
      return(ArraySize(m_items));
     }

   bool Add(const string symbol)
     {
      string s=symbol;
      StringTrimLeft(s);
      StringTrimRight(s);
      if(s=="")
         return(false);
      if(FindSymbol(s)>=0)
         return(true);
      if(!SymbolSelect(s,true))
         return(false);

      SKatSymbolFacts facts;
      if(!KatReadSymbolFacts(s,facts))
         return(false);

      const int volume_scale=KatVolumeScaleFromStep(facts.volume_step);
      if(volume_scale<0)
         return(false);

      const uint instrument_id=KatStableInstrumentId(s);
      const int collision=FindInstrument(instrument_id);
      if(collision>=0 && m_items[collision].symbol!=s)
         return(false);
      const uint spec_revision=KatPersistentSpecRevision(instrument_id,facts);
      if(spec_revision==0)
         return(false);

      SKatSessionState session;
      if(!KatReadSessionState(s,session))
        {
         session.scheduled_open=false;
         session.session_open=false;
         session.symbol_trade_allowed=false;
         session.server_time_seconds=(long)TimeTradeServer();
         session.last_tick_time_msc=0;
         session.session_count_today=0;
        }

      const int old_size=ArraySize(m_items);
      if(ArrayResize(m_items,old_size+1)!=old_size+1)
         return(false);

      m_items[old_size].symbol=s;
      m_items[old_size].instrument_id=instrument_id;
      m_items[old_size].spec_revision=spec_revision;
      m_items[old_size].price_scale=(uchar)facts.digits;
      m_items[old_size].volume_scale=(uchar)volume_scale;
      m_items[old_size].facts=facts;
      m_items[old_size].session=session;
      m_items[old_size].last_tick_msc=0;
      return(true);
     }

   bool AddCsv(const string csv,const int max_symbols=64)
     {
      if(csv=="")
         return(true);
      string parts[];
      const ushort sep=(ushort)StringGetCharacter(",",0);
      const int total=StringSplit(csv,sep,parts);
      if(total<0)
         return(false);
      for(int i=0;i<total && Count()<max_symbols;i++)
        {
         string item=parts[i];
         StringTrimLeft(item);
         StringTrimRight(item);
         if(item!="" && !Add(item))
            return(false);
        }
      return(true);
     }

   bool AddMarketWatch(const int max_symbols=64)
     {
      const int total=SymbolsTotal(true);
      if(total<=0)
         return(false);
      for(int i=0;i<total && Count()<max_symbols;i++)
        {
         const string symbol=SymbolName(i,true);
         if(symbol=="" || !Add(symbol))
            continue;
        }
      return(Count()>0);
     }

   bool EntryAt(const int index,SKatMultiSymbolEntry &entry) const
     {
      if(index<0 || index>=ArraySize(m_items))
         return(false);
      entry=m_items[index];
      return(true);
     }

   bool ResolveInstrument(const uint instrument_id,SKatMultiSymbolEntry &entry) const
     {
      if(instrument_id==0)
         return(false);
      const int index=FindInstrument(instrument_id);
      if(index<0)
         return(false);
      entry=m_items[index];
      return(true);
     }

   bool ResolveSymbol(const string symbol,SKatMultiSymbolEntry &entry) const
     {
      const int index=FindSymbol(symbol);
      if(index<0)
         return(false);
      entry=m_items[index];
      return(true);
     }

   bool Refresh(const int index,bool &spec_changed,bool &session_changed)
     {
      spec_changed=false;
      session_changed=false;
      if(index<0 || index>=ArraySize(m_items))
         return(false);

      const string symbol=m_items[index].symbol;
      SKatSymbolFacts latest;
      if(!KatReadSymbolFacts(symbol,latest))
         return(false);
      if(!KatMaterialSymbolFactsEqual(m_items[index].facts,latest))
        {
         const uint revision=KatPersistentSpecRevision(m_items[index].instrument_id,latest);
         if(revision==0 || revision<m_items[index].spec_revision)
            return(false);
         m_items[index].spec_revision=revision;
         m_items[index].facts=latest;
         m_items[index].price_scale=(uchar)latest.digits;
         const int volume_scale=KatVolumeScaleFromStep(latest.volume_step);
         if(volume_scale<0)
            return(false);
         m_items[index].volume_scale=(uchar)volume_scale;
         spec_changed=true;
        }

      SKatSessionState session;
      if(!KatReadSessionState(symbol,session))
         return(false);
      session_changed=(
         session.session_open!=m_items[index].session.session_open ||
         session.symbol_trade_allowed!=m_items[index].session.symbol_trade_allowed ||
         session.last_tick_time_msc!=m_items[index].session.last_tick_time_msc
      );
      m_items[index].session=session;
      return(true);
     }

   bool PollTick(const int index,
                 MqlTick &tick,
                 bool &changed,
                 SKatMultiSymbolEntry &entry)
     {
      changed=false;
      if(index<0 || index>=ArraySize(m_items))
         return(false);
      const string symbol=m_items[index].symbol;
      if(!SymbolIsSynchronized(symbol))
         return(false);
      if(!SymbolInfoTick(symbol,tick))
         return(false);
      if(tick.time_msc<=0)
         return(false);

      if(tick.time_msc>m_items[index].last_tick_msc)
        {
         m_items[index].last_tick_msc=tick.time_msc;
         changed=true;
        }
      entry=m_items[index];
      return(true);
     }
  };

#endif
