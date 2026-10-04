#property strict
#property script_show_inputs

#include <Katarina/NativeFacts.mqh>
#include <Katarina/Stage07/BridgeTransport.mqh>

input string InpEndpoint="tcp://127.0.0.1:5569";
input int InpTimeoutMs=8000;

void WriteEvidence(const bool passed,
                   const string detail)
  {
   const int h=FileOpen("Katarina_Stage07_bridge_transport_result.txt",
                        FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE)
      return;

   FileWrite(h,"schema_version=1.0");
   FileWrite(h,"stage=07");
   FileWrite(h,"proof_type=MQL5_STAGE07_BRIDGE_TRANSPORT");
   FileWrite(h,"endpoint="+InpEndpoint);
   FileWrite(h,"expected_state=RECOVERING");
   FileWrite(h,"communication_ready=0");
   FileWrite(h,"live_risk_ready=0");
   FileWrite(h,"detail="+detail);
   FileWrite(h,(passed ? "result=PASS" : "result=FAIL"));
   FileClose(h);
  }

void Finish(const int code)
  {
   if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
      TerminalClose(code);
  }

void OnStart(void)
  {
   SKatAccountFacts account;
   ZeroMemory(account);
   account.login=123456;
   account.server="Katarina-CI";
   account.currency="USD";
   account.currency_digits=2;
   account.margin_mode=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
   account.trade_mode=ACCOUNT_TRADE_MODE_DEMO;

   CKatStage07Transport transport;
   if(!transport.Configure(InpEndpoint,
                           77,
                           88,
                           account))
     {
      WriteEvidence(false,"transport configure failed");
      Finish(7);
      return;
     }

   if(!transport.Start())
     {
      WriteEvidence(false,"transport start failed");
      Finish(7);
      return;
     }

   const uint started=GetTickCount();
   while((int)(GetTickCount()-started)<InpTimeoutMs)
     {
      transport.Pump(64,2000);

      if(transport.IsFaulted())
        {
         transport.Stop();
         WriteEvidence(false,"transport entered FAULTED");
         Finish(7);
         return;
        }

      if(transport.IsRecovering())
        {
         transport.Stop();
         WriteEvidence(true,
                       "concrete Stage-07 transport completed heartbeat/HELLO/HELLO_ACK and remained RECOVERING");
         Finish(0);
         return;
        }

      Sleep(10);
     }

   transport.Stop();
   WriteEvidence(false,"timed out before RECOVERING");
   Finish(7);
  }
