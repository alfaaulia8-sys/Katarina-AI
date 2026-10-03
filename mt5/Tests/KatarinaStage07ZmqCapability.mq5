#property strict
#property script_show_inputs

#include <Zmq/Zmq.mqh>
#include <Katarina/Stage07/Kat1Codec.mqh>

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
   if(!Kat1HexToBytes("4b41543101003400640001003000010068000000040000000000000000885963845701002a000000000000002b0000000000000007000000010000005c110000000000009812000000000000f411000000000000d2040000000000000300000003000000d840f954",expected,error))
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

   Context context("__katarina_stage07_capability__");
   Socket socket(context,ZMQ_DEALER);

   if(!socket.valid())
     {
      detail="DEALER socket creation failed";
      Print("FAIL: ",detail);
      KatWriteCapabilityEvidence(false,version,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   if(!socket.connect(InpEndpoint))
     {
      detail="DEALER connect failed: "+Zmq::errorMessage();
      Print("FAIL: ",detail);
      KatWriteCapabilityEvidence(false,version,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   // Give the DEALER a short time to establish the localhost connection.
   Sleep(150);

   if(!socket.send(expected,true))
     {
      detail="nonblocking send failed: "+Zmq::errorMessage();
      Print("FAIL: ",detail);
      KatWriteCapabilityEvidence(false,version,detail);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   const uint started=GetTickCount();
   while((int)(GetTickCount()-started)<InpTimeoutMs)
     {
      ZmqMsg reply;
      if(socket.recv(reply,true))
        {
         uchar actual[];
         reply.getData(actual);

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

         passed=true;
         detail="raw KAT1 DEALER/ROUTER roundtrip PASS";
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

   KatWriteCapabilityEvidence(passed,version,detail);

   if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
      TerminalClose(passed ? 0 : 7);
  }
