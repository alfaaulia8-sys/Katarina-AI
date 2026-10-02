#ifndef __KATARINA_NATIVE_SNAPSHOT_MQH__
#define __KATARINA_NATIVE_SNAPSHOT_MQH__

#include <Katarina/NativeFacts.mqh>

struct SKatPositionFact
  {
   ulong                ticket;
   ulong                identifier;
   string               symbol;
   long                 magic;
   ENUM_POSITION_TYPE   type;
   ENUM_POSITION_REASON reason;
   long                 time_msc;
   long                 time_update_msc;
   double               volume;
   double               price_open;
   double               price_current;
   double               sl;
   double               tp;
   double               swap;
   double               profit;
  };

struct SKatOrderFact
  {
   ulong                  ticket;
   string                 symbol;
   long                   magic;
   ENUM_ORDER_TYPE        type;
   ENUM_ORDER_STATE       state;
   ENUM_ORDER_REASON      reason;
   ENUM_ORDER_TYPE_TIME   time_type;
   ENUM_ORDER_TYPE_FILLING filling_type;
   long                   time_setup_msc;
   long                   time_done_msc;
   datetime               expiration;
   double                 volume_initial;
   double                 volume_current;
   double                 price_open;
   double                 price_stoplimit;
   double                 sl;
   double                 tp;
   ulong                  position_id;
   ulong                  position_by_id;
  };

class CKatNativeSnapshot
  {
private:
   bool             m_complete;
   ulong            m_build_sequence;
   ulong            m_build_monotonic_ms;
   SKatAccountFacts m_account;
   SKatPositionFact m_positions[];
   SKatOrderFact    m_orders[];

public:
                     CKatNativeSnapshot(void)
     {
      Reset();
     }

   void              Reset(void)
     {
      m_complete=false;
      m_build_sequence=0;
      m_build_monotonic_ms=0;
      ArrayResize(m_positions,0);
      ArrayResize(m_orders,0);
     }

   bool              Build(const ulong build_sequence)
     {
      Reset();
      m_build_sequence=build_sequence;
      m_build_monotonic_ms=GetTickCount64();

      if(!KatReadAccountFacts(m_account))
         return(false);

      const int position_total=PositionsTotal();
      if(position_total<0)
         return(false);

      if(ArrayResize(m_positions,position_total)!=position_total)
         return(false);

      for(int i=0;i<position_total;i++)
        {
         const ulong ticket=PositionGetTicket(i);
         if(ticket==0)
           {
            Reset();
            return(false);
           }

         SKatPositionFact fact;
         fact.ticket=ticket;
         fact.identifier=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
         fact.symbol=PositionGetString(POSITION_SYMBOL);
         fact.magic=PositionGetInteger(POSITION_MAGIC);
         fact.type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         fact.reason=(ENUM_POSITION_REASON)PositionGetInteger(POSITION_REASON);
         fact.time_msc=PositionGetInteger(POSITION_TIME_MSC);
         fact.time_update_msc=PositionGetInteger(POSITION_TIME_UPDATE_MSC);
         fact.volume=PositionGetDouble(POSITION_VOLUME);
         fact.price_open=PositionGetDouble(POSITION_PRICE_OPEN);
         fact.price_current=PositionGetDouble(POSITION_PRICE_CURRENT);
         fact.sl=PositionGetDouble(POSITION_SL);
         fact.tp=PositionGetDouble(POSITION_TP);
         fact.swap=PositionGetDouble(POSITION_SWAP);
         fact.profit=PositionGetDouble(POSITION_PROFIT);

         if(fact.symbol=="" || fact.identifier==0)
           {
            Reset();
            return(false);
           }

         m_positions[i]=fact;
        }

      const int order_total=OrdersTotal();
      if(order_total<0)
        {
         Reset();
         return(false);
        }

      if(ArrayResize(m_orders,order_total)!=order_total)
        {
         Reset();
         return(false);
        }

      for(int i=0;i<order_total;i++)
        {
         const ulong ticket=OrderGetTicket(i);
         if(ticket==0)
           {
            Reset();
            return(false);
           }

         SKatOrderFact fact;
         fact.ticket=ticket;
         fact.symbol=OrderGetString(ORDER_SYMBOL);
         fact.magic=OrderGetInteger(ORDER_MAGIC);
         fact.type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         fact.state=(ENUM_ORDER_STATE)OrderGetInteger(ORDER_STATE);
         fact.reason=(ENUM_ORDER_REASON)OrderGetInteger(ORDER_REASON);
         fact.time_type=(ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME);
         fact.filling_type=(ENUM_ORDER_TYPE_FILLING)OrderGetInteger(ORDER_TYPE_FILLING);
         fact.time_setup_msc=OrderGetInteger(ORDER_TIME_SETUP_MSC);
         fact.time_done_msc=OrderGetInteger(ORDER_TIME_DONE_MSC);
         fact.expiration=(datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
         fact.volume_initial=OrderGetDouble(ORDER_VOLUME_INITIAL);
         fact.volume_current=OrderGetDouble(ORDER_VOLUME_CURRENT);
         fact.price_open=OrderGetDouble(ORDER_PRICE_OPEN);
         fact.price_stoplimit=OrderGetDouble(ORDER_PRICE_STOPLIMIT);
         fact.sl=OrderGetDouble(ORDER_SL);
         fact.tp=OrderGetDouble(ORDER_TP);
         fact.position_id=(ulong)OrderGetInteger(ORDER_POSITION_ID);
         fact.position_by_id=(ulong)OrderGetInteger(ORDER_POSITION_BY_ID);

         if(fact.symbol=="")
           {
            Reset();
            return(false);
           }

         m_orders[i]=fact;
        }

      // A total-count change proves this was not one coherent enumeration.
      // Same-count replacements are still caught later by transaction/reconciliation
      // semantics; Stage 06 does not pretend this local read is broker-atomic.
      if(PositionsTotal()!=position_total || OrdersTotal()!=order_total)
        {
         Reset();
         return(false);
        }

      m_complete=true;
      return(true);
     }

   bool              BuildStable(const ulong first_build_sequence,
                                 const int max_attempts=3)
     {
      const int attempts=(max_attempts<1 ? 1 : max_attempts);
      for(int i=0;i<attempts;i++)
        {
         if(Build(first_build_sequence+(ulong)i))
            return(true);
        }
      return(false);
     }

   bool              Complete(void) const
     {
      return(m_complete);
     }

   int               PositionCount(void) const
     {
      return(ArraySize(m_positions));
     }

   int               OrderCount(void) const
     {
      return(ArraySize(m_orders));
     }

   bool              PositionAt(const int index,SKatPositionFact &fact) const
     {
      if(index<0 || index>=ArraySize(m_positions))
         return(false);
      fact=m_positions[index];
      return(true);
     }

   bool              OrderAt(const int index,SKatOrderFact &fact) const
     {
      if(index<0 || index>=ArraySize(m_orders))
         return(false);
      fact=m_orders[index];
      return(true);
     }

   bool              Account(SKatAccountFacts &facts) const
     {
      if(!m_complete)
         return(false);
      facts=m_account;
      return(true);
     }

   ulong             BuildSequence(void) const
     {
      return(m_build_sequence);
     }

   ulong             BuildMonotonicMs(void) const
     {
      return(m_build_monotonic_ms);
     }
  };

#endif
