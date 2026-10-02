#ifndef __KATARINA_DEAL_HISTORY_MQH__
#define __KATARINA_DEAL_HISTORY_MQH__

struct SKatDealFact
  {
   ulong            ticket;
   ulong            order_ticket;
   ulong            position_id;
   long             time_msc;
   ENUM_DEAL_TYPE   type;
   ENUM_DEAL_ENTRY  entry;
   ENUM_DEAL_REASON reason;
   long             magic;
   string           symbol;
   string           comment;
   double           volume;
   double           price;
   double           profit;
   double           commission;
   double           swap;
   double           fee;
  };

class CKatDealHistoryRange
  {
private:
   bool         m_complete;
   bool         m_overflow;
   datetime     m_from;
   datetime     m_to;
   SKatDealFact m_items[];

public:
                     CKatDealHistoryRange(void)
     {
      Reset();
     }

   void              Reset(void)
     {
      m_complete=false;
      m_overflow=false;
      m_from=0;
      m_to=0;
      ArrayResize(m_items,0);
     }

   bool              Build(const datetime from_time,
                           const datetime to_time,
                           const int max_deals)
     {
      Reset();

      if(from_time<0 || to_time<from_time || max_deals<=0)
         return(false);

      if(!HistorySelect(from_time,to_time))
         return(false);

      const int total=HistoryDealsTotal();
      if(total<0)
         return(false);

      if(total>max_deals)
        {
         m_overflow=true;
         return(false);
        }

      if(ArrayResize(m_items,total)!=total)
         return(false);

      for(int i=0;i<total;i++)
        {
         const ulong ticket=HistoryDealGetTicket(i);
         if(ticket==0)
           {
            Reset();
            return(false);
           }

         SKatDealFact fact;
         fact.ticket=ticket;
         fact.order_ticket=(ulong)HistoryDealGetInteger(ticket,DEAL_ORDER);
         fact.position_id=(ulong)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
         fact.time_msc=HistoryDealGetInteger(ticket,DEAL_TIME_MSC);
         fact.type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket,DEAL_TYPE);
         fact.entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY);
         fact.reason=(ENUM_DEAL_REASON)HistoryDealGetInteger(ticket,DEAL_REASON);
         fact.magic=HistoryDealGetInteger(ticket,DEAL_MAGIC);
         fact.symbol=HistoryDealGetString(ticket,DEAL_SYMBOL);
         fact.comment=HistoryDealGetString(ticket,DEAL_COMMENT);
         fact.volume=HistoryDealGetDouble(ticket,DEAL_VOLUME);
         fact.price=HistoryDealGetDouble(ticket,DEAL_PRICE);
         fact.profit=HistoryDealGetDouble(ticket,DEAL_PROFIT);
         fact.commission=HistoryDealGetDouble(ticket,DEAL_COMMISSION);
         fact.swap=HistoryDealGetDouble(ticket,DEAL_SWAP);
         fact.fee=HistoryDealGetDouble(ticket,DEAL_FEE);

         m_items[i]=fact;
        }

      m_from=from_time;
      m_to=to_time;
      m_complete=true;
      return(true);
     }

   bool              Complete(void) const
     {
      return(m_complete);
     }

   bool              Overflow(void) const
     {
      return(m_overflow);
     }

   int               Count(void) const
     {
      return(ArraySize(m_items));
     }

   bool              At(const int index,SKatDealFact &fact) const
     {
      if(index<0 || index>=ArraySize(m_items))
         return(false);
      fact=m_items[index];
      return(true);
     }

   datetime          From(void) const
     {
      return(m_from);
     }

   datetime          To(void) const
     {
      return(m_to);
     }
  };

#endif
