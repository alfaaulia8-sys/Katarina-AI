#property strict
#property script_show_inputs

#include <Katarina/Stage07/ZmqDealerTransport.mqh>
#include <Katarina/Stage07/Kat1SystemMessages.mqh>
#include <Katarina/Stage07/Kat1RecoveryMessages.mqh>
#include <Katarina/Stage07/IdentityV1.mqh>
#include <Katarina/Stage07/WireSequence.mqh>

input string InpEndpoint="tcp://127.0.0.1:5571";
input int InpTimeoutMs=10000;

#define KAT_RECONNECT_MARKER "Katarina_Stage07_reconnect_phase.txt"
#define KAT_RECONNECT_RESULT "Katarina_Stage07_reconnect_result.txt"

bool SendWithDeadline(CKatZmqDealerByteTransport &transport,
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

bool ReceiveWithDeadline(CKatZmqDealerByteTransport &transport,
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

string ReadCommonText(const string name)
  {
   const int h=FileOpen(name,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE)
      return("");
   const string value=FileReadString(h);
   FileClose(h);
   return(value);
  }

bool WriteCommonText(const string name,const string value)
  {
   const int h=FileOpen(name,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE)
      return(false);
   FileWrite(h,value);
   FileClose(h);
   return(true);
  }

void WriteResult(const string result,
                 const string detail,
                 const int phase,
                 const ulong boot_id,
                 const ulong last_mt5_sequence,
                 const ulong last_python_sequence)
  {
   const int h=FileOpen(KAT_RECONNECT_RESULT,
                        FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE)
      return;

   FileWrite(h,"schema_version=1.0");
   FileWrite(h,"stage=07");
   FileWrite(h,"proof_type=CROSS_PROCESS_RECONNECT_SEQUENCE_RECOVERY");
   FileWrite(h,"phase="+IntegerToString(phase));
   FileWrite(h,"stream_id=77");
   FileWrite(h,"boot_id="+IntegerToString((long)boot_id));
   FileWrite(h,"last_mt5_sequence="+IntegerToString((long)last_mt5_sequence));
   FileWrite(h,"last_python_sequence="+IntegerToString((long)last_python_sequence));
   FileWrite(h,"communication_ready=1");
   FileWrite(h,"live_risk_ready=0");
   FileWrite(h,"detail="+detail);
   FileWrite(h,"result="+result);
   FileClose(h);
  }

bool NextExpected(CKatWireSequence &sequence,
                  const ulong expected,
                  ulong &actual)
  {
   actual=0;
   if(!sequence.Next(0,actual))
      return(false);
   return(actual==expected);
  }

bool RunCycle(CKatZmqDealerByteTransport &transport,
              CKatWireSequence &sequence,
              const int phase,
              const ulong boot_id,
              const ulong expected_heartbeat_sequence,
              const ulong expected_hello_sequence,
              const ulong expected_ack_sequence,
              const ulong expected_snapshot_request_sequence,
              const ulong expected_begin_sequence,
              const ulong expected_chunk_sequence,
              const ulong expected_commit_sequence,
              const ulong expected_reconcile_request_sequence,
              const ulong expected_report_sequence,
              const ulong expected_ready_heartbeat_sequence,
              const ulong expected_final_sequence,
              const ulong latest_consumed_before_cycle,
              ulong &last_mt5_sequence,
              ulong &last_python_sequence,
              string &error)
  {
   error="";
   const ulong stream_id=77;

   ulong seq=0;
   if(!NextExpected(sequence,expected_heartbeat_sequence,seq))
     {
      error="initial heartbeat sequence mismatch";
      return(false);
     }

   uchar heartbeat[];
   if(!Kat1BuildHeartbeat(seq,
                          1000000000+(ulong)phase*1000000000,
                          stream_id,
                          boot_id,
                          1000+(ulong)phase*1000,
                          seq,
                          latest_consumed_before_cycle,
                          0,
                          0,
                          1000000000+(ulong)phase*1000000000,
                          1,
                          heartbeat,
                          error) ||
      !SendWithDeadline(transport,heartbeat,InpTimeoutMs))
     {
      error="initial heartbeat send failed";
      return(false);
     }
   last_mt5_sequence=seq;

   uchar hello_frame[];
   if(!ReceiveWithDeadline(transport,hello_frame,InpTimeoutMs))
     {
      error="HELLO receive timed out";
      return(false);
     }

   SKat1Header hello_header;
   SKat1HelloMessage hello;
   if(!Kat1ValidateFrame(hello_frame,hello_header,error) ||
      hello_header.message_type!=KAT1_MSG_HELLO ||
      hello_header.sequence!=expected_hello_sequence ||
      hello_header.stream_id!=stream_id ||
      hello_header.boot_id!=boot_id ||
      !Kat1DecodeHello(hello_frame,hello,error) ||
      hello.requested_execution_mode!=0)
     {
      error="HELLO validation failed";
      return(false);
     }
   last_python_sequence=hello_header.sequence;

   uchar account_id[];
   if(!Kat1BuildAccountId("Katarina-CI",123456,account_id,error))
      return(false);

   uchar source_hash[];
   ArrayResize(source_hash,32);
   ArrayInitialize(source_hash,0x22);

   if(!NextExpected(sequence,expected_ack_sequence,seq))
     {
      error="HELLO_ACK sequence mismatch";
      return(false);
     }

   uchar hello_ack[];
   if(!Kat1BuildHelloAck(seq,
                         1100000000+(ulong)phase*1000000000,
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
                         error) ||
      !SendWithDeadline(transport,hello_ack,InpTimeoutMs))
     {
      error="HELLO_ACK send failed";
      return(false);
     }
   last_mt5_sequence=seq;

   uchar snapshot_request_frame[];
   if(!ReceiveWithDeadline(transport,snapshot_request_frame,InpTimeoutMs))
     {
      error="SNAPSHOT_REQUEST receive timed out";
      return(false);
     }

   SKat1Header snapshot_request_header;
   SKat1SnapshotRequest snapshot_request;
   if(!Kat1ValidateFrame(snapshot_request_frame,snapshot_request_header,error) ||
      snapshot_request_header.message_type!=KAT1_MSG_SNAPSHOT_REQUEST ||
      snapshot_request_header.sequence!=expected_snapshot_request_sequence ||
      snapshot_request_header.boot_id!=boot_id ||
      !Kat1DecodeSnapshotRequest(snapshot_request_frame,snapshot_request,error))
     {
      error="SNAPSHOT_REQUEST validation failed";
      return(false);
     }
   last_python_sequence=snapshot_request_header.sequence;

   uchar snapshot_id[];
   ArrayResize(snapshot_id,16);
   ArrayInitialize(snapshot_id,(uchar)(0x30+phase));

   uchar body[];
   if(!Kat1Utf8Bytes(phase==1 ?
                     "stage07-reconnect-phase1" :
                     "stage07-reconnect-phase2",
                     body))
     {
      error="snapshot body encoding failed";
      return(false);
     }

   uchar records[];
   ArrayResize(records,0);
   if(!Kat1AppendEmbeddedRecord(records,3,1,body,error))
      return(false);

   if(!NextExpected(sequence,expected_begin_sequence,seq))
     {
      error="SNAPSHOT_BEGIN sequence mismatch";
      return(false);
     }
   uchar begin[];
   if(!Kat1BuildSnapshotBegin(seq,
                              2000000000+(ulong)phase*1000000000,
                              stream_id,
                              boot_id,
                              snapshot_id,
                              seq,
                              10+(ulong)phase,
                              1,
                              1,
                              (uint)ArraySize(records),
                              (uint)snapshot_request.requested_record_mask,
                              1,
                              begin,
                              error) ||
      !SendWithDeadline(transport,begin,InpTimeoutMs))
      return(false);
   last_mt5_sequence=seq;

   if(!NextExpected(sequence,expected_chunk_sequence,seq))
     {
      error="SNAPSHOT_CHUNK sequence mismatch";
      return(false);
     }
   uchar chunk[];
   if(!Kat1BuildSnapshotChunk(seq,
                              2100000000+(ulong)phase*1000000000,
                              stream_id,
                              boot_id,
                              snapshot_id,
                              0,
                              1,
                              records,
                              chunk,
                              error) ||
      !SendWithDeadline(transport,chunk,InpTimeoutMs))
      return(false);
   last_mt5_sequence=seq;

   if(!NextExpected(sequence,expected_commit_sequence,seq))
     {
      error="SNAPSHOT_COMMIT sequence mismatch";
      return(false);
     }
   uchar commit[];
   if(!Kat1BuildSnapshotCommit(seq,
                               2200000000+(ulong)phase*1000000000,
                               stream_id,
                               boot_id,
                               snapshot_id,
                               1,
                               1,
                               (uint)ArraySize(records),
                               Kat1Crc32c(records,ArraySize(records)),
                               seq,
                               10+(ulong)phase,
                               commit,
                               error) ||
      !SendWithDeadline(transport,commit,InpTimeoutMs))
      return(false);
   last_mt5_sequence=seq;

   uchar reconcile_request_frame[];
   if(!ReceiveWithDeadline(transport,reconcile_request_frame,InpTimeoutMs))
     {
      error="RECONCILE_REQUEST receive timed out";
      return(false);
     }

   SKat1Header reconcile_header;
   SKat1ReconcileRequest reconcile;
   if(!Kat1ValidateFrame(reconcile_request_frame,reconcile_header,error) ||
      reconcile_header.message_type!=KAT1_MSG_RECONCILE_REQUEST ||
      reconcile_header.sequence!=expected_reconcile_request_sequence ||
      reconcile_header.boot_id!=boot_id ||
      !Kat1DecodeReconcileRequest(reconcile_request_frame,reconcile,error))
     {
      error="RECONCILE_REQUEST validation failed";
      return(false);
     }
   last_python_sequence=reconcile_header.sequence;

   uchar request_id[];
   uchar request_account_id[];
   uchar request_snapshot_id[];
   ArrayResize(request_id,16);
   ArrayResize(request_account_id,16);
   ArrayResize(request_snapshot_id,16);
   for(int i=0;i<16;i++)
     {
      request_id[i]=reconcile.request_id[i];
      request_account_id[i]=reconcile.account_id[i];
      request_snapshot_id[i]=reconcile.snapshot_id[i];
     }

   if(!Kat1Id128Equal(request_account_id,account_id) ||
      !Kat1Id128Equal(request_snapshot_id,snapshot_id))
     {
      error="RECONCILE_REQUEST binding mismatch";
      return(false);
     }

   if(!NextExpected(sequence,expected_report_sequence,seq))
     {
      error="RECONCILE_REPORT sequence mismatch";
      return(false);
     }

   uchar discrepancies[];
   ArrayResize(discrepancies,0);
   uchar report[];
   if(!Kat1BuildReconcileReport(seq,
                                2300000000+(ulong)phase*1000000000,
                                stream_id,
                                boot_id,
                                request_id,
                                snapshot_id,
                                expected_commit_sequence,
                                expected_commit_sequence,
                                0,
                                0,
                                0,
                                discrepancies,
                                2,
                                report,
                                error) ||
      !SendWithDeadline(transport,report,InpTimeoutMs))
      return(false);
   last_mt5_sequence=seq;

   uchar ready_heartbeat[];
   if(!ReceiveWithDeadline(transport,ready_heartbeat,InpTimeoutMs))
     {
      error="READY heartbeat receive timed out";
      return(false);
     }

   SKat1Header ready_header;
   if(!Kat1ValidateFrame(ready_heartbeat,ready_header,error) ||
      ready_header.message_type!=KAT1_MSG_HEARTBEAT ||
      ready_header.sequence!=expected_ready_heartbeat_sequence ||
      ready_header.boot_id!=boot_id)
     {
      error="READY heartbeat validation failed";
      return(false);
     }
   last_python_sequence=ready_header.sequence;

   if(!NextExpected(sequence,expected_final_sequence,seq))
     {
      error="final MT5 heartbeat sequence mismatch";
      return(false);
     }

   uchar final_heartbeat[];
   if(!Kat1BuildHeartbeat(seq,
                          2400000000+(ulong)phase*1000000000,
                          stream_id,
                          boot_id,
                          2400+(ulong)phase*1000,
                          seq,
                          ready_header.sequence,
                          0,
                          0,
                          2400000000+(ulong)phase*1000000000,
                          1,
                          final_heartbeat,
                          error) ||
      !SendWithDeadline(transport,final_heartbeat,InpTimeoutMs))
     {
      error="final heartbeat send failed";
      return(false);
     }

   last_mt5_sequence=seq;
   return(true);
  }

void OnStart(void)
  {
   const string marker=ReadCommonText(KAT_RECONNECT_MARKER);
   const int phase=(marker=="" ? 1 : 2);
   const ulong boot_id=(phase==1 ? 88 : 89);

   CKatWireSequence sequence;
   if(!sequence.Init(77,"MT5_TO_PYTHON"))
     {
      WriteResult("FAIL","wire sequence init failed",phase,boot_id,0,0);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   if(phase==1)
     {
      sequence.DeletePersistenceForTest();
      if(!sequence.Init(77,"MT5_TO_PYTHON"))
        {
         WriteResult("FAIL","clean wire sequence init failed",1,88,0,0);
         if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
            TerminalClose(7);
         return;
        }
     }
   else
     {
      if(marker!="phase1=7,python=4" || sequence.Last()!=7)
        {
         WriteResult("FAIL",
                     "phase2 did not recover phase1 sequence state",
                     2,
                     89,
                     sequence.Last(),
                     0);
         if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
            TerminalClose(7);
         return;
        }
     }

   CKatZmqDealerByteTransport transport;
   if(!transport.Start(InpEndpoint,"kat-stage07-reconnect",64,64))
     {
      WriteResult("FAIL","ZeroMQ transport start failed",phase,boot_id,sequence.Last(),0);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   Sleep(200);

   ulong last_mt5=sequence.Last();
   ulong last_python=(phase==1 ? 0 : 4);
   string error="";

   const bool ok=(phase==1 ?
      RunCycle(transport,
               sequence,
               1,
               88,
               1,1,2,2,3,4,5,3,6,4,7,0,
               last_mt5,last_python,error)
      :
      RunCycle(transport,
               sequence,
               2,
               89,
               8,5,9,6,10,11,12,7,13,8,14,4,
               last_mt5,last_python,error));

   Sleep(100);
   transport.Stop();

   if(!ok)
     {
      WriteResult("FAIL",error,phase,boot_id,last_mt5,last_python);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   if(phase==1)
     {
      if(last_mt5!=7 || last_python!=4 ||
         !WriteCommonText(KAT_RECONNECT_MARKER,"phase1=7,python=4"))
        {
         WriteResult("FAIL","phase1 persistence marker failed",1,88,last_mt5,last_python);
         if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
            TerminalClose(7);
         return;
        }

      WriteResult("PHASE1_PASS",
                  "phase1 READY; terminal may restart",
                  1,88,last_mt5,last_python);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(0);
      return;
     }

   if(last_mt5!=14 || last_python!=8)
     {
      WriteResult("FAIL","phase2 final sequence mismatch",2,89,last_mt5,last_python);
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   FileDelete(KAT_RECONNECT_MARKER,FILE_COMMON);
   sequence.DeletePersistenceForTest();

   WriteResult("PASS",
               "same stream survived new boot and full re-handshake/recovery without sequence reuse",
               2,89,last_mt5,last_python);
   if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
      TerminalClose(0);
  }
