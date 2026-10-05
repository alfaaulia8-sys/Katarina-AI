#property strict

#include <Katarina/NativeFacts.mqh>

void KatWriteLine(const int handle,const string key,const string value)
  {
   if(handle==INVALID_HANDLE)
      return;
   FileWriteString(handle,key+"="+value+"\r\n");
  }

void OnStart(void)
  {
   int failures=0;
   SKatAccountFacts account;
   const bool account_ok=KatReadAccountFacts(account);

   if(!account_ok)
     {
      Print("FAIL_STAGE36_DEMO_GATE: account facts unavailable");
      failures++;
     }

   bool non_real=false;
   if(account_ok)
     {
      non_real=(account.trade_mode==ACCOUNT_TRADE_MODE_DEMO ||
                account.trade_mode==ACCOUNT_TRADE_MODE_CONTEST);
      if(account.trade_mode==ACCOUNT_TRADE_MODE_REAL)
        {
         Print("FAIL_STAGE36_DEMO_GATE: REAL account is forbidden");
         failures++;
        }
      else if(!non_real)
        {
         PrintFormat("FAIL_STAGE36_DEMO_GATE: unsupported account trade mode=%d",
                     (int)account.trade_mode);
         failures++;
        }
     }

   const int handle=FileOpen("Katarina_Stage36_demo_gate.txt",
                             FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
   if(handle==INVALID_HANDLE)
     {
      PrintFormat("FAIL_STAGE36_DEMO_GATE: evidence open failed error=%d",GetLastError());
      failures++;
     }
   else
     {
      KatWriteLine(handle,"schema_version","1");
      KatWriteLine(handle,"stage","36");
      KatWriteLine(handle,"proof_type","DEMO_ACCOUNT_GATE");
      KatWriteLine(handle,"account_facts_ok",(account_ok ? "true" : "false"));
      if(account_ok)
        {
         KatWriteLine(handle,"trade_mode",IntegerToString((int)account.trade_mode));
         KatWriteLine(handle,"broker_server",account.server);
         KatWriteLine(handle,"login_last4",IntegerToString((long)(account.login%10000)));
        }
      KatWriteLine(handle,"non_real_account",(non_real ? "true" : "false"));
      KatWriteLine(handle,"broker_mutation","false");
      KatWriteLine(handle,"live_risk_ready","false");
      KatWriteLine(handle,"live_execution_enabled","false");
      KatWriteLine(handle,"result",
                   (failures==0 ? "PASS_STAGE36_DEMO_GATE" : "FAIL_STAGE36_DEMO_GATE"));
      FileClose(handle);
     }

   if(failures==0)
      Print("PASS_STAGE36_DEMO_GATE");
   else
      PrintFormat("FAIL_STAGE36_DEMO_GATE failures=%d",failures);
  }
