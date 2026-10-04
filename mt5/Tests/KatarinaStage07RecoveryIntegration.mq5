#property strict
#property script_show_inputs

#include <Katarina/Stage07/ZmqDealerTransport.mqh>
#include <Katarina/Stage07/Kat1SystemMessages.mqh>
#include <Katarina/Stage07/Kat1RecoveryMessages.mqh>
#include <Katarina/Stage07/IdentityV1.mqh>

input string InpEndpoint="tcp://127.0.0.1:5570";
input int InpTimeoutMs=10000;

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

void WriteEvidence(const bool passed,
                   const string detail)
  {
   const int h=FileOpen("Katarina_Stage07_recovery_result.txt",
                        FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE)
      return;

   FileWrite(h,"schema_version=1.0");
   FileWrite(h,"stage=07");
   FileWrite(h,"proof_type=MQL5_PYTHON_SNAPSHOT_RECONCILIATION");
   FileWrite(h,"stream_id=77");
   FileWrite(h,"boot_id=88");
   FileWrite(h,"snapshot_chunks=1");
   FileWrite(h,"snapshot_records=1");
   FileWrite(h,"request_byte_equality=1");
   FileWrite(h,"reconcile_request_byte_equality=1");
   FileWrite(h,"clean_reconciliation=1");
   FileWrite(h,"final_expected_state=READY");
   FileWrite(h,"live_risk_ready=0");
   FileWrite(h,"detail="+detail);
   FileWrite(h,(passed ? "result=PASS" : "result=FAIL"));
   FileClose(h);
  }

void Fail(CKatZmqDealerByteTransport &transport,
          const string detail)
  {
   Print("FAIL: ",detail);
   WriteEvidence(false,detail);
   transport.Stop();
   if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
      TerminalClose(7);
  }

void Finish(CKatZmqDealerByteTransport &transport)
  {
   WriteEvidence(true,
                 "snapshot/reconciliation cross-language transaction PASS");
   Sleep(100);
   transport.Stop();
   if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
      TerminalClose(0);
  }

void OnStart(void)
  {
   const ulong stream_id=77;
   const ulong boot_id=88;

   CKatZmqDealerByteTransport transport;
   if(!transport.Start(InpEndpoint,"kat-stage07-recovery",64,64))
     {
      WriteEvidence(false,"transport start failed");
      if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
         TerminalClose(7);
      return;
     }

   Sleep(150);

   string error="";
   uchar heartbeat[];
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
                          error) ||
      !SendWithDeadline(transport,heartbeat,InpTimeoutMs))
     {
      Fail(transport,"initial HEARTBEAT failed: "+error);
      return;
     }

   uchar hello_frame[];
   if(!ReceiveWithDeadline(transport,hello_frame,InpTimeoutMs))
     {
      Fail(transport,"HELLO receive timed out");
      return;
     }

   SKat1HelloMessage hello;
   if(!Kat1DecodeHello(hello_frame,hello,error) ||
      hello.requested_execution_mode!=0)
     {
      Fail(transport,"HELLO decode/read-only validation failed: "+error);
      return;
     }

   uchar account_id[];
   if(!Kat1BuildAccountId("Katarina-CI",123456,account_id,error))
     {
      Fail(transport,"account_id build failed: "+error);
      return;
     }

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
                         error) ||
      !SendWithDeadline(transport,hello_ack,InpTimeoutMs))
     {
      Fail(transport,"HELLO_ACK failed: "+error);
      return;
     }

   uchar snapshot_request_frame[];
   if(!ReceiveWithDeadline(transport,snapshot_request_frame,InpTimeoutMs))
     {
      Fail(transport,"SNAPSHOT_REQUEST receive timed out");
      return;
     }

   SKat1Header snapshot_request_header;
   if(!Kat1ValidateFrame(snapshot_request_frame,
                         snapshot_request_header,
                         error))
     {
      Fail(transport,"SNAPSHOT_REQUEST frame invalid: "+error);
      return;
     }

   SKat1SnapshotRequest snapshot_request;
   if(!Kat1DecodeSnapshotRequest(snapshot_request_frame,
                                 snapshot_request,
                                 error))
     {
      Fail(transport,"SNAPSHOT_REQUEST decode failed: "+error);
      return;
     }

   uchar snapshot_request_id[];
   ArrayResize(snapshot_request_id,16);
   for(int i=0;i<16;i++)
      snapshot_request_id[i]=snapshot_request.request_id[i];

   uchar rebuilt_snapshot_request[];
   if(!Kat1BuildSnapshotRequest(snapshot_request_header.sequence,
                                snapshot_request_header.source_time_ns,
                                snapshot_request_header.stream_id,
                                snapshot_request_header.boot_id,
                                snapshot_request_id,
                                snapshot_request.requested_record_mask,
                                snapshot_request.after_execution_cursor,
                                snapshot_request.max_chunk_bytes,
                                rebuilt_snapshot_request,
                                error) ||
      !Kat1BytesEqual(snapshot_request_frame,
                      rebuilt_snapshot_request))
     {
      Fail(transport,"SNAPSHOT_REQUEST cross-language byte equality failed");
      return;
     }

   uchar snapshot_id[];
   ArrayResize(snapshot_id,16);
   ArrayInitialize(snapshot_id,0x33);

   uchar record_body[];
   if(!Kat1Utf8Bytes("stage07-synthetic-account-state",record_body))
     {
      Fail(transport,"snapshot record UTF-8 conversion failed");
      return;
     }

   uchar records[];
   ArrayResize(records,0);
   if(!Kat1AppendEmbeddedRecord(records,
                                3,
                                1,
                                record_body,
                                error))
     {
      Fail(transport,"snapshot record framing failed: "+error);
      return;
     }

   if((uint)ArraySize(records)>snapshot_request.max_chunk_bytes)
     {
      Fail(transport,"snapshot record exceeds requested max_chunk_bytes");
      return;
     }

   uchar begin[];
   if(!Kat1BuildSnapshotBegin(3,
                              2000000000,
                              stream_id,
                              boot_id,
                              snapshot_id,
                              3,
                              10,
                              1,
                              1,
                              (uint)ArraySize(records),
                              (uint)snapshot_request.requested_record_mask,
                              1,
                              begin,
                              error) ||
      !SendWithDeadline(transport,begin,InpTimeoutMs))
     {
      Fail(transport,"SNAPSHOT_BEGIN failed: "+error);
      return;
     }

   uchar chunk[];
   if(!Kat1BuildSnapshotChunk(4,
                              2100000000,
                              stream_id,
                              boot_id,
                              snapshot_id,
                              0,
                              1,
                              records,
                              chunk,
                              error) ||
      !SendWithDeadline(transport,chunk,InpTimeoutMs))
     {
      Fail(transport,"SNAPSHOT_CHUNK failed: "+error);
      return;
     }

   uchar commit[];
   if(!Kat1BuildSnapshotCommit(5,
                               2200000000,
                               stream_id,
                               boot_id,
                               snapshot_id,
                               1,
                               1,
                               (uint)ArraySize(records),
                               Kat1Crc32c(records,ArraySize(records)),
                               5,
                               10,
                               commit,
                               error) ||
      !SendWithDeadline(transport,commit,InpTimeoutMs))
     {
      Fail(transport,"SNAPSHOT_COMMIT failed: "+error);
      return;
     }

   uchar reconcile_request_frame[];
   if(!ReceiveWithDeadline(transport,reconcile_request_frame,InpTimeoutMs))
     {
      Fail(transport,"RECONCILE_REQUEST receive timed out");
      return;
     }

   SKat1Header reconcile_header;
   if(!Kat1ValidateFrame(reconcile_request_frame,
                         reconcile_header,
                         error))
     {
      Fail(transport,"RECONCILE_REQUEST frame invalid: "+error);
      return;
     }

   SKat1ReconcileRequest reconcile;
   if(!Kat1DecodeReconcileRequest(reconcile_request_frame,
                                  reconcile,
                                  error))
     {
      Fail(transport,"RECONCILE_REQUEST decode failed: "+error);
      return;
     }

   uchar reconcile_request_id[];
   uchar reconcile_account_id[];
   uchar reconcile_snapshot_id[];
   ArrayResize(reconcile_request_id,16);
   ArrayResize(reconcile_account_id,16);
   ArrayResize(reconcile_snapshot_id,16);
   for(int i=0;i<16;i++)
     {
      reconcile_request_id[i]=reconcile.request_id[i];
      reconcile_account_id[i]=reconcile.account_id[i];
      reconcile_snapshot_id[i]=reconcile.snapshot_id[i];
     }

   if(!Kat1Id128Equal(reconcile_account_id,account_id) ||
      !Kat1Id128Equal(reconcile_snapshot_id,snapshot_id))
     {
      Fail(transport,"RECONCILE_REQUEST binding mismatch");
      return;
     }

   uchar rebuilt_reconcile[];
   if(!Kat1BuildReconcileRequest(reconcile_header.sequence,
                                 reconcile_header.source_time_ns,
                                 reconcile_header.stream_id,
                                 reconcile_header.boot_id,
                                 reconcile_request_id,
                                 reconcile_account_id,
                                 reconcile_snapshot_id,
                                 reconcile.after_event_cursor,
                                 reconcile.scope_flags,
                                 rebuilt_reconcile,
                                 error) ||
      !Kat1BytesEqual(reconcile_request_frame,
                      rebuilt_reconcile))
     {
      Fail(transport,"RECONCILE_REQUEST cross-language byte equality failed");
      return;
     }

   uchar discrepancies[];
   ArrayResize(discrepancies,0);

   uchar report[];
   if(!Kat1BuildReconcileReport(6,
                                2300000000,
                                stream_id,
                                boot_id,
                                reconcile_request_id,
                                snapshot_id,
                                5,
                                5,
                                0,
                                0,
                                0,
                                discrepancies,
                                2,
                                report,
                                error) ||
      !SendWithDeadline(transport,report,InpTimeoutMs))
     {
      Fail(transport,"RECONCILE_REPORT failed: "+error);
      return;
     }

   // Python promotes communication to READY only after consuming the clean
   // report, then sends one READY-state heartbeat on its own sequence lane.
   uchar python_heartbeat[];
   if(!ReceiveWithDeadline(transport,python_heartbeat,InpTimeoutMs))
     {
      Fail(transport,"READY-state Python HEARTBEAT timed out");
      return;
     }

   SKat1Header python_heartbeat_header;
   if(!Kat1ValidateFrame(python_heartbeat,
                         python_heartbeat_header,
                         error) ||
      python_heartbeat_header.message_type!=KAT1_MSG_HEARTBEAT ||
      python_heartbeat_header.stream_id!=stream_id ||
      python_heartbeat_header.boot_id!=boot_id)
     {
      Fail(transport,"READY-state Python HEARTBEAT invalid");
      return;
     }

   uchar final_heartbeat[];
   if(!Kat1BuildHeartbeat(7,
                          2400000000,
                          stream_id,
                          boot_id,
                          2400,
                          7,
                          python_heartbeat_header.sequence,
                          0,
                          0,
                          2400000000,
                          1,
                          final_heartbeat,
                          error) ||
      !SendWithDeadline(transport,final_heartbeat,InpTimeoutMs))
     {
      Fail(transport,"final MT5 HEARTBEAT failed: "+error);
      return;
     }

   Finish(transport);
  }
