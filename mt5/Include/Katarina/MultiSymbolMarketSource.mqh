#ifndef __KATARINA_MULTI_SYMBOL_MARKET_SOURCE_MQH__
#define __KATARINA_MULTI_SYMBOL_MARKET_SOURCE_MQH__

#include <Katarina/MultiSymbolCatalog.mqh>

struct SKatMultiSymbolTick
  {
   string symbol;
   uint   instrument_id;
   uint   spec_revision;
   MqlTick tick;
  };

class CKatMultiSymbolMarketSource
  {
private:
   CKatMultiSymbolCatalog *m_catalog;
   int m_cursor;

public:
   CKatMultiSymbolMarketSource(void)
     {
      m_catalog=NULL;
      m_cursor=0;
     }

   bool Bind(CKatMultiSymbolCatalog &catalog)
     {
      m_catalog=&catalog;
      m_cursor=0;
      return(catalog.Count()>0);
     }

   bool PollNext(SKatMultiSymbolTick &out_tick)
     {
      if(m_catalog==NULL)
         return(false);
      const int total=m_catalog.Count();
      if(total<=0)
         return(false);

      for(int attempts=0;attempts<total;attempts++)
        {
         const int index=m_cursor;
         m_cursor++;
         if(m_cursor>=total)
            m_cursor=0;

         MqlTick tick;
         bool changed=false;
         SKatMultiSymbolEntry entry;
         if(!m_catalog.PollTick(index,tick,changed,entry))
            continue;
         if(!changed)
            continue;

         out_tick.symbol=entry.symbol;
         out_tick.instrument_id=entry.instrument_id;
         out_tick.spec_revision=entry.spec_revision;
         out_tick.tick=tick;
         return(true);
        }
      return(false);
     }
  };

#endif
