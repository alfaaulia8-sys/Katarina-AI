#ifndef __KATARINA_STAGE07_KAT1_RECOVERY_MESSAGES_MQH__
#define __KATARINA_STAGE07_KAT1_RECOVERY_MESSAGES_MQH__

#include <Katarina/Stage07/Kat1SystemMessages.mqh>

#define KAT1_MSG_SNAPSHOT_REQUEST  10
#define KAT1_MSG_SNAPSHOT_BEGIN    11
#define KAT1_MSG_SNAPSHOT_CHUNK    12
#define KAT1_MSG_SNAPSHOT_COMMIT   13
#define KAT1_MSG_SNAPSHOT_ABORT    14
#define KAT1_MSG_RECONCILE_REQUEST 312
#define KAT1_MSG_RECONCILE_REPORT  313

struct SKat1SnapshotRequest
  {
   uchar request_id[16];
   ulong requested_record_mask;
   ulong after_execution_cursor;
   uint  max_chunk_bytes;
  };

struct SKat1ReconcileRequest
  {
   uchar request_id[16];
   uchar account_id[16];
   uchar snapshot_id[16];
   ulong after_event_cursor;
   uint  scope_flags;
  };

bool Kat1CopyId128(const uchar &source[],
                   const int source_offset,
                   uchar &target[])
  {
   if(!Kat1RangeOk(ArraySize(source),source_offset,16))
      return(false);
   ArrayResize(target,16);
   for(int i=0;i<16;i++)
      target[i]=source[source_offset+i];
   return(true);
  }

bool Kat1WriteId128(uchar &target[],
                    const int offset,
                    const uchar &value[])
  {
   if(ArraySize(value)!=16 ||
      !Kat1RangeOk(ArraySize(target),offset,16))
      return(false);
   for(int i=0;i<16;i++)
      target[offset+i]=value[i];
   return(true);
  }

bool Kat1Id128Equal(const uchar &left[],
                    const uchar &right[])
  {
   if(ArraySize(left)!=16 || ArraySize(right)!=16)
      return(false);
   for(int i=0;i<16;i++)
     {
      if(left[i]!=right[i])
         return(false);
     }
   return(true);
  }

bool Kat1AppendRawBytes(uchar &target[],
                        const uchar &source[])
  {
   const int offset=ArraySize(target);
   const int count=ArraySize(source);
   if(ArrayResize(target,offset+count)!=(offset+count))
      return(false);
   for(int i=0;i<count;i++)
      target[offset+i]=source[i];
   return(true);
  }

bool Kat1AppendEmbeddedRecord(uchar &records[],
                              const ushort record_type,
                              const ushort schema_version,
                              const uchar &body[],
                              string &error)
  {
   error="";
   const int body_length=ArraySize(body);
   if(body_length<0 || body_length>60000)
     {
      error="embedded record body exceeds Stage-07 maximum";
      return(false);
     }

   const int offset=ArraySize(records);
   if(ArrayResize(records,offset+8+body_length)!=(offset+8+body_length))
     {
      error="embedded record allocation failed";
      return(false);
     }

   Kat1WriteU16LE(records,offset,record_type);
   Kat1WriteU16LE(records,offset+2,schema_version);
   Kat1WriteU32LE(records,offset+4,(uint)body_length);
   for(int i=0;i<body_length;i++)
      records[offset+8+i]=body[i];

   return(true);
  }

bool Kat1ValidateLen32Records(const uchar &records[],
                              const uint expected_count,
                              string &error)
  {
   error="";
   int cursor=0;
   uint count=0;
   const int size=ArraySize(records);

   while(cursor<size)
     {
      if(cursor+4>size)
        {
         error="truncated len32 record header";
         return(false);
        }

      const uint body_length=Kat1ReadU32LE(records,cursor);
      cursor+=4;

      if(body_length>60000 || cursor+(int)body_length>size)
        {
         error="invalid len32 record body";
         return(false);
        }

      cursor+=(int)body_length;
      count++;
     }

   if(cursor!=size || count!=expected_count)
     {
      error="len32 record count/length mismatch";
      return(false);
     }

   return(true);
  }

bool Kat1DecodeSnapshotRequest(const uchar &frame[],
                               SKat1SnapshotRequest &request,
                               string &error)
  {
   SKat1Header header;
   if(!Kat1ValidateFrame(frame,header,error))
      return(false);

   if(header.message_type!=KAT1_MSG_SNAPSHOT_REQUEST ||
      header.schema_version!=1 ||
      header.block_length!=40)
     {
      error="frame is not SNAPSHOT_REQUEST v1";
      return(false);
     }

   const ushort required=(KAT1_FLAG_CRC32C_PRESENT|
                          KAT1_FLAG_CRITICAL_MESSAGE|
                          KAT1_FLAG_SNAPSHOT_TRANSACTION);
   if((header.flags & required)!=required)
     {
      error="SNAPSHOT_REQUEST flags are invalid";
      return(false);
     }

   const int root=KAT1_HEADER_BYTES;
   uchar id[];
   if(!Kat1CopyId128(frame,root,id))
     {
      error="SNAPSHOT_REQUEST request_id truncated";
      return(false);
     }
   for(int i=0;i<16;i++)
      request.request_id[i]=id[i];

   request.requested_record_mask=Kat1ReadU64LE(frame,root+16);
   request.after_execution_cursor=Kat1ReadU64LE(frame,root+24);
   request.max_chunk_bytes=Kat1ReadU32LE(frame,root+32);

   if(Kat1ReadU32LE(frame,root+36)!=0)
     {
      error="SNAPSHOT_REQUEST reserved field is nonzero";
      return(false);
     }

   if(request.max_chunk_bytes==0 || request.max_chunk_bytes>60000)
     {
      error="SNAPSHOT_REQUEST max_chunk_bytes is invalid";
      return(false);
     }

   return(true);
  }

bool Kat1BuildSnapshotRequest(const ulong sequence,
                              const ulong source_time_ns,
                              const ulong stream_id,
                              const ulong boot_id,
                              const uchar &request_id[],
                              const ulong requested_record_mask,
                              const ulong after_execution_cursor,
                              const uint max_chunk_bytes,
                              uchar &frame[],
                              string &error)
  {
   if(ArraySize(request_id)!=16 ||
      max_chunk_bytes==0 ||
      max_chunk_bytes>60000)
     {
      error="invalid SNAPSHOT_REQUEST argument";
      return(false);
     }

   uchar payload[];
   ArrayResize(payload,40);
   ArrayInitialize(payload,0);

   if(!Kat1WriteId128(payload,0,request_id))
     {
      error="SNAPSHOT_REQUEST request_id write failed";
      return(false);
     }

   Kat1WriteU64LE(payload,16,requested_record_mask);
   Kat1WriteU64LE(payload,24,after_execution_cursor);
   Kat1WriteU32LE(payload,32,max_chunk_bytes);

   return(Kat1BuildFrame(KAT1_MSG_SNAPSHOT_REQUEST,
                         1,
                         40,
                         KAT1_FLAG_CRC32C_PRESENT|
                         KAT1_FLAG_CRITICAL_MESSAGE|
                         KAT1_FLAG_SNAPSHOT_TRANSACTION,
                         sequence,
                         source_time_ns,
                         stream_id,
                         boot_id,
                         payload,
                         frame,
                         error));
  }

bool Kat1BuildSnapshotBegin(const ulong sequence,
                            const ulong source_time_ns,
                            const ulong stream_id,
                            const ulong boot_id,
                            const uchar &snapshot_id[],
                            const ulong base_sequence,
                            const ulong account_revision,
                            const uint expected_chunk_count,
                            const uint expected_record_count,
                            const uint expected_total_payload_bytes,
                            const uint record_mask,
                            const uint spec_revision_watermark,
                            uchar &frame[],
                            string &error)
  {
   if(ArraySize(snapshot_id)!=16)
     {
      error="SNAPSHOT_BEGIN snapshot_id must be 16 bytes";
      return(false);
     }

   uchar payload[];
   ArrayResize(payload,56);
   ArrayInitialize(payload,0);
   Kat1WriteId128(payload,0,snapshot_id);
   Kat1WriteU64LE(payload,16,base_sequence);
   Kat1WriteU64LE(payload,24,account_revision);
   Kat1WriteU32LE(payload,32,expected_chunk_count);
   Kat1WriteU32LE(payload,36,expected_record_count);
   Kat1WriteU32LE(payload,40,expected_total_payload_bytes);
   Kat1WriteU32LE(payload,44,record_mask);
   Kat1WriteU32LE(payload,48,spec_revision_watermark);

   return(Kat1BuildFrame(KAT1_MSG_SNAPSHOT_BEGIN,
                         1,
                         56,
                         KAT1_FLAG_CRC32C_PRESENT|
                         KAT1_FLAG_CRITICAL_MESSAGE|
                         KAT1_FLAG_SNAPSHOT_TRANSACTION,
                         sequence,
                         source_time_ns,
                         stream_id,
                         boot_id,
                         payload,
                         frame,
                         error));
  }

bool Kat1BuildSnapshotChunk(const ulong sequence,
                            const ulong source_time_ns,
                            const ulong stream_id,
                            const ulong boot_id,
                            const uchar &snapshot_id[],
                            const uint chunk_index,
                            const uint record_count,
                            const uchar &records[],
                            uchar &frame[],
                            string &error)
  {
   if(ArraySize(snapshot_id)!=16 || ArraySize(records)>60000)
     {
      error="invalid SNAPSHOT_CHUNK argument";
      return(false);
     }

   uchar payload[];
   ArrayResize(payload,32);
   ArrayInitialize(payload,0);
   Kat1WriteId128(payload,0,snapshot_id);
   Kat1WriteU32LE(payload,16,chunk_index);
   Kat1WriteU32LE(payload,20,record_count);
   Kat1WriteU32LE(payload,24,(uint)ArraySize(records));
   Kat1WriteU32LE(payload,28,Kat1Crc32c(records,ArraySize(records)));

   if(!Kat1AppendRawBytes(payload,records))
     {
      error="SNAPSHOT_CHUNK payload allocation failed";
      return(false);
     }

   return(Kat1BuildFrame(KAT1_MSG_SNAPSHOT_CHUNK,
                         1,
                         32,
                         KAT1_FLAG_CRC32C_PRESENT|
                         KAT1_FLAG_CRITICAL_MESSAGE|
                         KAT1_FLAG_SNAPSHOT_TRANSACTION,
                         sequence,
                         source_time_ns,
                         stream_id,
                         boot_id,
                         payload,
                         frame,
                         error));
  }

bool Kat1BuildSnapshotCommit(const ulong sequence,
                             const ulong source_time_ns,
                             const ulong stream_id,
                             const ulong boot_id,
                             const uchar &snapshot_id[],
                             const uint chunk_count,
                             const uint record_count,
                             const uint total_payload_bytes,
                             const uint aggregate_crc32c,
                             const ulong sequence_watermark,
                             const ulong account_revision,
                             uchar &frame[],
                             string &error)
  {
   if(ArraySize(snapshot_id)!=16)
     {
      error="SNAPSHOT_COMMIT snapshot_id must be 16 bytes";
      return(false);
     }

   uchar payload[];
   ArrayResize(payload,48);
   ArrayInitialize(payload,0);
   Kat1WriteId128(payload,0,snapshot_id);
   Kat1WriteU32LE(payload,16,chunk_count);
   Kat1WriteU32LE(payload,20,record_count);
   Kat1WriteU32LE(payload,24,total_payload_bytes);
   Kat1WriteU32LE(payload,28,aggregate_crc32c);
   Kat1WriteU64LE(payload,32,sequence_watermark);
   Kat1WriteU64LE(payload,40,account_revision);

   return(Kat1BuildFrame(KAT1_MSG_SNAPSHOT_COMMIT,
                         1,
                         48,
                         KAT1_FLAG_CRC32C_PRESENT|
                         KAT1_FLAG_CRITICAL_MESSAGE|
                         KAT1_FLAG_SNAPSHOT_TRANSACTION,
                         sequence,
                         source_time_ns,
                         stream_id,
                         boot_id,
                         payload,
                         frame,
                         error));
  }

bool Kat1DecodeReconcileRequest(const uchar &frame[],
                                SKat1ReconcileRequest &request,
                                string &error)
  {
   SKat1Header header;
   if(!Kat1ValidateFrame(frame,header,error))
      return(false);

   if(header.message_type!=KAT1_MSG_RECONCILE_REQUEST ||
      header.schema_version!=1 ||
      header.block_length!=64)
     {
      error="frame is not RECONCILE_REQUEST v1";
      return(false);
     }

   const ushort required=(KAT1_FLAG_CRC32C_PRESENT|
                          KAT1_FLAG_CRITICAL_MESSAGE);
   if((header.flags & required)!=required ||
      (header.flags & KAT1_FLAG_SNAPSHOT_TRANSACTION)!=0)
     {
      error="RECONCILE_REQUEST flags are invalid";
      return(false);
     }

   const int root=KAT1_HEADER_BYTES;
   uchar id[];
   if(!Kat1CopyId128(frame,root,id))
      return(false);
   for(int i=0;i<16;i++)
      request.request_id[i]=id[i];

   if(!Kat1CopyId128(frame,root+16,id))
      return(false);
   for(int i=0;i<16;i++)
      request.account_id[i]=id[i];

   if(!Kat1CopyId128(frame,root+32,id))
      return(false);
   for(int i=0;i<16;i++)
      request.snapshot_id[i]=id[i];

   request.after_event_cursor=Kat1ReadU64LE(frame,root+48);
   request.scope_flags=Kat1ReadU32LE(frame,root+56);

   if(Kat1ReadU32LE(frame,root+60)!=0)
     {
      error="RECONCILE_REQUEST reserved field is nonzero";
      return(false);
     }

   return(true);
  }

bool Kat1BuildReconcileRequest(const ulong sequence,
                               const ulong source_time_ns,
                               const ulong stream_id,
                               const ulong boot_id,
                               const uchar &request_id[],
                               const uchar &account_id[],
                               const uchar &snapshot_id[],
                               const ulong after_event_cursor,
                               const uint scope_flags,
                               uchar &frame[],
                               string &error)
  {
   if(ArraySize(request_id)!=16 ||
      ArraySize(account_id)!=16 ||
      ArraySize(snapshot_id)!=16)
     {
      error="invalid RECONCILE_REQUEST identity";
      return(false);
     }

   uchar payload[];
   ArrayResize(payload,64);
   ArrayInitialize(payload,0);
   Kat1WriteId128(payload,0,request_id);
   Kat1WriteId128(payload,16,account_id);
   Kat1WriteId128(payload,32,snapshot_id);
   Kat1WriteU64LE(payload,48,after_event_cursor);
   Kat1WriteU32LE(payload,56,scope_flags);

   return(Kat1BuildFrame(KAT1_MSG_RECONCILE_REQUEST,
                         1,
                         64,
                         KAT1_FLAG_CRC32C_PRESENT|
                         KAT1_FLAG_CRITICAL_MESSAGE,
                         sequence,
                         source_time_ns,
                         stream_id,
                         boot_id,
                         payload,
                         frame,
                         error));
  }

bool Kat1BuildReconcileReport(const ulong sequence,
                              const ulong source_time_ns,
                              const ulong stream_id,
                              const ulong boot_id,
                              const uchar &request_id[],
                              const uchar &snapshot_id[],
                              const ulong first_event_cursor,
                              const ulong last_event_cursor,
                              const uint position_count,
                              const uint order_count,
                              const uint discrepancy_count,
                              const uchar &discrepancy_records[],
                              const uchar recovery_state,
                              uchar &frame[],
                              string &error)
  {
   if(ArraySize(request_id)!=16 || ArraySize(snapshot_id)!=16)
     {
      error="invalid RECONCILE_REPORT identity";
      return(false);
     }

   if(!Kat1ValidateLen32Records(discrepancy_records,
                                discrepancy_count,
                                error))
      return(false);

   uchar payload[];
   ArrayResize(payload,64);
   ArrayInitialize(payload,0);
   Kat1WriteId128(payload,0,request_id);
   Kat1WriteId128(payload,16,snapshot_id);
   Kat1WriteU64LE(payload,32,first_event_cursor);
   Kat1WriteU64LE(payload,40,last_event_cursor);
   Kat1WriteU32LE(payload,48,position_count);
   Kat1WriteU32LE(payload,52,order_count);
   Kat1WriteU32LE(payload,56,discrepancy_count);
   payload[60]=recovery_state;

   if(!Kat1AppendRawBytes(payload,discrepancy_records))
     {
      error="RECONCILE_REPORT payload allocation failed";
      return(false);
     }

   return(Kat1BuildFrame(KAT1_MSG_RECONCILE_REPORT,
                         1,
                         64,
                         KAT1_FLAG_CRC32C_PRESENT|
                         KAT1_FLAG_CRITICAL_MESSAGE,
                         sequence,
                         source_time_ns,
                         stream_id,
                         boot_id,
                         payload,
                         frame,
                         error));
  }

#endif
