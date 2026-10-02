#ifndef __KATARINA_EVENT_BUFFER_MQH__
#define __KATARINA_EVENT_BUFFER_MQH__

enum ENUM_KAT_TRANSACTION_FIELD_FLAG
  {
   KAT_TRANS_HAS_ORDER          =1,
   KAT_TRANS_HAS_DEAL           =2,
   KAT_TRANS_HAS_POSITION       =4,
   KAT_TRANS_HAS_POSITION_BY    =8,
   KAT_TRANS_HAS_SYMBOL         =16,
   KAT_TRANS_HAS_ORDER_TYPE     =32,
   KAT_TRANS_HAS_ORDER_STATE    =64,
   KAT_TRANS_HAS_DEAL_TYPE      =128,
   KAT_TRANS_HAS_TIME_TYPE      =256,
   KAT_TRANS_HAS_EXPIRATION     =512,
   KAT_TRANS_HAS_PRICE          =1024,
   KAT_TRANS_HAS_PRICE_TRIGGER  =2048,
   KAT_TRANS_HAS_SL             =4096,
   KAT_TRANS_HAS_TP             =8192,
   KAT_TRANS_HAS_VOLUME         =16384
  };

struct SKatCapturedTick
  {
   ulong    local_capture_id;
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
   ulong                       local_capture_id;
   long                        capture_monotonic_ms;
   ENUM_TRADE_TRANSACTION_TYPE transaction_type;
   uint                        transaction_field_flags;
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
   ENUM_TRADE_REQUEST_ACTIONS  request_action;
   ulong                       request_magic;
   ulong                       request_order;
   string                      request_symbol;
   double                      request_volume;
   double                      request_price;
   double                      request_stoplimit;
   double                      request_sl;
   double                      request_tp;
   ulong                       request_deviation;
   ENUM_ORDER_TYPE             request_type;
   ENUM_ORDER_TYPE_FILLING     request_type_filling;
   ENUM_ORDER_TYPE_TIME        request_type_time;
   datetime                    request_expiration;
   ulong                       request_position;
   ulong                       request_position_by;
   string                      request_comment;

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
                    const ulong local_capture_id,
                    SKatCapturedTick &out_event)
  {
   out_event.local_capture_id=local_capture_id;
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
                                const ulong local_capture_id,
                                SKatCapturedTrade &out_event)
  {
   out_event.local_capture_id=local_capture_id;
   out_event.capture_monotonic_ms=(long)(GetMicrosecondCount()/1000);
   out_event.transaction_type=trans.type;
   out_event.transaction_field_flags=0;

   // MqlTradeTransaction fields are type-dependent. Start from a fully neutral
   // record and copy only fields documented for the received transaction type.
   out_event.deal=0;
   out_event.order=0;
   out_event.position=0;
   out_event.position_by=0;
   out_event.symbol="";
   out_event.order_type=(ENUM_ORDER_TYPE)0;
   out_event.order_state=(ENUM_ORDER_STATE)0;
   out_event.deal_type=(ENUM_DEAL_TYPE)0;
   out_event.time_type=(ENUM_ORDER_TYPE_TIME)0;
   out_event.time_expiration=0;
   out_event.price=0.0;
   out_event.price_trigger=0.0;
   out_event.price_sl=0.0;
   out_event.price_tp=0.0;
   out_event.volume=0.0;

   const bool order_transaction=
      (trans.type==TRADE_TRANSACTION_ORDER_ADD ||
       trans.type==TRADE_TRANSACTION_ORDER_UPDATE ||
       trans.type==TRADE_TRANSACTION_ORDER_DELETE ||
       trans.type==TRADE_TRANSACTION_HISTORY_ADD ||
       trans.type==TRADE_TRANSACTION_HISTORY_UPDATE ||
       trans.type==TRADE_TRANSACTION_HISTORY_DELETE);

   const bool deal_transaction=
      (trans.type==TRADE_TRANSACTION_DEAL_ADD ||
       trans.type==TRADE_TRANSACTION_DEAL_UPDATE ||
       trans.type==TRADE_TRANSACTION_DEAL_DELETE);

   if(order_transaction)
     {
      out_event.order=trans.order;
      out_event.symbol=trans.symbol;
      out_event.order_type=trans.order_type;
      out_event.order_state=trans.order_state;
      out_event.time_type=trans.time_type;
      out_event.time_expiration=trans.time_expiration;
      out_event.price=trans.price;
      out_event.price_trigger=trans.price_trigger;
      out_event.price_sl=trans.price_sl;
      out_event.price_tp=trans.price_tp;
      out_event.volume=trans.volume;
      out_event.position=trans.position;
      out_event.position_by=trans.position_by;

      out_event.transaction_field_flags=
         KAT_TRANS_HAS_ORDER |
         KAT_TRANS_HAS_SYMBOL |
         KAT_TRANS_HAS_ORDER_TYPE |
         KAT_TRANS_HAS_ORDER_STATE |
         KAT_TRANS_HAS_TIME_TYPE |
         KAT_TRANS_HAS_EXPIRATION |
         KAT_TRANS_HAS_PRICE |
         KAT_TRANS_HAS_PRICE_TRIGGER |
         KAT_TRANS_HAS_SL |
         KAT_TRANS_HAS_TP |
         KAT_TRANS_HAS_VOLUME |
         KAT_TRANS_HAS_POSITION |
         KAT_TRANS_HAS_POSITION_BY;
     }
   else if(deal_transaction)
     {
      out_event.deal=trans.deal;
      out_event.order=trans.order;
      out_event.symbol=trans.symbol;
      out_event.deal_type=trans.deal_type;
      out_event.price=trans.price;
      out_event.price_sl=trans.price_sl;
      out_event.price_tp=trans.price_tp;
      out_event.volume=trans.volume;
      out_event.position=trans.position;
      out_event.position_by=trans.position_by;

      out_event.transaction_field_flags=
         KAT_TRANS_HAS_DEAL |
         KAT_TRANS_HAS_ORDER |
         KAT_TRANS_HAS_SYMBOL |
         KAT_TRANS_HAS_DEAL_TYPE |
         KAT_TRANS_HAS_PRICE |
         KAT_TRANS_HAS_SL |
         KAT_TRANS_HAS_TP |
         KAT_TRANS_HAS_VOLUME |
         KAT_TRANS_HAS_POSITION |
         KAT_TRANS_HAS_POSITION_BY;
     }
   else if(trans.type==TRADE_TRANSACTION_POSITION)
     {
      out_event.symbol=trans.symbol;
      out_event.deal_type=trans.deal_type;
      out_event.price=trans.price;
      out_event.price_sl=trans.price_sl;
      out_event.price_tp=trans.price_tp;
      out_event.volume=trans.volume;

      out_event.transaction_field_flags=
         KAT_TRANS_HAS_SYMBOL |
         KAT_TRANS_HAS_DEAL_TYPE |
         KAT_TRANS_HAS_PRICE |
         KAT_TRANS_HAS_SL |
         KAT_TRANS_HAS_TP |
         KAT_TRANS_HAS_VOLUME;
     }

   // MQL5 documents request/result as meaningful only for
   // TRADE_TRANSACTION_REQUEST. Never interpret them for other transaction types.
   out_event.request_result_valid=(trans.type==TRADE_TRANSACTION_REQUEST);
   out_event.request_action=(ENUM_TRADE_REQUEST_ACTIONS)0;
   out_event.request_magic=0;
   out_event.request_order=0;
   out_event.request_symbol="";
   out_event.request_volume=0.0;
   out_event.request_price=0.0;
   out_event.request_stoplimit=0.0;
   out_event.request_sl=0.0;
   out_event.request_tp=0.0;
   out_event.request_deviation=0;
   out_event.request_type=(ENUM_ORDER_TYPE)0;
   out_event.request_type_filling=(ENUM_ORDER_TYPE_FILLING)0;
   out_event.request_type_time=(ENUM_ORDER_TYPE_TIME)0;
   out_event.request_expiration=0;
   out_event.request_position=0;
   out_event.request_position_by=0;
   out_event.request_comment="";

   out_event.request_id=0;
   out_event.result_retcode=0;
   out_event.result_order=0;
   out_event.result_deal=0;
   out_event.result_volume=0.0;
   out_event.result_price=0.0;

   if(out_event.request_result_valid)
     {
      out_event.request_action=request.action;
      out_event.request_magic=request.magic;
      out_event.request_order=request.order;
      out_event.request_symbol=request.symbol;
      out_event.request_volume=request.volume;
      out_event.request_price=request.price;
      out_event.request_stoplimit=request.stoplimit;
      out_event.request_sl=request.sl;
      out_event.request_tp=request.tp;
      out_event.request_deviation=request.deviation;
      out_event.request_type=request.type;
      out_event.request_type_filling=request.type_filling;
      out_event.request_type_time=request.type_time;
      out_event.request_expiration=request.expiration;
      out_event.request_position=request.position;
      out_event.request_position_by=request.position_by;
      out_event.request_comment=request.comment;

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
