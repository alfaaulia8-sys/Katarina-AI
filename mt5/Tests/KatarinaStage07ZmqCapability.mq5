#property strict
#property script_show_inputs

#include <Zmq/Zmq.mqh>
#include <Katarina/Stage07/Kat1Codec.mqh>
#include <Katarina/Stage07/ZmqDealerTransport.mqh>

input string InpEndpoint="tcp://127.0.0.1:5567";
input int InpTimeoutMs=8000;

void KatWriteCapabilityEvidence(const bool passed,
                                const string zmq_version,
                                const string detail)
  {
   const int handle=FileOpen("Katarina_Stage07_zmq_capability_result.txt",
                             FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(handle==INVALID_HANDLE)
      return;

   FileWrite(handle,"schema_version=1.0");
   FileWrite(handle,"stage=07");
   FileWrite(handle,"proof_type=MQL5_ZEROMQ_CAPABILITY");
   FileWrite(handle,"terminal_build="+IntegerToString((int)TerminalInfoInteger(TERMINAL_BUILD)));
   FileWrite(handle,"zmq_version="+zmq_version);
   FileWrite(handle,"endpoint="+InpEndpoint);
   FileWrite(handle,"dlls_allowed="+IntegerToString((int)MQLInfoInteger(MQL_DLLS_ALLOWED)));
   FileWrite(handle,"raw_kat1_bytes="+IntegerToString(104));
   FileWrite(handle,"detail="+detail);
   FileWrite(handle,(passed ? "result=PASS" : "result=FAIL"));
   FileClose(handle);
  }

void OnStart(void)
  {
   bool passed=false;
   string detail="";
   string version="";

   if(!MQLInfoInteger(MQL_DLLS_ALLOWED))
     {
      detail="DLL imports are not allowed";
      Print("FAIL: ",detail);
      KatWriteCapabilityEvidence(false,version,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   uchar expected[];
   string error="";
   if(!Kat1HexToBytes("4b415431010034006400010030000100680000006400000000000000c0d46687b8c1da180807060504030201181716151413121101000000070000005b8a060000000000688a0600000000000000000000000000000000000000000000000000030000006c56d517",expected,error))
     {
      detail="KAT1 fixture decode failed: "+error;
      Print("FAIL: ",detail);
      KatWriteCapabilityEvidence(false,version,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   SKat1Header header;
   if(!Kat1ValidateFrame(expected,header,error))
     {
      detail="KAT1 fixture invalid: "+error;
      Print("FAIL: ",detail);
      KatWriteCapabilityEvidence(false,version,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   version=Zmq::getVersion();
   Print("ZeroMQ version: ",version);

   CKatZmqDealerByteTransport transport;
   if(!transport.Start(InpEndpoint,"kat-stage07-capability",64,64))
     {
      detail="DEALER byte transport start failed";
      Print("FAIL: ",detail);
      KatWriteCapabilityEvidence(false,version,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   // Immediate mode is enabled by the adapter. Give localhost transport a
   // short establishment window before the first nonblocking send.
   Sleep(150);

   if(!transport.SendFrame(expected))
     {
      detail="nonblocking adapter send failed";
      Print("FAIL: ",detail);
      transport.Stop();
      KatWriteCapabilityEvidence(false,version,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   const uint started=GetTickCount();
   while((int)(GetTickCount()-started)<InpTimeoutMs)
     {
      uchar actual[];
      if(transport.ReceiveFrame(actual))
        {
         if(!Kat1BytesEqual(expected,actual))
           {
            detail="echo payload mismatch";
            Print("FAIL: ",detail);
            break;
           }

         SKat1Header echoed;
         string echoed_error="";
         if(!Kat1ValidateFrame(actual,echoed,echoed_error))
           {
            detail="echo KAT1 validation failed: "+echoed_error;
            Print("FAIL: ",detail);
            break;
           }

         if(echoed.message_type!=100 || echoed.frame_length!=104)
           {
            detail="echo KAT1 header mismatch";
            Print("FAIL: ",detail);
            break;
           }

         // Acknowledge the echo before the Python ROUTER is allowed to close.
         // This removes a ZeroMQ linger=0 race from the capability harness.
         if(!transport.SendFrame(actual))
           {
            detail="adapter ACK send failed";
            Print("FAIL: ",detail);
            break;
           }

         if(transport.FramesSent()!=2 || transport.FramesReceived()!=1)
           {
            detail="adapter frame counters mismatch";
            Print("FAIL: ",detail);
            break;
           }

         passed=true;
         detail="raw KAT1 CKatZmqDealerByteTransport acknowledged roundtrip PASS";
         Print("PASS: ",detail);
         break;
        }

      Sleep(10);
     }

   if(!passed && detail=="")
     {
      detail="nonblocking receive timed out";
      Print("FAIL: ",detail);
     }

   transport.Stop();

   KatWriteCapabilityEvidence(passed,version,detail);

   if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
      TerminalClose(passed ? 0 : 7);
  }
