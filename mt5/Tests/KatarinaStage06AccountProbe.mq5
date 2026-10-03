#property strict
#property script_show_inputs

#include <Katarina/NativeFacts.mqh>
#include <Katarina/NativeSnapshot.mqh>
#include <Katarina/HealthSample.mqh>
#include <Katarina/SessionState.mqh>
#include <Katarina/TestEvidence.mqh>

input string InpAccountClass="UNSPECIFIED";

string KatResolveProbeClass(void)
  {
   if(!MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
      return InpAccountClass;

   int handle=FileOpen("Katarina_Stage06_probe_class.txt",
                       FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(handle==INVALID_HANDLE)
      return InpAccountClass;

   string value=FileReadString(handle);
   FileClose(handle);
   StringTrimLeft(value);
   StringTrimRight(value);
   return value;
  }

void OnStart(void)
  {
   int failures=0;
   const string account_class=KatResolveProbeClass();

   const bool discovery_mode=(account_class=="DISCOVERY");
   const bool account_class_valid=
      (account_class=="STANDARD_LIKE" ||
       account_class=="CENT_LIKE" ||
       discovery_mode);

   if(!account_class_valid)
     {
      Print("FAIL: account class must be STANDARD_LIKE, CENT_LIKE, or DISCOVERY");
      failures++;
     }

   SKatAccountFacts account;
   bool account_ok=KatReadAccountFacts(account);
   if(!account_ok)
     {
      Print("FAIL: account facts unavailable");
      failures++;
     }
   else
     {
      PrintFormat("PASS: account server=%s currency=%s digits=%d margin_mode=%d balance=%G equity=%G",
                  account.server,
                  account.currency,
                  account.currency_digits,
                  (int)account.margin_mode,
                  account.balance,
                  account.equity);
     }

   SKatSymbolFacts symbol;
   bool symbol_ok=KatReadSymbolFacts(_Symbol,symbol);
   if(!symbol_ok)
     {
      PrintFormat("FAIL: SymbolSpec unavailable for %s",_Symbol);
      failures++;
     }
   else
     {
      PrintFormat("PASS: symbol=%s digits=%d contract=%G tick_size=%G tick_value=%G volume_min=%G volume_step=%G",
                  symbol.symbol,
                  symbol.digits,
                  symbol.contract_size,
                  symbol.tick_size,
                  symbol.tick_value,
                  symbol.volume_min,
                  symbol.volume_step);
     }

   CKatNativeSnapshot snapshot;
   bool snapshot_ok=snapshot.BuildStable(1,3);
   if(!snapshot_ok)
     {
      Print("FAIL: complete native snapshot unavailable");
      failures++;
     }
   else
     {
      PrintFormat("PASS: complete snapshot positions=%d orders=%d",
                  snapshot.PositionCount(),
                  snapshot.OrderCount());
     }

   SKatHealthSample health;
   bool health_ok=KatSampleHealth(_Symbol,health);
   if(!health_ok)
      Print("INFO: terminal currently disconnected; health sample still captured");
   else
      PrintFormat("PASS: health connected=%d terminal_trade=%d mql_trade=%d account_trade=%d expert=%d ping_us=%I64d",
                  (int)health.terminal_connected,
                  (int)health.terminal_trade_allowed,
                  (int)health.mql_trade_allowed,
                  (int)health.account_trade_allowed,
                  (int)health.account_expert_allowed,
                  health.terminal_ping_us);

   SKatSessionState session;
   bool session_ok=KatReadSessionState(_Symbol,session);
   if(!session_ok)
      Print("INFO: session state unavailable at this moment");
   else
      PrintFormat("PASS: session scheduled=%d open=%d trade_allowed=%d sessions_today=%d",
                  (int)session.scheduled_open,
                  (int)session.session_open,
                  (int)session.symbol_trade_allowed,
                  session.session_count_today);

   const string class_token=KatEvidenceSafeToken(account_class);
   const int evidence=KatOpenEvidenceFile("account_probe_"+class_token+".txt");

   if(evidence==INVALID_HANDLE)
     {
      PrintFormat("FAIL: unable to write Stage 06 account probe evidence, error=%d",GetLastError());
      failures++;
     }
   else
     {
      KatEvidenceWrite(evidence,"schema_version","1.0");
      KatEvidenceWrite(evidence,"stage","06");
      KatEvidenceWrite(evidence,"design_version",KAT_STAGE06_DESIGN_VERSION);
      KatEvidenceWriteLong(evidence,"generated_epoch_seconds",(long)TimeGMT());
      KatEvidenceWrite(evidence,"proof_type",(discovery_mode ? "ACCOUNT_DISCOVERY" : "ACCOUNT_PROBE"));
      KatEvidenceWrite(evidence,"account_class",account_class);
      KatEvidenceWriteLong(evidence,"terminal_build",TerminalInfoInteger(TERMINAL_BUILD));
      KatEvidenceWrite(evidence,"symbol",_Symbol);

      if(account_ok)
        {
         KatEvidenceWrite(evidence,"broker_server",account.server);
         KatEvidenceWrite(evidence,"account_currency",account.currency);
         KatEvidenceWriteLong(evidence,"account_currency_digits",account.currency_digits);
         KatEvidenceWriteLong(evidence,"margin_mode",(long)account.margin_mode);
         KatEvidenceWriteULong(evidence,"login_last4",(account.login%10000));
         KatEvidenceWriteDouble(evidence,"balance_native",account.balance,account.currency_digits);
         KatEvidenceWriteDouble(evidence,"equity_native",account.equity,account.currency_digits);
        }

      if(symbol_ok)
        {
         KatEvidenceWriteLong(evidence,"symbol_digits",symbol.digits);
         KatEvidenceWriteDouble(evidence,"contract_size",symbol.contract_size,8);
         KatEvidenceWriteDouble(evidence,"tick_size",symbol.tick_size,12);
         KatEvidenceWriteDouble(evidence,"tick_value",symbol.tick_value,8);
         KatEvidenceWriteDouble(evidence,"volume_min",symbol.volume_min,8);
         KatEvidenceWriteDouble(evidence,"volume_max",symbol.volume_max,8);
         KatEvidenceWriteDouble(evidence,"volume_step",symbol.volume_step,8);
        }

      KatEvidenceWriteBool(evidence,"snapshot_complete",snapshot_ok);
      if(snapshot_ok)
        {
         KatEvidenceWriteLong(evidence,"positions",snapshot.PositionCount());
         KatEvidenceWriteLong(evidence,"orders",snapshot.OrderCount());
        }

      KatEvidenceWriteBool(evidence,"terminal_connected",health.terminal_connected);
      KatEvidenceWriteBool(evidence,"terminal_trade_allowed",health.terminal_trade_allowed);
      KatEvidenceWriteBool(evidence,"mql_trade_allowed",health.mql_trade_allowed);
      KatEvidenceWriteBool(evidence,"account_trade_allowed",health.account_trade_allowed);
      KatEvidenceWriteBool(evidence,"account_expert_allowed",health.account_expert_allowed);
      KatEvidenceWriteLong(evidence,"terminal_ping_us",health.terminal_ping_us);

      KatEvidenceWriteBool(evidence,"session_read_ok",session_ok);
      if(session_ok)
        {
         KatEvidenceWriteBool(evidence,"session_scheduled",session.scheduled_open);
         KatEvidenceWriteBool(evidence,"session_open",session.session_open);
         KatEvidenceWriteBool(evidence,"symbol_trade_allowed",session.symbol_trade_allowed);
         KatEvidenceWriteLong(evidence,"sessions_today",session.session_count_today);
        }

      KatEvidenceWriteLong(evidence,"failures",failures);
      KatEvidenceWrite(evidence,"result",(failures==0 ? "PASS" : "FAIL"));
      FileClose(evidence);

      Print("Stage 06 account probe evidence: ",KatEvidenceCommonRoot());
     }

   if(failures==0)
      Print("Katarina Stage 06 account probe PASSED");
   else
      PrintFormat("Katarina Stage 06 account probe FAILED: %d",failures);

   if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
      TerminalClose(failures==0 ? 0 : 7);
  }
