#ifndef __KATARINA_EVENT_BUFFER_MQH__
#define __KATARINA_EVENT_BUFFER_MQH__

struct SKatCapturedTick
  {
   ulong    capture_sequence;
   string   symbol;
   datetime time_seconds;
   long     time_msc;
   double   bid;
   double   ask;
   double   last;
   ulong    volume;
   double   volume_real;
   uint     flags;
  };

struct SKatCapturedTrade
  {
   ulong                       capture_sequence;
   long                        capture_monotonic_ms;
   ENUM_TRADE_TRANSACTION_TYPE transaction_type;
   ulong                       deal;
   ulong                       order;
   ulong                       position;
   ulong                       position_by;
   string                      symbol;
   ENUM_ORDER_TYPE             order_type;
   ENUM_ORDER_STATE            order_state;
   ENUM_DEAL_TYPE              deal_type;
   ENUM_ORDER_TYPE_TIME        time_type;
   datetime                    time_expiration;
   double                      price;
   double                      price_trigger;
   double                      price_sl;
   double                      price_tp;
   double                      volume;

   bool                        request_result_valid;
   uint                        request_id;
   uint                        result_retcode;
   ulong                       result_order;
   ulong                       result_deal;
   double                      result_volume;
   double                      result_price;

   bool                        order_reason_valid;
   ENUM_ORDER_REASON           order_reason;
   bool                        deal_reason_valid;
   ENUM_DEAL_REASON            deal_reason;
   bool                        position_reason_valid;
   ENUM_POSITION_REASON        position_reason;
  };

void KatCaptureTick(const string symbol,
                    const MqlTick &tick,
                    const ulong capture_sequence,
                    SKatCapturedTick &out_event)
  {
   out_event.capture_sequence=capture_sequence;
   out_event.symbol=symbol;
   out_event.time_seconds=tick.time;
   out_event.time_msc=tick.time_msc;
   out_event.bid=tick.bid;
   out_event.ask=tick.ask;
   out_event.last=tick.last;
   out_event.volume=tick.volume;
   out_event.volume_real=tick.volume_real;
   out_event.flags=tick.flags;
  }

void KatCaptureTradeTransaction(const MqlTradeTransaction &trans,
                                const MqlTradeRequest &request,
                                const MqlTradeResult &result,
                                const ulong capture_sequence,
                                SKatCapturedTrade &out_event)
  {
   out_event.capture_sequence=capture_sequence;
   out_event.capture_monotonic_ms=(long)(GetMicrosecondCount()/1000);
   out_event.transaction_type=trans.type;
   out_event.deal=trans.deal;
   out_event.order=trans.order;
   out_event.position=trans.position;
   out_event.position_by=trans.position_by;
   out_event.symbol=trans.symbol;
   out_event.order_type=trans.order_type;
   out_event.order_state=trans.order_state;
   out_event.deal_type=trans.deal_type;
   out_event.time_type=trans.time_type;
   out_event.time_expiration=trans.time_expiration;
   out_event.price=trans.price;
   out_event.price_trigger=trans.price_trigger;
   out_event.price_sl=trans.price_sl;
   out_event.price_tp=trans.price_tp;
   out_event.volume=trans.volume;

   // MQL5 documents request/result as meaningful only for
   // TRADE_TRANSACTION_REQUEST. Never interpret them for other transaction types.
   out_event.request_result_valid=(trans.type==TRADE_TRANSACTION_REQUEST);
   out_event.request_id=0;
   out_event.result_retcode=0;
   out_event.result_order=0;
   out_event.result_deal=0;
   out_event.result_volume=0.0;
   out_event.result_price=0.0;

   if(out_event.request_result_valid)
     {
      out_event.request_id=result.request_id;
      out_event.result_retcode=result.retcode;
      out_event.result_order=result.order;
      out_event.result_deal=result.deal;
      out_event.result_volume=result.volume;
      out_event.result_price=result.price;
     }

   out_event.order_reason_valid=false;
   out_event.order_reason=(ENUM_ORDER_REASON)0;
   out_event.deal_reason_valid=false;
   out_event.deal_reason=(ENUM_DEAL_REASON)0;
   out_event.position_reason_valid=false;
   out_event.position_reason=(ENUM_POSITION_REASON)0;
  }

class CKatLatestTickSlot
  {
private:
   bool             m_has_value;
   SKatCapturedTick m_value;

public:
                     CKatLatestTickSlot(void)
     {
      m_has_value=false;
     }

   void              Capture(const SKatCapturedTick &value)
     {
      m_value=value;
      m_has_value=true;
     }

   bool              Peek(SKatCapturedTick &value) const
     {
      if(!m_has_value)
         return(false);
      value=m_value;
      return(true);
     }

   void              Clear(void)
     {
      m_has_value=false;
     }

   bool              HasValue(void) const
     {
      return(m_has_value);
     }
  };

class CKatTradeEventQueue
  {
private:
   SKatCapturedTrade m_items[];
   int               m_capacity;
   int               m_head;
   int               m_tail;
   int               m_count;

public:
                     CKatTradeEventQueue(void)
     {
      m_capacity=0;
      m_head=0;
      m_tail=0;
      m_count=0;
     }

   bool              Init(const int capacity)
     {
      if(capacity<=0)
         return(false);
      if(ArrayResize(m_items,capacity)!=capacity)
         return(false);
      m_capacity=capacity;
      m_head=0;
      m_tail=0;
      m_count=0;
      return(true);
     }

   bool              Push(const SKatCapturedTrade &value)
     {
      if(m_capacity<=0 || m_count>=m_capacity)
         return(false);
      m_items[m_tail]=value;
      m_tail++;
      if(m_tail>=m_capacity)
         m_tail=0;
      m_count++;
      return(true);
     }

   bool              Peek(SKatCapturedTrade &value) const
     {
      if(m_count<=0)
         return(false);
      value=m_items[m_head];
      return(true);
     }

   bool              Pop(SKatCapturedTrade &value)
     {
      if(m_count<=0)
         return(false);
      value=m_items[m_head];
      m_head++;
      if(m_head>=m_capacity)
         m_head=0;
      m_count--;
      return(true);
     }

   int               Count(void) const
     {
      return(m_count);
     }

   int               Capacity(void) const
     {
      return(m_capacity);
     }
  };

#endif
