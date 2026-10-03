#property strict
#property script_show_inputs

#include <Katarina/Stage07/Kat1Codec.mqh>
#include <Katarina/Stage07/Kat1SystemMessages.mqh>
#include <Katarina/Stage07/ZmqDealerTransport.mqh>

input string InpEndpoint="tcp://127.0.0.1:5568";
input int InpTimeoutMs=8000;

void KatWriteHandshakeEvidence(const bool passed,
                               const string detail)
  {
   const int handle=FileOpen("Katarina_Stage07_handshake_result.txt",
                             FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(handle==INVALID_HANDLE)
      return;

   FileWrite(handle,"schema_version=1.0");
   FileWrite(handle,"stage=07");
   FileWrite(handle,"proof_type=MQL5_PYTHON_KAT1_HANDSHAKE");
   FileWrite(handle,"terminal_build="+IntegerToString((int)TerminalInfoInteger(TERMINAL_BUILD)));
   FileWrite(handle,"endpoint="+InpEndpoint);
   FileWrite(handle,"stream_id=77");
   FileWrite(handle,"boot_id=88");
   FileWrite(handle,"execution_mode=READ_ONLY");
   FileWrite(handle,"expected_python_state=RECOVERING");
   FileWrite(handle,"live_risk_ready=0");
   FileWrite(handle,"detail="+detail);
   FileWrite(handle,(passed ? "result=PASS" : "result=FAIL"));
   FileClose(handle);
  }

bool KatSendWithDeadline(CKatZmqDealerByteTransport &transport,
                         const uchar &frame[],
                         const int timeout_ms)
  {
   const uint started=GetTickCount();
   while((int)(GetTickCount()-started)<timeout_ms)
     {
      if(transport.SendFrame(frame))
         return(true);
      Sleep(10);
     }
   return(false);
  }

bool KatReceiveWithDeadline(CKatZmqDealerByteTransport &transport,
                            uchar &frame[],
                            const int timeout_ms)
  {
   const uint started=GetTickCount();
   while((int)(GetTickCount()-started)<timeout_ms)
     {
      if(transport.ReceiveFrame(frame))
         return(true);
      Sleep(10);
     }
   return(false);
  }

void OnStart(void)
  {
   bool passed=false;
   string detail="";
   const ulong stream_id=77;
   const ulong boot_id=88;

   CKatZmqDealerByteTransport transport;
   if(!transport.Start(InpEndpoint,"kat-stage07-handshake",64,64))
     {
      detail="DEALER transport start failed";
      Print("FAIL: ",detail);
      KatWriteHandshakeEvidence(false,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   uchar heartbeat[];
   string error="";
   if(!Kat1BuildHeartbeat(1,
                          1000000000,
                          stream_id,
                          boot_id,
                          1000,
                          1,
                          0,
                          0,
                          0,
                          1000000000,
                          1,
                          heartbeat,
                          error))
     {
      detail="HEARTBEAT build failed: "+error;
      Print("FAIL: ",detail);
      transport.Stop();
      KatWriteHandshakeEvidence(false,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   if(!KatSendWithDeadline(transport,heartbeat,InpTimeoutMs))
     {
      detail="HEARTBEAT send timed out";
      Print("FAIL: ",detail);
      transport.Stop();
      KatWriteHandshakeEvidence(false,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   uchar hello_frame[];
   if(!KatReceiveWithDeadline(transport,hello_frame,InpTimeoutMs))
     {
      detail="HELLO receive timed out";
      Print("FAIL: ",detail);
      transport.Stop();
      KatWriteHandshakeEvidence(false,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   SKat1Header hello_header;
   if(!Kat1ValidateFrame(hello_frame,hello_header,error))
     {
      detail="HELLO frame invalid: "+error;
      Print("FAIL: ",detail);
      transport.Stop();
      KatWriteHandshakeEvidence(false,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   if(hello_header.stream_id!=stream_id || hello_header.boot_id!=boot_id)
     {
      detail="HELLO stream/boot binding mismatch";
      Print("FAIL: ",detail);
      transport.Stop();
      KatWriteHandshakeEvidence(false,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   SKat1HelloMessage hello;
   if(!Kat1DecodeHello(hello_frame,hello,error))
     {
      detail="HELLO decode failed: "+error;
      Print("FAIL: ",detail);
      transport.Stop();
      KatWriteHandshakeEvidence(false,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   if(hello.requested_execution_mode!=0)
     {
      detail="Python HELLO requested non-read-only execution";
      Print("FAIL: ",detail);
      transport.Stop();
      KatWriteHandshakeEvidence(false,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   uchar account_id[];
   ArrayResize(account_id,16);
   ArrayInitialize(account_id,0x11);

   uchar source_hash[];
   ArrayResize(source_hash,32);
   ArrayInitialize(source_hash,0x22);

   uchar hello_ack[];
   if(!Kat1BuildHelloAck(2,
                         1100000000,
                         stream_id,
                         boot_id,
                         account_id,
                         123456,
                         (uint)TerminalInfoInteger(TERMINAL_BUILD),
                         700,
                         0,
                         1,
                         1,
                         0,
                         1,
                         2,
                         2,
                         source_hash,
                         1,
                         "Katarina-CI",
                         "USD",
                         hello_ack,
                         error))
     {
      detail="HELLO_ACK build failed: "+error;
      Print("FAIL: ",detail);
      transport.Stop();
      KatWriteHandshakeEvidence(false,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   if(!KatSendWithDeadline(transport,hello_ack,InpTimeoutMs))
     {
      detail="HELLO_ACK send timed out";
      Print("FAIL: ",detail);
      transport.Stop();
      KatWriteHandshakeEvidence(false,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   // Python sends one final HEARTBEAT only after its session supervisor has
   // accepted HELLO_ACK and entered RECOVERING.
   uchar python_heartbeat[];
   if(!KatReceiveWithDeadline(transport,python_heartbeat,InpTimeoutMs))
     {
      detail="post-HELLO_ACK Python HEARTBEAT timed out";
      Print("FAIL: ",detail);
      transport.Stop();
      KatWriteHandshakeEvidence(false,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   SKat1Header final_header;
   if(!Kat1ValidateFrame(python_heartbeat,final_header,error) ||
      final_header.message_type!=KAT1_MSG_HEARTBEAT ||
      final_header.stream_id!=stream_id ||
      final_header.boot_id!=boot_id)
     {
      detail="post-HELLO_ACK Python HEARTBEAT invalid";
      Print("FAIL: ",detail);
      transport.Stop();
      KatWriteHandshakeEvidence(false,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   // ACK the Python heartbeat so its linger=0 ROUTER can close only after
   // bidirectional proof is complete.
   uchar final_ack[];
   if(!Kat1BuildHeartbeat(3,
                          1200000000,
                          stream_id,
                          boot_id,
                          1200,
                          3,
                          0,
                          0,
                          0,
                          1200000000,
                          1,
                          final_ack,
                          error) ||
      !KatSendWithDeadline(transport,final_ack,InpTimeoutMs))
     {
      detail="final HEARTBEAT ACK failed";
      Print("FAIL: ",detail);
      transport.Stop();
      KatWriteHandshakeEvidence(false,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   passed=true;
   detail="HEARTBEAT->HELLO->HELLO_ACK cross-language RECOVERING handshake PASS";
   Print("PASS: ",detail);

   KatWriteHandshakeEvidence(passed,detail);
   transport.Stop();

   if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
      TerminalClose(0);
  }
