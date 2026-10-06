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
   const bool terminal_connected=(bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   const bool terminal_trade_allowed=(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);

   if(!terminal_connected)
     {
      Print("FAIL_STAGE36_LIVE_PREFLIGHT: terminal not connected");
      failures++;
     }

   if(!account_ok)
     {
      Print("FAIL_STAGE36_LIVE_PREFLIGHT: account facts unavailable");
      failures++;
     }

   bool real_account=false;
   bool account_trade_allowed=false;
   bool expert_trade_allowed=false;

   if(account_ok)
     {
      real_account=(account.trade_mode==ACCOUNT_TRADE_MODE_REAL);
      account_trade_allowed=account.trade_allowed;
      expert_trade_allowed=account.expert_trade_allowed;

      if(!real_account)
        {
         PrintFormat("FAIL_STAGE36_LIVE_PREFLIGHT: REAL account required, mode=%d",
                     (int)account.trade_mode);
         failures++;
        }
      if(!account_trade_allowed)
        {
         Print("FAIL_STAGE36_LIVE_PREFLIGHT: broker account trade permission disabled");
         failures++;
        }
      if(!expert_trade_allowed)
        {
         Print("FAIL_STAGE36_LIVE_PREFLIGHT: expert trading permission disabled");
         failures++;
        }
     }

   if(!terminal_trade_allowed)
     {
      Print("FAIL_STAGE36_LIVE_PREFLIGHT: terminal trade permission disabled");
      failures++;
     }

   const int handle=FileOpen("Katarina_Stage36_live_preflight.txt",
                             FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
   if(handle==INVALID_HANDLE)
     {
      PrintFormat("FAIL_STAGE36_LIVE_PREFLIGHT: evidence open failed error=%d",GetLastError());
      failures++;
     }
   else
     {
      KatWriteLine(handle,"schema_version","1");
      KatWriteLine(handle,"stage","36");
      KatWriteLine(handle,"proof_type","LIVE_ENVIRONMENT_PREFLIGHT");
      KatWriteLine(handle,"terminal_connected",(terminal_connected ? "true" : "false"));
      KatWriteLine(handle,"terminal_trade_allowed",(terminal_trade_allowed ? "true" : "false"));
      KatWriteLine(handle,"account_facts_ok",(account_ok ? "true" : "false"));
      if(account_ok)
        {
         KatWriteLine(handle,"trade_mode",IntegerToString((int)account.trade_mode));
         KatWriteLine(handle,"broker_server",account.server);
         KatWriteLine(handle,"login_last4",IntegerToString((long)(account.login%10000)));
        }
      KatWriteLine(handle,"real_account",(real_account ? "true" : "false"));
      KatWriteLine(handle,"account_trade_allowed",(account_trade_allowed ? "true" : "false"));
      KatWriteLine(handle,"expert_trade_allowed",(expert_trade_allowed ? "true" : "false"));
      KatWriteLine(handle,"broker_mutation","false");
      KatWriteLine(handle,"live_risk_ready","false");
      KatWriteLine(handle,"live_execution_authority","false");
      KatWriteLine(handle,"result",
                   (failures==0 ? "PASS_STAGE36_LIVE_PREFLIGHT" : "FAIL_STAGE36_LIVE_PREFLIGHT"));
      FileClose(handle);
     }

   if(failures==0)
      Print("PASS_STAGE36_LIVE_PREFLIGHT");
   else
      PrintFormat("FAIL_STAGE36_LIVE_PREFLIGHT failures=%d",failures);
  }
