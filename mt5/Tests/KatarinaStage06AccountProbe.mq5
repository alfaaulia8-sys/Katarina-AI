#property strict
#property script_show_inputs

#include <Katarina/NativeFacts.mqh>
#include <Katarina/NativeSnapshot.mqh>
#include <Katarina/HealthSample.mqh>
#include <Katarina/SessionState.mqh>

void OnStart(void)
  {
   int failures=0;

   SKatAccountFacts account;
   if(!KatReadAccountFacts(account))
     {
      Print("FAIL: account facts unavailable");
      failures++;
     }
   else
     {
      PrintFormat("PASS: account login=%I64u server=%s currency=%s digits=%d margin_mode=%d balance=%G equity=%G",
                  account.login,
                  account.server,
                  account.currency,
                  account.currency_digits,
                  (int)account.margin_mode,
                  account.balance,
                  account.equity);
     }

   SKatSymbolFacts symbol;
   if(!KatReadSymbolFacts(_Symbol,symbol))
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
   if(!snapshot.BuildStable(1,3))
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
   if(!KatSampleHealth(_Symbol,health))
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
   if(!KatReadSessionState(_Symbol,session))
     {
      Print("INFO: session state unavailable at this moment");
     }
   else
     {
      PrintFormat("PASS: session scheduled=%d open=%d trade_allowed=%d sessions_today=%d",
                  (int)session.scheduled_open,
                  (int)session.session_open,
                  (int)session.symbol_trade_allowed,
                  session.session_count_today);
     }

   if(failures==0)
      Print("Katarina Stage 06 account probe PASSED");
   else
      PrintFormat("Katarina Stage 06 account probe FAILED: %d",failures);
  }
