#property strict
#property script_show_inputs

#include <Katarina/Stage07/Kat1NativeRecords.mqh>

string BytesToHex(const uchar &data[])
  {
   const string digits="0123456789abcdef";
   string out="";
   const int size=ArraySize(data);
   for(int i=0;i<size;i++)
     {
      const int value=(int)data[i];
      out+=StringSubstr(digits,(value>>4)&0x0F,1);
      out+=StringSubstr(digits,value&0x0F,1);
     }
   return(out);
  }

void WriteEvidence(const string result,
                   const string detail,
                   const uchar &body[])
  {
   const int h=FileOpen("Katarina_Stage07_native_account_record_result.txt",
                        FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE)
      return;

   FileWrite(h,"schema_version=1.0");
   FileWrite(h,"stage=07");
   FileWrite(h,"proof_type=MQL5_NATIVE_ACCOUNT_RECORD");
   FileWrite(h,"broker_server=Katarina-CI");
   FileWrite(h,"broker_login=123456");
   FileWrite(h,"currency=USD");
   FileWrite(h,"currency_digits=2");
   FileWrite(h,"account_revision=55");
   FileWrite(h,"account_unit_profile_revision=9");
   FileWrite(h,"body_bytes="+IntegerToString(ArraySize(body)));
   FileWrite(h,"body_hex="+BytesToHex(body));
   FileWrite(h,"detail="+detail);
   FileWrite(h,"result="+result);
   FileClose(h);
  }

void OnStart(void)
  {
   SKatAccountFacts facts;
   ZeroMemory(facts);
   facts.login=123456;
   facts.leverage=500;
   facts.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
   facts.trade_mode=ACCOUNT_TRADE_MODE_REAL;
   facts.stopout_mode=ACCOUNT_STOPOUT_MODE_PERCENT;
   facts.trade_allowed=true;
   facts.expert_trade_allowed=true;
   facts.hedge_allowed=true;
   facts.fifo_close=false;
   facts.server="Katarina-CI";
   facts.currency="USD";
   facts.currency_digits=2;

   facts.balance=1000.00;
   facts.equity=987.66;
   facts.credit=0.00;
   facts.profit=-12.34;
   facts.margin=50.00;
   facts.free_margin=937.66;
   facts.margin_initial=0.00;
   facts.margin_maintenance=0.00;
   facts.margin_level=1975.32;
   facts.margin_call=50.00;
   facts.stopout_level=20.00;

   uchar body[];
   string error="";
   if(!Kat1BuildAccountStateRecordBody(facts,55,9,body,error))
     {
      WriteEvidence("FAIL","account body build failed: "+error,body);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   if(ArraySize(body)!=144)
     {
      WriteEvidence("FAIL","account body length is not 144",body);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   WriteEvidence("PASS","native account body built",body);
   if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
      TerminalClose(0);
  }
