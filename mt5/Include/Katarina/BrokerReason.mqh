#ifndef __KATARINA_BROKER_REASON_MQH__
#define __KATARINA_BROKER_REASON_MQH__

struct SKatReasonEvidence
  {
   bool                 order_reason_valid;
   ENUM_ORDER_REASON    order_reason;
   bool                 deal_reason_valid;
   ENUM_DEAL_REASON     deal_reason;
   bool                 position_reason_valid;
   ENUM_POSITION_REASON position_reason;
  };

void KatResetReasonEvidence(SKatReasonEvidence &evidence)
  {
   evidence.order_reason_valid=false;
   evidence.order_reason=(ENUM_ORDER_REASON)0;
   evidence.deal_reason_valid=false;
   evidence.deal_reason=(ENUM_DEAL_REASON)0;
   evidence.position_reason_valid=false;
   evidence.position_reason=(ENUM_POSITION_REASON)0;
  }

bool KatReadOrderReason(const ulong ticket,
                        ENUM_ORDER_REASON &reason)
  {
   if(ticket==0)
      return(false);

   if(OrderSelect(ticket))
     {
      reason=(ENUM_ORDER_REASON)OrderGetInteger(ORDER_REASON);
      return(true);
     }

   if(HistoryOrderSelect(ticket))
     {
      reason=(ENUM_ORDER_REASON)HistoryOrderGetInteger(ticket,ORDER_REASON);
      return(true);
     }

   return(false);
  }

bool KatReadDealReason(const ulong ticket,
                       ENUM_DEAL_REASON &reason)
  {
   if(ticket==0)
      return(false);

   if(!HistoryDealSelect(ticket))
      return(false);

   reason=(ENUM_DEAL_REASON)HistoryDealGetInteger(ticket,DEAL_REASON);
   return(true);
  }

bool KatReadPositionReason(const ulong ticket,
                           ENUM_POSITION_REASON &reason)
  {
   if(ticket==0)
      return(false);

   if(!PositionSelectByTicket(ticket))
      return(false);

   reason=(ENUM_POSITION_REASON)PositionGetInteger(POSITION_REASON);
   return(true);
  }

void KatEnrichReasonEvidence(const ulong order_ticket,
                             const ulong deal_ticket,
                             const ulong position_ticket,
                             SKatReasonEvidence &evidence)
  {
   KatResetReasonEvidence(evidence);

   ENUM_ORDER_REASON order_reason;
   if(KatReadOrderReason(order_ticket,order_reason))
     {
      evidence.order_reason=order_reason;
      evidence.order_reason_valid=true;
     }

   ENUM_DEAL_REASON deal_reason;
   if(KatReadDealReason(deal_ticket,deal_reason))
     {
      evidence.deal_reason=deal_reason;
      evidence.deal_reason_valid=true;
     }

   ENUM_POSITION_REASON position_reason;
   if(KatReadPositionReason(position_ticket,position_reason))
     {
      evidence.position_reason=position_reason;
      evidence.position_reason_valid=true;
     }
  }

#endif
