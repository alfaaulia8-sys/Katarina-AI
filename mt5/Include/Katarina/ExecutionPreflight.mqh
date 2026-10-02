#ifndef __KATARINA_EXECUTION_PREFLIGHT_MQH__
#define __KATARINA_EXECUTION_PREFLIGHT_MQH__

#include <Katarina/NativeFacts.mqh>

enum ENUM_KAT_SIDE
  {
   KAT_SIDE_BUY=1,
   KAT_SIDE_SELL=2
  };

enum ENUM_KAT_ENTRY_TYPE
  {
   KAT_ENTRY_MARKET=1,
   KAT_ENTRY_LIMIT=2,
   KAT_ENTRY_STOP=3
  };

enum ENUM_KAT_PREFLIGHT_REASON
  {
   KAT_PREFLIGHT_OK=0,
   KAT_PREFLIGHT_STAGE06_EXECUTION_DISABLED=1,
   KAT_PREFLIGHT_SYMBOL_NOT_APPROVED=2,
   KAT_PREFLIGHT_INVALID_VOLUME=3,
   KAT_PREFLIGHT_UNSUPPORTED_ORDER_TYPE=4,
   KAT_PREFLIGHT_NATIVE_SL_REQUIRED=5,
   KAT_PREFLIGHT_INVALID_SL_SIDE=6,
   KAT_PREFLIGHT_INVALID_SL_DISTANCE=7,
   KAT_PREFLIGHT_INVALID_ENTRY_PRICE=8,
   KAT_PREFLIGHT_INVALID_PENDING_RELATION=9,
   KAT_PREFLIGHT_SYMBOL_NOT_TRADABLE=10,
   KAT_PREFLIGHT_DIRECTION_NOT_ALLOWED=11,
   KAT_PREFLIGHT_INVALID_PENDING_DISTANCE=12,
   KAT_PREFLIGHT_TP_UNSUPPORTED=13,
   KAT_PREFLIGHT_INVALID_TP_SIDE=14,
   KAT_PREFLIGHT_INVALID_TP_DISTANCE=15
  };

struct SKatOpenPreflight
  {
   string              symbol;
   ENUM_KAT_SIDE       side;
   ENUM_KAT_ENTRY_TYPE entry_type;
   double              volume;
   double              requested_price;
   double              sl;
   double              tp;
  };

bool KatVolumeAligned(const double value,
                      const double minimum,
                      const double maximum,
                      const double step)
  {
   if(value<minimum || value>maximum || step<=0.0)
      return(false);

   const double steps=(value-minimum)/step;
   const double nearest=MathRound(steps);
   return(MathAbs(steps-nearest)<=1e-7);
  }

ENUM_KAT_PREFLIGHT_REASON KatValidateOpenPreflight(const SKatOpenPreflight &request,
                                                   const SKatSymbolFacts &spec,
                                                   const bool symbol_approved,
                                                   const double bid,
                                                   const double ask)
  {
   if(!symbol_approved)
      return(KAT_PREFLIGHT_SYMBOL_NOT_APPROVED);

   if(spec.trade_mode==SYMBOL_TRADE_MODE_DISABLED ||
      spec.trade_mode==SYMBOL_TRADE_MODE_CLOSEONLY)
      return(KAT_PREFLIGHT_SYMBOL_NOT_TRADABLE);

   if(request.side==KAT_SIDE_BUY &&
      spec.trade_mode==SYMBOL_TRADE_MODE_SHORTONLY)
      return(KAT_PREFLIGHT_DIRECTION_NOT_ALLOWED);

   if(request.side==KAT_SIDE_SELL &&
      spec.trade_mode==SYMBOL_TRADE_MODE_LONGONLY)
      return(KAT_PREFLIGHT_DIRECTION_NOT_ALLOWED);

   if(!KatVolumeAligned(request.volume,
                        spec.volume_min,
                        spec.volume_max,
                        spec.volume_step))
      return(KAT_PREFLIGHT_INVALID_VOLUME);

   long required_mode=0;
   if(request.entry_type==KAT_ENTRY_MARKET)
      required_mode=SYMBOL_ORDER_MARKET;
   else if(request.entry_type==KAT_ENTRY_LIMIT)
      required_mode=SYMBOL_ORDER_LIMIT;
   else if(request.entry_type==KAT_ENTRY_STOP)
      required_mode=SYMBOL_ORDER_STOP;
   else
      return(KAT_PREFLIGHT_UNSUPPORTED_ORDER_TYPE);

   if((spec.order_mode & required_mode)==0)
      return(KAT_PREFLIGHT_UNSUPPORTED_ORDER_TYPE);

   if((spec.order_mode & SYMBOL_ORDER_SL)==0 || request.sl<=0.0)
      return(KAT_PREFLIGHT_NATIVE_SL_REQUIRED);

   double entry_price=request.requested_price;
   if(request.entry_type==KAT_ENTRY_MARKET)
      entry_price=(request.side==KAT_SIDE_BUY ? ask : bid);

   if(entry_price<=0.0 || bid<=0.0 || ask<=0.0 || ask<bid)
      return(KAT_PREFLIGHT_INVALID_ENTRY_PRICE);

   const double min_distance=(double)spec.stops_level_points*spec.point;

   if(request.entry_type==KAT_ENTRY_LIMIT)
     {
      if(request.side==KAT_SIDE_BUY && request.requested_price>=ask)
         return(KAT_PREFLIGHT_INVALID_PENDING_RELATION);
      if(request.side==KAT_SIDE_SELL && request.requested_price<=bid)
         return(KAT_PREFLIGHT_INVALID_PENDING_RELATION);

      if(min_distance>0.0)
        {
         if(request.side==KAT_SIDE_BUY &&
            ask-request.requested_price<min_distance)
            return(KAT_PREFLIGHT_INVALID_PENDING_DISTANCE);
         if(request.side==KAT_SIDE_SELL &&
            request.requested_price-bid<min_distance)
            return(KAT_PREFLIGHT_INVALID_PENDING_DISTANCE);
        }
     }

   if(request.entry_type==KAT_ENTRY_STOP)
     {
      if(request.side==KAT_SIDE_BUY && request.requested_price<=ask)
         return(KAT_PREFLIGHT_INVALID_PENDING_RELATION);
      if(request.side==KAT_SIDE_SELL && request.requested_price>=bid)
         return(KAT_PREFLIGHT_INVALID_PENDING_RELATION);

      if(min_distance>0.0)
        {
         if(request.side==KAT_SIDE_BUY &&
            request.requested_price-ask<min_distance)
            return(KAT_PREFLIGHT_INVALID_PENDING_DISTANCE);
         if(request.side==KAT_SIDE_SELL &&
            bid-request.requested_price<min_distance)
            return(KAT_PREFLIGHT_INVALID_PENDING_DISTANCE);
        }
     }

   if(request.side==KAT_SIDE_BUY && request.sl>=entry_price)
      return(KAT_PREFLIGHT_INVALID_SL_SIDE);
   if(request.side==KAT_SIDE_SELL && request.sl<=entry_price)
      return(KAT_PREFLIGHT_INVALID_SL_SIDE);

   if(min_distance>0.0 && MathAbs(entry_price-request.sl)<min_distance)
      return(KAT_PREFLIGHT_INVALID_SL_DISTANCE);

   if(request.tp>0.0)
     {
      if((spec.order_mode & SYMBOL_ORDER_TP)==0)
         return(KAT_PREFLIGHT_TP_UNSUPPORTED);

      if(request.side==KAT_SIDE_BUY && request.tp<=entry_price)
         return(KAT_PREFLIGHT_INVALID_TP_SIDE);
      if(request.side==KAT_SIDE_SELL && request.tp>=entry_price)
         return(KAT_PREFLIGHT_INVALID_TP_SIDE);

      if(min_distance>0.0 && MathAbs(request.tp-entry_price)<min_distance)
         return(KAT_PREFLIGHT_INVALID_TP_DISTANCE);
     }

   // Stage 06 validates only the local shape/capability surface.
   // Broker OrderCheck, revision binding, durable idempotency and actual submission
   // remain disabled until their later stages are implemented.
   return(KAT_PREFLIGHT_STAGE06_EXECUTION_DISABLED);
  }

#endif
