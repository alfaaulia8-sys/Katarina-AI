#ifndef __KATARINA_STAGE07_KAT1_NATIVE_RECORDS_MQH__
#define __KATARINA_STAGE07_KAT1_NATIVE_RECORDS_MQH__

#include <Katarina/NativeFacts.mqh>
#include <Katarina/NativeSnapshot.mqh>
#include <Katarina/Stage07/Kat1RecoveryMessages.mqh>
#include <Katarina/Stage07/IdentityV1.mqh>

#define KAT1_SNAPSHOT_RECORD_SYMBOL_SPEC    1
#define KAT1_SNAPSHOT_RECORD_SESSION_STATE  2
#define KAT1_SNAPSHOT_RECORD_ACCOUNT_STATE  3
#define KAT1_SNAPSHOT_RECORD_POSITION_STATE 4
#define KAT1_SNAPSHOT_RECORD_ORDER_STATE    5

long Kat1Pow10Long(const int scale)
  {
   if(scale<0 || scale>8)
      return(0);
   long result=1;
   for(int i=0;i<scale;i++)
      result*=10;
   return(result);
  }

bool Kat1ScaleToI64(const double value,
                    const int scale,
                    long &units)
  {
   const long factor=Kat1Pow10Long(scale);
   if(factor<=0 || !MathIsValidNumber(value))
      return(false);

   const double scaled=value*(double)factor;
   if(!MathIsValidNumber(scaled))
      return(false);

   units=(long)MathRound(scaled);
   return(true);
  }

uchar Kat1NormalizeAccountMode(const ENUM_ACCOUNT_MARGIN_MODE mode)
  {
   if(mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      return(1);
   if(mode==ACCOUNT_MARGIN_MODE_RETAIL_NETTING)
      return(2);
   if(mode==ACCOUNT_MARGIN_MODE_EXCHANGE)
      return(3);
   return(0);
  }

uchar Kat1NormalizeAccountTradeMode(const ENUM_ACCOUNT_TRADE_MODE mode)
  {
   if(mode==ACCOUNT_TRADE_MODE_DEMO)
      return(1);
   if(mode==ACCOUNT_TRADE_MODE_CONTEST)
      return(2);
   if(mode==ACCOUNT_TRADE_MODE_REAL)
      return(3);
   return(0);
  }

uint Kat1AccountFlags(const SKatAccountFacts &facts)
  {
   uint flags=0;
   if(facts.trade_allowed)
      flags|=0x00000001;
   if(facts.expert_trade_allowed)
      flags|=0x00000002;
   if(facts.hedge_allowed)
      flags|=0x00000004;
   if(facts.fifo_close)
      flags|=0x00000008;
   return(flags);
  }

// ACCOUNT_STATE snapshot record uses the frozen ACCOUNT_DELTA v1 body layout
// without a nested KAT1 frame header.
bool Kat1BuildAccountStateRecordBody(const SKatAccountFacts &facts,
                                     const ulong account_revision,
                                     const uint account_unit_profile_revision,
                                     uchar &body[],
                                     string &error)
  {
   error="";
   if(facts.login==0 ||
      facts.server=="" ||
      facts.currency=="" ||
      facts.currency_digits<0 ||
      facts.currency_digits>8 ||
      account_revision==0 ||
      account_unit_profile_revision==0)
     {
      error="invalid account record inputs";
      return(false);
     }

   uchar account_id[];
   if(!Kat1BuildAccountId(facts.server,
                          facts.login,
                          account_id,
                          error))
      return(false);

   long balance=0;
   long equity=0;
   long credit=0;
   long profit=0;
   long margin=0;
   long free_margin=0;
   long margin_initial=0;
   long margin_maintenance=0;

   if(!Kat1ScaleToI64(facts.balance,facts.currency_digits,balance) ||
      !Kat1ScaleToI64(facts.equity,facts.currency_digits,equity) ||
      !Kat1ScaleToI64(facts.credit,facts.currency_digits,credit) ||
      !Kat1ScaleToI64(facts.profit,facts.currency_digits,profit) ||
      !Kat1ScaleToI64(facts.margin,facts.currency_digits,margin) ||
      !Kat1ScaleToI64(facts.free_margin,facts.currency_digits,free_margin) ||
      !Kat1ScaleToI64(facts.margin_initial,facts.currency_digits,margin_initial) ||
      !Kat1ScaleToI64(facts.margin_maintenance,facts.currency_digits,margin_maintenance))
     {
      error="account money scaling failed";
      return(false);
     }

   long margin_level_e6=0;
   long margin_call_e6=0;
   long stopout_e6=0;
   if(!Kat1ScaleToI64(facts.margin_level,6,margin_level_e6) ||
      !Kat1ScaleToI64(facts.margin_call,6,margin_call_e6) ||
      !Kat1ScaleToI64(facts.stopout_level,6,stopout_e6))
     {
      error="account ratio scaling failed";
      return(false);
     }

   ArrayResize(body,144);
   ArrayInitialize(body,0);

   if(!Kat1WriteId128(body,0,account_id))
     {
      error="account_id write failed";
      return(false);
     }

   Kat1WriteU64LE(body,16,account_revision);

   // The Stage-06 native account snapshot reads every ACCOUNT_DELTA v1 fact.
   // Golden Stage-04 complete-account fixtures use 0xFFFF.
   Kat1WriteU64LE(body,24,0x000000000000FFFF);

   Kat1WriteU64LE(body,32,(ulong)balance);
   Kat1WriteU64LE(body,40,(ulong)equity);
   Kat1WriteU64LE(body,48,(ulong)credit);
   Kat1WriteU64LE(body,56,(ulong)profit);
   Kat1WriteU64LE(body,64,(ulong)margin);
   Kat1WriteU64LE(body,72,(ulong)free_margin);
   Kat1WriteU64LE(body,80,(ulong)margin_initial);
   Kat1WriteU64LE(body,88,(ulong)margin_maintenance);

   Kat1WriteU64LE(body,96,(ulong)facts.leverage);
   Kat1WriteU64LE(body,104,(ulong)margin_level_e6);
   Kat1WriteU64LE(body,112,(ulong)margin_call_e6);
   Kat1WriteU64LE(body,120,(ulong)stopout_e6);

   body[128]=Kat1NormalizeAccountMode(facts.margin_mode);
   body[129]=Kat1NormalizeAccountTradeMode(facts.trade_mode);
   body[130]=(uchar)facts.stopout_mode;
   body[131]=(uchar)facts.currency_digits;
   Kat1WriteU32LE(body,132,Kat1AccountFlags(facts));
   Kat1WriteU32LE(body,136,account_unit_profile_revision);

   return(true);
  }

bool Kat1AppendAccountStateRecord(const SKatAccountFacts &facts,
                                  const ulong account_revision,
                                  const uint account_unit_profile_revision,
                                  uchar &records[],
                                  string &error)
  {
   uchar body[];
   if(!Kat1BuildAccountStateRecordBody(facts,
                                       account_revision,
                                       account_unit_profile_revision,
                                       body,
                                       error))
      return(false);

   return(Kat1AppendEmbeddedRecord(records,
                                   KAT1_SNAPSHOT_RECORD_ACCOUNT_STATE,
                                   1,
                                   body,
                                   error));
  }

#endif
