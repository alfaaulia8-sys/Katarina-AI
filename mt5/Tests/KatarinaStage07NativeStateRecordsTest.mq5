#property strict
#property script_show_inputs

#include <Katarina/Stage07/Kat1NativeRecords.mqh>

string BytesToHex(const uchar &data[])
  {
   const string digits="0123456789abcdef";
   string out="";
   for(int i=0;i<ArraySize(data);i++)
     {
      const int value=(int)data[i];
      out+=StringSubstr(digits,(value>>4)&0x0F,1);
      out+=StringSubstr(digits,value&0x0F,1);
     }
   return(out);
  }

bool WriteEvidence(const string result,
                   const string detail,
                   const uchar &symbol_body[],
                   const uchar &session_body[],
                   const uchar &position_body[],
                   const uchar &order_body[])
  {
   const int h=FileOpen("Katarina_Stage07_native_state_records_result.txt",
                        FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE)
      return(false);

   FileWrite(h,"schema_version=1.0");
   FileWrite(h,"stage=07");
   FileWrite(h,"proof_type=MQL5_NATIVE_STATE_RECORDS");
   FileWrite(h,"symbol_body_hex="+BytesToHex(symbol_body));
   FileWrite(h,"session_body_hex="+BytesToHex(session_body));
   FileWrite(h,"position_body_hex="+BytesToHex(position_body));
   FileWrite(h,"order_body_hex="+BytesToHex(order_body));
   FileWrite(h,"detail="+detail);
   FileWrite(h,"result="+result);
   FileClose(h);
   return(true);
  }

void Finish(const int code)
  {
   if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
      TerminalClose(code);
  }

void OnStart(void)
  {
   string error="";
   uchar symbol_body[];
   uchar session_body[];
   uchar position_body[];
   uchar order_body[];

   SKatSymbolFacts symbol;
   ZeroMemory(symbol);
   symbol.symbol="XAUUSD.a";
   symbol.digits=2;
   symbol.calc_mode=(ENUM_SYMBOL_CALC_MODE)0;
   symbol.trade_mode=(ENUM_SYMBOL_TRADE_MODE)4;
   symbol.swap_mode=(ENUM_SYMBOL_SWAP_MODE)1;
   symbol.order_mode=127;
   symbol.filling_mode=3;
   symbol.expiration_mode=15;
   symbol.stops_level_points=20;
   symbol.freeze_level_points=5;
   symbol.point=0.01;
   symbol.tick_size=0.01;
   symbol.tick_value=1.23;
   symbol.tick_value_profit=1.24;
   symbol.tick_value_loss=1.22;
   symbol.contract_size=100.0;
   symbol.volume_min=0.01;
   symbol.volume_max=100.0;
   symbol.volume_step=0.01;
   symbol.volume_limit=200.0;
   symbol.margin_initial=0.0;
   symbol.margin_maintenance=0.0;
   symbol.swap_long=-12.5;
   symbol.swap_short=3.25;
   symbol.swap_sunday=1.0;
   symbol.swap_monday=1.0;
   symbol.swap_tuesday=1.0;
   symbol.swap_wednesday=3.0;
   symbol.swap_thursday=1.0;
   symbol.swap_friday=1.0;
   symbol.swap_saturday=1.0;
   symbol.base_currency="XAU";
   symbol.profit_currency="USD";
   symbol.margin_currency="USD";

   if(!Kat1BuildSymbolSpecRecordBody(symbol,
                                     1,
                                     7,
                                     2,
                                     2,
                                     2,
                                     "XAUUSD",
                                     0,
                                     symbol_body,
                                     error))
     {
      WriteEvidence("FAIL","SYMBOL_SPEC build failed: "+error,
                    symbol_body,session_body,position_body,order_body);
      Finish(7);
      return;
     }

   SKatSessionState session;
   ZeroMemory(session);
   session.scheduled_open=true;
   session.session_open=true;
   session.symbol_trade_allowed=true;
   session.server_time_seconds=1790956800;
   session.last_tick_time_msc=1790956800123;
   session.session_count_today=1;

   if(!Kat1BuildSessionStateRecordBody(1,
                                       7,
                                       11,
                                       session,
                                       true,
                                       true,
                                       true,
                                       true,
                                       33000,
                                       session_body,
                                       error))
     {
      WriteEvidence("FAIL","SESSION_STATE build failed: "+error,
                    symbol_body,session_body,position_body,order_body);
      Finish(7);
      return;
     }

   uchar account_id[];
   if(!Kat1BuildAccountId("Katarina-CI",123456,account_id,error))
     {
      WriteEvidence("FAIL","account_id build failed: "+error,
                    symbol_body,session_body,position_body,order_body);
      Finish(7);
      return;
     }

   SKatPositionFact position;
   ZeroMemory(position);
   position.ticket=10001;
   position.identifier=11001;
   position.symbol="XAUUSD.a";
   position.magic=778899;
   position.type=POSITION_TYPE_BUY;
   position.reason=(ENUM_POSITION_REASON)3;
   position.time_msc=1790956800123;
   position.time_update_msc=1790956860456;
   position.volume=0.10;
   position.price_open=4286.35;
   position.price_current=4287.11;
   position.sl=4275.00;
   position.tp=4310.00;
   position.swap=-1.25;
   position.profit=35.50;

   if(!Kat1BuildPositionStateRecordBody(position,
                                        account_id,
                                        1,
                                        7,
                                        9,
                                        2,
                                        2,
                                        2,
                                        1,
                                        0,
                                        position_body,
                                        error))
     {
      WriteEvidence("FAIL","POSITION_STATE build failed: "+error,
                    symbol_body,session_body,position_body,order_body);
      Finish(7);
      return;
     }

   SKatOrderFact order;
   ZeroMemory(order);
   order.ticket=8001;
   order.symbol="XAUUSD.a";
   order.magic=778899;
   order.type=ORDER_TYPE_BUY_LIMIT;
   order.state=ORDER_STATE_PLACED;
   order.reason=(ENUM_ORDER_REASON)3;
   order.time_type=ORDER_TIME_SPECIFIED;
   order.filling_type=ORDER_FILLING_FOK;
   order.time_setup_msc=1790956800123;
   order.time_done_msc=0;
   order.expiration=(datetime)1790960400;
   order.volume_initial=0.10;
   order.volume_current=0.10;
   order.price_open=4280.00;
   order.price_stoplimit=0.00;
   order.sl=4270.00;
   order.tp=4310.00;
   order.position_id=0;
   order.position_by_id=0;

   uchar linked_order_id[];
   ArrayResize(linked_order_id,16);
   ArrayInitialize(linked_order_id,0);

   if(!Kat1BuildOrderStateRecordBody(order,
                                     account_id,
                                     linked_order_id,
                                     1,
                                     7,
                                     4,
                                     2,
                                     2,
                                     1,
                                     0,
                                     order_body,
                                     error))
     {
      WriteEvidence("FAIL","ORDER_STATE build failed: "+error,
                    symbol_body,session_body,position_body,order_body);
      Finish(7);
      return;
     }

   if(ArraySize(session_body)!=48 ||
      ArraySize(position_body)!=144 ||
      ArraySize(order_body)!=160 ||
      ArraySize(symbol_body)<=184)
     {
      WriteEvidence("FAIL","record body lengths are invalid",
                    symbol_body,session_body,position_body,order_body);
      Finish(7);
      return;
     }

   WriteEvidence("PASS",
                 "native state record bodies built",
                 symbol_body,session_body,position_body,order_body);
   Finish(0);
  }
