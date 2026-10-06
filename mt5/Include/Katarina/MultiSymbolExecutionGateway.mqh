#ifndef __KATARINA_MULTI_SYMBOL_EXECUTION_GATEWAY_MQH__
#define __KATARINA_MULTI_SYMBOL_EXECUTION_GATEWAY_MQH__

#include <Katarina/MultiSymbolCatalog.mqh>
#include <Katarina/ExecutionPreflight.mqh>
#include <Katarina/Stage07/Kat1ExecutionIntents.mqh>

enum ENUM_KAT_MULTI_EXEC_REASON
  {
   KAT_MULTI_EXEC_OK=0,
   KAT_MULTI_EXEC_DECODE_FAILED=1,
   KAT_MULTI_EXEC_ACCOUNT_MISMATCH=2,
   KAT_MULTI_EXEC_ACCOUNT_REVISION_MISMATCH=3,
   KAT_MULTI_EXEC_EXPIRED=4,
   KAT_MULTI_EXEC_UNKNOWN_INSTRUMENT=5,
   KAT_MULTI_EXEC_SPEC_REVISION_MISMATCH=6,
   KAT_MULTI_EXEC_PREFLIGHT_FAILED=7,
   KAT_MULTI_EXEC_DISARMED=8,
   KAT_MULTI_EXEC_DUPLICATE_INTENT=9,
   KAT_MULTI_EXEC_ORDERCHECK_FAILED=10,
   KAT_MULTI_EXEC_SEND_FAILED=11
  };

struct SKatMultiExecutionResult
  {
   ENUM_KAT_MULTI_EXEC_REASON reason;
   string symbol;
   string intent_id;
   uint broker_retcode;
   uint request_id;
   ulong broker_order;
   ulong broker_deal;
  };

double KatScaleFromI64(const long value,const int scale)
  {
   double factor=1.0;
   for(int i=0;i<scale;i++)
      factor*=10.0;
   return((double)value/factor);
  }

bool KatId16Equal(const uchar &left[],const uchar &right[])
  {
   if(ArraySize(left)<16 || ArraySize(right)<16)
      return(false);
   for(int i=0;i<16;i++)
      if(left[i]!=right[i])
         return(false);
   return(true);
  }

ENUM_ORDER_TYPE_FILLING KatChooseFilling(const long modes)
  {
   if((modes & SYMBOL_FILLING_FOK)!=0)
      return(ORDER_FILLING_FOK);
   if((modes & SYMBOL_FILLING_IOC)!=0)
      return(ORDER_FILLING_IOC);
   return(ORDER_FILLING_RETURN);
  }

class CKatMultiSymbolExecutionGateway
  {
private:
   CKatMultiSymbolCatalog *m_catalog;
   string m_seen[];

   bool Seen(const string intent_id) const
     {
      for(int i=0;i<ArraySize(m_seen);i++)
         if(m_seen[i]==intent_id)
            return(true);
      return(false);
     }

   bool MarkSeen(const string intent_id)
     {
      if(Seen(intent_id))
         return(true);
      const int n=ArraySize(m_seen);
      if(ArrayResize(m_seen,n+1)!=n+1)
         return(false);
      m_seen[n]=intent_id;
      return(true);
     }

public:
   CKatMultiSymbolExecutionGateway(void)
     {
      m_catalog=NULL;
      ArrayResize(m_seen,0);
     }

   bool Bind(CKatMultiSymbolCatalog &catalog)
     {
      m_catalog=&catalog;
      return(catalog.Count()>0);
     }

   bool PrepareOpen(const uchar &frame[],
                    const uchar &expected_account_id[],
                    const ulong expected_account_revision,
                    const ulong now_ns,
                    SKat1OpenIntent &intent,
                    SKatMultiSymbolEntry &entry,
                    SKatOpenPreflight &preflight,
                    ENUM_KAT_MULTI_EXEC_REASON &reason,
                    string &error)
     {
      reason=KAT_MULTI_EXEC_OK;
      error="";
      if(m_catalog==NULL)
        {
         reason=KAT_MULTI_EXEC_UNKNOWN_INSTRUMENT;
         error="catalog not bound";
         return(false);
        }
      if(!Kat1DecodeOpenIntent(frame,intent,error))
        {
         reason=KAT_MULTI_EXEC_DECODE_FAILED;
         return(false);
        }
      if(!KatId16Equal(intent.account_id,expected_account_id))
        {
         reason=KAT_MULTI_EXEC_ACCOUNT_MISMATCH;
         error="account_id mismatch";
         return(false);
        }
      if(intent.approved_account_revision!=expected_account_revision)
        {
         reason=KAT_MULTI_EXEC_ACCOUNT_REVISION_MISMATCH;
         error="account revision mismatch";
         return(false);
        }
      if(intent.submit_expiry_ns==0 || now_ns>intent.submit_expiry_ns)
        {
         reason=KAT_MULTI_EXEC_EXPIRED;
         error="intent expired";
         return(false);
        }
      if(!m_catalog.ResolveInstrument(intent.instrument_id,entry))
        {
         reason=KAT_MULTI_EXEC_UNKNOWN_INSTRUMENT;
         error="instrument_id not mapped";
         return(false);
        }
      if(entry.spec_revision!=intent.spec_revision)
        {
         reason=KAT_MULTI_EXEC_SPEC_REVISION_MISMATCH;
         error="spec revision mismatch";
         return(false);
        }

      MqlTick tick;
      if(!SymbolIsSynchronized(entry.symbol) || !SymbolInfoTick(entry.symbol,tick))
        {
         reason=KAT_MULTI_EXEC_PREFLIGHT_FAILED;
         error="symbol tick unavailable";
         return(false);
        }

      preflight.symbol=entry.symbol;
      preflight.side=(intent.side==1 ? KAT_SIDE_BUY : KAT_SIDE_SELL);
      preflight.entry_type=KAT_ENTRY_MARKET;
      preflight.volume=KatScaleFromI64(intent.volume_units,entry.volume_scale);
      preflight.requested_price=0.0;
      preflight.sl=KatScaleFromI64(intent.sl_units,entry.price_scale);
      preflight.tp=(intent.tp_units==0 ? 0.0 : KatScaleFromI64(intent.tp_units,entry.price_scale));

      const ENUM_KAT_PREFLIGHT_REASON p=
         KatValidateOpenPreflight(preflight,entry.facts,true,tick.bid,tick.ask);
      // Stage-06's terminal return code means the deterministic shape checks passed
      // but the frozen Stage-06 gateway itself deliberately had no submit path.
      if(p!=KAT_PREFLIGHT_STAGE06_EXECUTION_DISABLED)
        {
         reason=KAT_MULTI_EXEC_PREFLIGHT_FAILED;
         error="deterministic preflight rejected";
         return(false);
        }
      return(true);
     }

   bool SubmitOpen(const uchar &frame[],
                   const uchar &expected_account_id[],
                   const ulong expected_account_revision,
                   const ulong now_ns,
                   const bool execution_armed,
                   SKatMultiExecutionResult &out)
     {
      out.reason=KAT_MULTI_EXEC_DECODE_FAILED;
      out.symbol="";
      out.intent_id="";
      out.broker_retcode=0;
      out.request_id=0;
      out.broker_order=0;
      out.broker_deal=0;

      SKat1OpenIntent intent;
      SKatMultiSymbolEntry entry;
      SKatOpenPreflight preflight;
      ENUM_KAT_MULTI_EXEC_REASON reason;
      string error="";
      if(!PrepareOpen(frame,expected_account_id,expected_account_revision,now_ns,
                      intent,entry,preflight,reason,error))
        {
         out.reason=reason;
         return(false);
        }

      out.symbol=entry.symbol;
      out.intent_id=Kat1Id128Hex(intent.execution_intent_id);
      if(Seen(out.intent_id))
        {
         out.reason=KAT_MULTI_EXEC_DUPLICATE_INTENT;
         return(false);
        }
      if(!execution_armed)
        {
         out.reason=KAT_MULTI_EXEC_DISARMED;
         return(false);
        }

      MqlTick tick;
      if(!SymbolInfoTick(entry.symbol,tick))
        {
         out.reason=KAT_MULTI_EXEC_PREFLIGHT_FAILED;
         return(false);
        }

      MqlTradeRequest request;
      MqlTradeResult result;
      MqlTradeCheckResult check;
      ZeroMemory(request);
      ZeroMemory(result);
      ZeroMemory(check);

      request.action=TRADE_ACTION_DEAL;
      request.magic=778899;
      request.symbol=entry.symbol;
      request.volume=preflight.volume;
      request.type=(preflight.side==KAT_SIDE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      request.price=(preflight.side==KAT_SIDE_BUY ? tick.ask : tick.bid);
      request.sl=preflight.sl;
      request.tp=preflight.tp;
      request.deviation=intent.max_deviation_points;
      request.type_filling=KatChooseFilling(entry.facts.filling_mode);
      request.type_time=ORDER_TIME_GTC;
      request.comment="KATARINA";

      if(!OrderCheck(request,check))
        {
         out.reason=KAT_MULTI_EXEC_ORDERCHECK_FAILED;
         out.broker_retcode=check.retcode;
         return(false);
        }

      if(!OrderSendAsync(request,result))
        {
         out.reason=KAT_MULTI_EXEC_SEND_FAILED;
         out.broker_retcode=result.retcode;
         out.request_id=result.request_id;
         return(false);
        }

      if(!MarkSeen(out.intent_id))
        {
         out.reason=KAT_MULTI_EXEC_SEND_FAILED;
         return(false);
        }

      out.reason=KAT_MULTI_EXEC_OK;
      out.broker_retcode=result.retcode;
      out.request_id=result.request_id;
      out.broker_order=result.order;
      out.broker_deal=result.deal;
      return(true);
     }
  };

#endif
