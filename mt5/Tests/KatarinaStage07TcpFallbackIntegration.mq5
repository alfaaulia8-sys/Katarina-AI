#property strict
#property version   "1.00"
#property description "Stage-07 native TCP fallback integration proof."
#property description "Terminal must allow 127.0.0.1 in Tools > Options > Expert Advisors."

#include <Katarina/Stage07/NativeTcpTransport.mqh>

#define KAT7_TCP_ENDPOINT "tcp://127.0.0.1:5572"
#define KAT7_HELLO_HEX "4b4154310100340001000100340003006c000000010000000000000000000000000000000807060504030201181716151413121100112233445566778899aabbccddeeff3f0000000000000000000000000000000000000000000000000100000000000000000000b5861ead"

void WriteEvidence(const bool passed,
                   const string detail,
                   const int last_error,
                   const int frame_length,
                   const ulong frames_sent,
                   const ulong frames_received)
  {
   const int handle=FileOpen("Katarina_Stage07_tcp_fallback_result.txt",
                             FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(handle==INVALID_HANDLE)
      return;

   FileWrite(handle,"stage=07");
   FileWrite(handle,"transport=NATIVE_TCP");
   FileWrite(handle,"endpoint=" KAT7_TCP_ENDPOINT);
   FileWrite(handle,"framing=KAT1_FRAME_LENGTH_ONLY");
   FileWrite(handle,"secondary_envelope=false");
   FileWrite(handle,"golden_message=HELLO");
   FileWrite(handle,"frame_length="+IntegerToString(frame_length));
   FileWrite(handle,"frames_sent="+IntegerToString((long)frames_sent));
   FileWrite(handle,"frames_received="+IntegerToString((long)frames_received));
   FileWrite(handle,"last_error="+IntegerToString(last_error));
   FileWrite(handle,"detail="+detail);
   FileWrite(handle,"result="+(passed ? "PASS" : "FAIL"));
   FileClose(handle);
  }

void OnStart(void)
  {
   uchar golden[];
   string error="";
   if(!Kat1HexToBytes(KAT7_HELLO_HEX,golden,error))
     {
      WriteEvidence(false,"GOLDEN_DECODE_FAILED_"+error,GetLastError(),0,0,0);
      return;
     }

   SKat1Header golden_header;
   if(!Kat1ValidateFrame(golden,golden_header,error))
     {
      WriteEvidence(false,"GOLDEN_VALIDATE_FAILED_"+error,GetLastError(),ArraySize(golden),0,0);
      return;
     }

   CKatNativeTcpByteTransport transport;
   ResetLastError();
   if(!transport.Start(KAT7_TCP_ENDPOINT,3000,5000))
     {
      const int code=GetLastError();
      WriteEvidence(false,
                    "START_FAILED_ALLOW_127_0_0_1_IN_TERMINAL_NETWORK_LIST",
                    code,
                    ArraySize(golden),
                    transport.FramesSent(),
                    transport.FramesReceived());
      return;
     }

   if(!transport.SendFrame(golden))
     {
      const int code=GetLastError();
      WriteEvidence(false,"SEND_FAILED",code,ArraySize(golden),
                    transport.FramesSent(),transport.FramesReceived());
      transport.Stop();
      return;
     }

   uchar echoed[];
   if(!transport.ReceiveFrame(echoed,8000))
     {
      const int code=GetLastError();
      WriteEvidence(false,"RECEIVE_FAILED",code,ArraySize(golden),
                    transport.FramesSent(),transport.FramesReceived());
      transport.Stop();
      return;
     }

   SKat1Header echoed_header;
   if(!Kat1ValidateFrame(echoed,echoed_header,error) ||
      !Kat1BytesEqual(golden,echoed) ||
      echoed_header.message_type!=1 ||
      echoed_header.frame_length!=108)
     {
      WriteEvidence(false,"BYTE_EQUALITY_OR_HEADER_FAILED_"+error,GetLastError(),
                    ArraySize(echoed),transport.FramesSent(),transport.FramesReceived());
      transport.Stop();
      return;
     }

   WriteEvidence(true,"CROSS_LANGUAGE_BYTE_EQUALITY_PASS",0,ArraySize(echoed),
                 transport.FramesSent(),transport.FramesReceived());
   transport.Stop();
  }
