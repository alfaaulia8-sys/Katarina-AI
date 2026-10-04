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


bool Kat1BuildSymbolSpecRecordBody(const SKatSymbolFacts &facts,
                                   const uint instrument_id,
                                   const uint spec_revision,
                                   const uchar price_scale,
                                   const uchar volume_scale,
                                   const uchar money_scale,
                                   const string canonical_symbol,
                                   const uint symbol_flags,
                                   uchar &body[],
                                   string &error)
  {
   error="";
   if(instrument_id==0 ||
      spec_revision==0 ||
      facts.symbol=="" ||
      canonical_symbol=="" ||
      price_scale>8 ||
      volume_scale>8 ||
      money_scale>8 ||
      facts.digits<0 ||
      facts.digits>8)
     {
      error="invalid SYMBOL_SPEC record inputs";
      return(false);
     }

   long point_units=0;
   long tick_size_units=0;
   long tick_value_units=0;
   long tick_value_profit_units=0;
   long tick_value_loss_units=0;
   long contract_size_e8=0;
   long volume_min_units=0;
   long volume_max_units=0;
   long volume_step_units=0;
   long volume_limit_units=0;
   long margin_initial_units=0;
   long margin_maintenance_units=0;
   long swap_long_e8=0;
   long swap_short_e8=0;
   long swap_sunday_e4=0;
   long swap_monday_e4=0;
   long swap_tuesday_e4=0;
   long swap_wednesday_e4=0;
   long swap_thursday_e4=0;
   long swap_friday_e4=0;
   long swap_saturday_e4=0;

   if(!Kat1ScaleToI64(facts.point,price_scale,point_units) ||
      !Kat1ScaleToI64(facts.tick_size,price_scale,tick_size_units) ||
      !Kat1ScaleToI64(facts.tick_value,money_scale,tick_value_units) ||
      !Kat1ScaleToI64(facts.tick_value_profit,money_scale,tick_value_profit_units) ||
      !Kat1ScaleToI64(facts.tick_value_loss,money_scale,tick_value_loss_units) ||
      !Kat1ScaleToI64(facts.contract_size,8,contract_size_e8) ||
      !Kat1ScaleToI64(facts.volume_min,volume_scale,volume_min_units) ||
      !Kat1ScaleToI64(facts.volume_max,volume_scale,volume_max_units) ||
      !Kat1ScaleToI64(facts.volume_step,volume_scale,volume_step_units) ||
      !Kat1ScaleToI64(facts.volume_limit,volume_scale,volume_limit_units) ||
      !Kat1ScaleToI64(facts.margin_initial,money_scale,margin_initial_units) ||
      !Kat1ScaleToI64(facts.margin_maintenance,money_scale,margin_maintenance_units) ||
      !Kat1ScaleToI64(facts.swap_long,8,swap_long_e8) ||
      !Kat1ScaleToI64(facts.swap_short,8,swap_short_e8) ||
      !Kat1ScaleToI64(facts.swap_sunday,4,swap_sunday_e4) ||
      !Kat1ScaleToI64(facts.swap_monday,4,swap_monday_e4) ||
      !Kat1ScaleToI64(facts.swap_tuesday,4,swap_tuesday_e4) ||
      !Kat1ScaleToI64(facts.swap_wednesday,4,swap_wednesday_e4) ||
      !Kat1ScaleToI64(facts.swap_thursday,4,swap_thursday_e4) ||
      !Kat1ScaleToI64(facts.swap_friday,4,swap_friday_e4) ||
      !Kat1ScaleToI64(facts.swap_saturday,4,swap_saturday_e4))
     {
      error="SYMBOL_SPEC scaling failed";
      return(false);
     }

   ArrayResize(body,184);
   ArrayInitialize(body,0);

   Kat1WriteU32LE(body,0,instrument_id);
   Kat1WriteU32LE(body,4,spec_revision);
   body[8]=(uchar)facts.digits;
   body[9]=price_scale;
   body[10]=volume_scale;
   Kat1WriteU16LE(body,12,(ushort)facts.calc_mode);
   body[14]=(uchar)facts.trade_mode;
   body[15]=(uchar)facts.swap_mode;
   Kat1WriteU32LE(body,16,(uint)facts.order_mode);
   Kat1WriteU32LE(body,20,(uint)facts.filling_mode);
   Kat1WriteU32LE(body,24,(uint)facts.expiration_mode);
   Kat1WriteU32LE(body,28,(uint)facts.stops_level_points);
   Kat1WriteU32LE(body,32,(uint)facts.freeze_level_points);

   Kat1WriteU64LE(body,40,(ulong)point_units);
   Kat1WriteU64LE(body,48,(ulong)tick_size_units);
   Kat1WriteU64LE(body,56,(ulong)tick_value_units);
   Kat1WriteU64LE(body,64,(ulong)tick_value_profit_units);
   Kat1WriteU64LE(body,72,(ulong)tick_value_loss_units);
   Kat1WriteU64LE(body,80,(ulong)contract_size_e8);
   Kat1WriteU64LE(body,88,(ulong)volume_min_units);
   Kat1WriteU64LE(body,96,(ulong)volume_max_units);
   Kat1WriteU64LE(body,104,(ulong)volume_step_units);
   Kat1WriteU64LE(body,112,(ulong)volume_limit_units);
   Kat1WriteU64LE(body,120,(ulong)margin_initial_units);
   Kat1WriteU64LE(body,128,(ulong)margin_maintenance_units);
   Kat1WriteU64LE(body,136,(ulong)swap_long_e8);
   Kat1WriteU64LE(body,144,(ulong)swap_short_e8);
   Kat1WriteU32LE(body,152,(uint)swap_sunday_e4);
   Kat1WriteU32LE(body,156,(uint)swap_monday_e4);
   Kat1WriteU32LE(body,160,(uint)swap_tuesday_e4);
   Kat1WriteU32LE(body,164,(uint)swap_wednesday_e4);
   Kat1WriteU32LE(body,168,(uint)swap_thursday_e4);
   Kat1WriteU32LE(body,172,(uint)swap_friday_e4);
   Kat1WriteU32LE(body,176,(uint)swap_saturday_e4);
   Kat1WriteU32LE(body,180,symbol_flags);

   if(!Kat1AppendU16Utf8(body,canonical_symbol,32,error) ||
      !Kat1AppendU16Utf8(body,facts.symbol,64,error) ||
      !Kat1AppendU16Utf8(body,facts.base_currency,16,error) ||
      !Kat1AppendU16Utf8(body,facts.profit_currency,16,error) ||
      !Kat1AppendU16Utf8(body,facts.margin_currency,16,error))
      return(false);

   return(true);
  }

bool Kat1AppendSymbolSpecRecord(const SKatSymbolFacts &facts,
                                const uint instrument_id,
                                const uint spec_revision,
                                const uchar price_scale,
                                const uchar volume_scale,
                                const uchar money_scale,
                                const string canonical_symbol,
                                const uint symbol_flags,
                                uchar &records[],
                                string &error)
  {
   uchar body[];
   if(!Kat1BuildSymbolSpecRecordBody(facts,
                                     instrument_id,
                                     spec_revision,
                                     price_scale,
                                     volume_scale,
                                     money_scale,
                                     canonical_symbol,
                                     symbol_flags,
                                     body,
                                     error))
      return(false);

   return(Kat1AppendEmbeddedRecord(records,
                                   KAT1_SNAPSHOT_RECORD_SYMBOL_SPEC,
                                   1,
                                   body,
                                   error));
  }

bool Kat1BuildSessionStateRecordBody(const uint instrument_id,
                                     const uint spec_revision,
                                     const ulong state_revision,
                                     const SKatSessionState &session,
                                     const bool terminal_connected,
                                     const bool terminal_trade_allowed,
                                     const bool mql_trade_allowed,
                                     const bool fresh_tick,
                                     const uint terminal_ping_us,
                                     uchar &body[],
                                     string &error)
  {
   error="";
   if(instrument_id==0 || spec_revision==0 || state_revision==0)
     {
      error="invalid SESSION_STATE record inputs";
      return(false);
     }

   ArrayResize(body,48);
   ArrayInitialize(body,0);
   Kat1WriteU32LE(body,0,instrument_id);
   Kat1WriteU32LE(body,4,spec_revision);
   Kat1WriteU64LE(body,8,state_revision);

   const ulong last_tick_ns=(session.last_tick_time_msc>0 ?
                             (ulong)session.last_tick_time_msc*1000000 : 0);
   const ulong server_time_ns=(session.server_time_seconds>0 ?
                               (ulong)session.server_time_seconds*1000000000 : 0);
   Kat1WriteU64LE(body,16,last_tick_ns);
   Kat1WriteU64LE(body,24,server_time_ns);

   body[32]=(session.scheduled_open ? 1 : 0);
   body[33]=(terminal_connected ? 1 : 0);
   body[34]=(terminal_trade_allowed ? 1 : 0);
   body[35]=(mql_trade_allowed ? 1 : 0);
   body[36]=(session.symbol_trade_allowed ? 1 : 0);
   body[37]=(fresh_tick ? 1 : 0);
   body[38]=(session.session_open ? 1 : 0);
   Kat1WriteU32LE(body,40,terminal_ping_us);

   return(true);
  }

bool Kat1AppendSessionStateRecord(const uint instrument_id,
                                  const uint spec_revision,
                                  const ulong state_revision,
                                  const SKatSessionState &session,
                                  const bool terminal_connected,
                                  const bool terminal_trade_allowed,
                                  const bool mql_trade_allowed,
                                  const bool fresh_tick,
                                  const uint terminal_ping_us,
                                  uchar &records[],
                                  string &error)
  {
   uchar body[];
   if(!Kat1BuildSessionStateRecordBody(instrument_id,
                                       spec_revision,
                                       state_revision,
                                       session,
                                       terminal_connected,
                                       terminal_trade_allowed,
                                       mql_trade_allowed,
                                       fresh_tick,
                                       terminal_ping_us,
                                       body,
                                       error))
      return(false);

   return(Kat1AppendEmbeddedRecord(records,
                                   KAT1_SNAPSHOT_RECORD_SESSION_STATE,
                                   1,
                                   body,
                                   error));
  }

uchar Kat1PositionSide(const ENUM_POSITION_TYPE type)
  {
   if(type==POSITION_TYPE_BUY)
      return(1);
   if(type==POSITION_TYPE_SELL)
      return(2);
   return(0);
  }

bool Kat1BuildPositionStateRecordBody(const SKatPositionFact &fact,
                                      const uchar &account_id[],
                                      const uint instrument_id,
                                      const uint spec_revision,
                                      const ulong position_revision,
                                      const uchar price_scale,
                                      const uchar volume_scale,
                                      const uchar money_scale,
                                      const uchar origin_class,
                                      const uint presence_flags,
                                      uchar &body[],
                                      string &error)
  {
   error="";
   if(ArraySize(account_id)!=16 ||
      fact.ticket==0 ||
      fact.identifier==0 ||
      fact.symbol=="" ||
      instrument_id==0 ||
      spec_revision==0 ||
      position_revision==0 ||
      price_scale>8 ||
      volume_scale>8 ||
      money_scale>8 ||
      fact.magic<0)
     {
      error="invalid POSITION_STATE record inputs";
      return(false);
     }

   long volume_units=0;
   long open_price_units=0;
   long current_price_units=0;
   long sl_units=0;
   long tp_units=0;
   long profit_units=0;
   long swap_units=0;

   if(!Kat1ScaleToI64(fact.volume,volume_scale,volume_units) ||
      !Kat1ScaleToI64(fact.price_open,price_scale,open_price_units) ||
      !Kat1ScaleToI64(fact.price_current,price_scale,current_price_units) ||
      !Kat1ScaleToI64(fact.sl,price_scale,sl_units) ||
      !Kat1ScaleToI64(fact.tp,price_scale,tp_units) ||
      !Kat1ScaleToI64(fact.profit,money_scale,profit_units) ||
      !Kat1ScaleToI64(fact.swap,money_scale,swap_units))
     {
      error="POSITION_STATE scaling failed";
      return(false);
     }

   ArrayResize(body,144);
   ArrayInitialize(body,0);
   Kat1WriteId128(body,0,account_id);
   Kat1WriteU64LE(body,16,fact.ticket);
   Kat1WriteU64LE(body,24,fact.identifier);
   Kat1WriteU32LE(body,32,instrument_id);
   Kat1WriteU32LE(body,36,spec_revision);
   Kat1WriteU64LE(body,40,(ulong)fact.magic);
   Kat1WriteU64LE(body,48,position_revision);
   Kat1WriteU64LE(body,56,(fact.time_msc>0 ? (ulong)fact.time_msc*1000000 : 0));
   Kat1WriteU64LE(body,64,(fact.time_update_msc>0 ? (ulong)fact.time_update_msc*1000000 : 0));
   Kat1WriteU64LE(body,72,(ulong)volume_units);
   Kat1WriteU64LE(body,80,(ulong)open_price_units);
   Kat1WriteU64LE(body,88,(ulong)current_price_units);
   Kat1WriteU64LE(body,96,(ulong)sl_units);
   Kat1WriteU64LE(body,104,(ulong)tp_units);
   Kat1WriteU64LE(body,112,(ulong)profit_units);
   Kat1WriteU64LE(body,120,(ulong)swap_units);
   body[128]=1; // UPSERT snapshot record
   body[129]=Kat1PositionSide(fact.type);
   body[130]=origin_class;
   body[131]=(uchar)fact.reason;
   Kat1WriteU32LE(body,132,presence_flags);
   Kat1WriteU32LE(body,136,(uint)fact.type);

   if(body[129]==0)
     {
      error="unsupported position side";
      return(false);
     }

   return(true);
  }

bool Kat1AppendPositionStateRecord(const SKatPositionFact &fact,
                                   const uchar &account_id[],
                                   const uint instrument_id,
                                   const uint spec_revision,
                                   const ulong position_revision,
                                   const uchar price_scale,
                                   const uchar volume_scale,
                                   const uchar money_scale,
                                   const uchar origin_class,
                                   const uint presence_flags,
                                   uchar &records[],
                                   string &error)
  {
   uchar body[];
   if(!Kat1BuildPositionStateRecordBody(fact,
                                        account_id,
                                        instrument_id,
                                        spec_revision,
                                        position_revision,
                                        price_scale,
                                        volume_scale,
                                        money_scale,
                                        origin_class,
                                        presence_flags,
                                        body,
                                        error))
      return(false);

   return(Kat1AppendEmbeddedRecord(records,
                                   KAT1_SNAPSHOT_RECORD_POSITION_STATE,
                                   1,
                                   body,
                                   error));
  }

uchar Kat1OrderSide(const ENUM_ORDER_TYPE type)
  {
   if(type==ORDER_TYPE_BUY ||
      type==ORDER_TYPE_BUY_LIMIT ||
      type==ORDER_TYPE_BUY_STOP ||
      type==ORDER_TYPE_BUY_STOP_LIMIT)
      return(1);

   if(type==ORDER_TYPE_SELL ||
      type==ORDER_TYPE_SELL_LIMIT ||
      type==ORDER_TYPE_SELL_STOP ||
      type==ORDER_TYPE_SELL_STOP_LIMIT)
      return(2);

   return(0);
  }

uchar Kat1OrderEntryType(const ENUM_ORDER_TYPE type)
  {
   if(type==ORDER_TYPE_BUY || type==ORDER_TYPE_SELL)
      return(1);
   if(type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_SELL_LIMIT)
      return(2);
   if(type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_SELL_STOP)
      return(3);
   if(type==ORDER_TYPE_BUY_STOP_LIMIT || type==ORDER_TYPE_SELL_STOP_LIMIT)
      return(4); // reserved/observable, never production-authorized in V1
   return(0);
  }

uchar Kat1OrderStateNormalized(const ENUM_ORDER_STATE state)
  {
   if(state==ORDER_STATE_STARTED)
      return(1);
   if(state==ORDER_STATE_PLACED)
      return(2);
   if(state==ORDER_STATE_PARTIAL)
      return(3);
   if(state==ORDER_STATE_FILLED)
      return(4);
   if(state==ORDER_STATE_CANCELED)
      return(5);
   if(state==ORDER_STATE_REJECTED)
      return(6);
   if(state==ORDER_STATE_EXPIRED)
      return(7);
   if(state==ORDER_STATE_REQUEST_ADD)
      return(8);
   if(state==ORDER_STATE_REQUEST_MODIFY)
      return(9);
   if(state==ORDER_STATE_REQUEST_CANCEL)
      return(10);
   return(0);
  }

uchar Kat1OrderTimeInForce(const ENUM_ORDER_TYPE_TIME value)
  {
   if(value==ORDER_TIME_GTC)
      return(0);
   if(value==ORDER_TIME_DAY)
      return(1);
   if(value==ORDER_TIME_SPECIFIED)
      return(2);
   if(value==ORDER_TIME_SPECIFIED_DAY)
      return(3);
   return(0);
  }

uchar Kat1OrderFillingPolicy(const ENUM_ORDER_TYPE_FILLING value)
  {
   if(value==ORDER_FILLING_FOK)
      return(1);
   if(value==ORDER_FILLING_IOC)
      return(2);
   if(value==ORDER_FILLING_RETURN)
      return(3);
   if(value==ORDER_FILLING_BOC)
      return(4);
   return(0);
  }

bool Kat1BuildOrderStateRecordBody(const SKatOrderFact &fact,
                                   const uchar &account_id[],
                                   const uchar &linked_order_id[],
                                   const uint instrument_id,
                                   const uint spec_revision,
                                   const ulong order_revision,
                                   const uchar price_scale,
                                   const uchar volume_scale,
                                   const uchar origin_class,
                                   const uint presence_flags,
                                   uchar &body[],
                                   string &error)
  {
   error="";
   if(ArraySize(account_id)!=16 ||
      ArraySize(linked_order_id)!=16 ||
      fact.ticket==0 ||
      fact.symbol=="" ||
      instrument_id==0 ||
      spec_revision==0 ||
      order_revision==0 ||
      price_scale>8 ||
      volume_scale>8 ||
      fact.magic<0)
     {
      error="invalid ORDER_STATE record inputs";
      return(false);
     }

   long volume_initial_units=0;
   long volume_current_units=0;
   long price_open_units=0;
   long stop_limit_units=0;
   long sl_units=0;
   long tp_units=0;

   if(!Kat1ScaleToI64(fact.volume_initial,volume_scale,volume_initial_units) ||
      !Kat1ScaleToI64(fact.volume_current,volume_scale,volume_current_units) ||
      !Kat1ScaleToI64(fact.price_open,price_scale,price_open_units) ||
      !Kat1ScaleToI64(fact.price_stoplimit,price_scale,stop_limit_units) ||
      !Kat1ScaleToI64(fact.sl,price_scale,sl_units) ||
      !Kat1ScaleToI64(fact.tp,price_scale,tp_units))
     {
      error="ORDER_STATE scaling failed";
      return(false);
     }

   const uchar side=Kat1OrderSide(fact.type);
   const uchar entry_type=Kat1OrderEntryType(fact.type);
   const uchar normalized_state=Kat1OrderStateNormalized(fact.state);
   if(side==0 || entry_type==0 || normalized_state==0)
     {
      error="unsupported order enum normalization";
      return(false);
     }

   ArrayResize(body,160);
   ArrayInitialize(body,0);
   Kat1WriteId128(body,0,account_id);
   Kat1WriteU64LE(body,16,fact.ticket);
   Kat1WriteId128(body,24,linked_order_id);
   Kat1WriteU32LE(body,40,instrument_id);
   Kat1WriteU32LE(body,44,spec_revision);
   Kat1WriteU64LE(body,48,(ulong)fact.magic);
   Kat1WriteU64LE(body,56,order_revision);
   Kat1WriteU64LE(body,64,(fact.time_setup_msc>0 ? (ulong)fact.time_setup_msc*1000000 : 0));
   Kat1WriteU64LE(body,72,(fact.time_done_msc>0 ? (ulong)fact.time_done_msc*1000000 : 0));
   Kat1WriteU64LE(body,80,(ulong)volume_initial_units);
   Kat1WriteU64LE(body,88,(ulong)volume_current_units);
   Kat1WriteU64LE(body,96,(ulong)price_open_units);
   Kat1WriteU64LE(body,104,(ulong)stop_limit_units);
   Kat1WriteU64LE(body,112,(ulong)sl_units);
   Kat1WriteU64LE(body,120,(ulong)tp_units);
   Kat1WriteU64LE(body,128,(fact.expiration>0 ? (ulong)fact.expiration*1000000000 : 0));
   body[136]=1; // UPSERT snapshot record
   body[137]=side;
   body[138]=entry_type;
   body[139]=origin_class;
   body[140]=normalized_state;
   body[141]=Kat1OrderTimeInForce(fact.time_type);
   body[142]=Kat1OrderFillingPolicy(fact.filling_type);
   Kat1WriteU32LE(body,144,presence_flags);
   Kat1WriteU32LE(body,148,(uint)fact.type);
   Kat1WriteU32LE(body,152,(uint)fact.state);
   Kat1WriteU32LE(body,156,(uint)fact.reason);

   return(true);
  }

bool Kat1AppendOrderStateRecord(const SKatOrderFact &fact,
                                const uchar &account_id[],
                                const uchar &linked_order_id[],
                                const uint instrument_id,
                                const uint spec_revision,
                                const ulong order_revision,
                                const uchar price_scale,
                                const uchar volume_scale,
                                const uchar origin_class,
                                const uint presence_flags,
                                uchar &records[],
                                string &error)
  {
   uchar body[];
   if(!Kat1BuildOrderStateRecordBody(fact,
                                     account_id,
                                     linked_order_id,
                                     instrument_id,
                                     spec_revision,
                                     order_revision,
                                     price_scale,
                                     volume_scale,
                                     origin_class,
                                     presence_flags,
                                     body,
                                     error))
      return(false);

   return(Kat1AppendEmbeddedRecord(records,
                                   KAT1_SNAPSHOT_RECORD_ORDER_STATE,
                                   1,
                                   body,
                                   error));
  }

#endif
