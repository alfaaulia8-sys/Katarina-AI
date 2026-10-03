#ifndef __KATARINA_STAGE07_KAT1_SYSTEM_MESSAGES_MQH__
#define __KATARINA_STAGE07_KAT1_SYSTEM_MESSAGES_MQH__

#include <Katarina/Stage07/Kat1Codec.mqh>

#define KAT1_MSG_HELLO     1
#define KAT1_MSG_HELLO_ACK 2
#define KAT1_MSG_HEARTBEAT 3

struct SKat1HelloMessage
  {
   uchar client_instance_id[16];
   ulong requested_capability_bits;
   ulong last_known_stream_id;
   ulong last_execution_cursor;
   uchar requested_execution_mode;
   uchar requested_wire_major;
   uchar requested_wire_minor;
   ulong last_snapshot_sequence;
  };

bool Kat1BuildFrame(const ushort message_type,
                    const ushort schema_version,
                    const ushort block_length,
                    const ushort flags,
                    const ulong sequence,
                    const ulong source_time_ns,
                    const ulong stream_id,
                    const ulong boot_id,
                    const uchar &payload[],
                    uchar &frame[],
                    string &error)
  {
   error="";
   const int payload_size=ArraySize(payload);
   if(payload_size<(int)block_length)
     {
      error="payload shorter than root block";
      return(false);
     }

   const int trailer=((flags & KAT1_FLAG_CRC32C_PRESENT)!=0 ? 4 : 0);
   const int frame_length=KAT1_HEADER_BYTES+payload_size+trailer;
   if(frame_length>KAT1_MAX_FRAME_BYTES)
     {
      error="encoded frame exceeds KAT1 maximum";
      return(false);
     }

   SKat1Header header;
   header.wire_major=KAT1_WIRE_MAJOR;
   header.wire_minor=KAT1_WIRE_MINOR;
   header.header_length=KAT1_HEADER_BYTES;
   header.message_type=message_type;
   header.schema_version=schema_version;
   header.block_length=block_length;
   header.flags=flags;
   header.frame_length=(uint)frame_length;
   header.sequence=sequence;
   header.source_time_ns=source_time_ns;
   header.stream_id=stream_id;
   header.boot_id=boot_id;

   uchar encoded_header[];
   if(!Kat1EncodeHeader(header,encoded_header,error))
      return(false);

   ArrayResize(frame,frame_length);
   ArrayInitialize(frame,0);

   for(int i=0;i<KAT1_HEADER_BYTES;i++)
      frame[i]=encoded_header[i];

   for(int i=0;i<payload_size;i++)
      frame[KAT1_HEADER_BYTES+i]=payload[i];

   if(trailer==4)
     {
      const uint crc=Kat1Crc32c(frame,frame_length-4);
      Kat1WriteU32LE(frame,frame_length-4,crc);
     }

   SKat1Header verify;
   if(!Kat1ValidateFrame(frame,verify,error))
     {
      ArrayResize(frame,0);
      return(false);
     }

   return(true);
  }

bool Kat1Utf8Bytes(const string value,
                   uchar &bytes[])
  {
   ArrayResize(bytes,0);
   const int copied=StringToCharArray(value,bytes,0,WHOLE_ARRAY,CP_UTF8);
   if(copied<=0)
      return(value=="");

   int size=ArraySize(bytes);
   if(size>0 && bytes[size-1]==0)
      ArrayResize(bytes,size-1);

   return(true);
  }

bool Kat1AppendU16Utf8(uchar &buffer[],
                       const string value,
                       const int max_bytes,
                       string &error)
  {
   uchar utf8[];
   if(!Kat1Utf8Bytes(value,utf8))
     {
      error="UTF-8 conversion failed";
      return(false);
     }

   const int length=ArraySize(utf8);
   if(length>max_bytes || length>65535)
     {
      error="UTF-8 field exceeds max_bytes";
      return(false);
     }

   const int offset=ArraySize(buffer);
   ArrayResize(buffer,offset+2+length);
   Kat1WriteU16LE(buffer,offset,(ushort)length);
   for(int i=0;i<length;i++)
      buffer[offset+2+i]=utf8[i];

   return(true);
  }

bool Kat1BuildHeartbeat(const ulong sequence,
                        const ulong source_time_ns,
                        const ulong stream_id,
                        const ulong boot_id,
                        const ulong uptime_ms,
                        const ulong latest_produced_sequence,
                        const ulong latest_consumed_command_sequence,
                        const uint critical_queue_depth,
                        const uint market_queue_depth,
                        const ulong last_broker_observation_ns,
                        const uchar transport_state,
                        uchar &frame[],
                        string &error)
  {
   uchar payload[];
   ArrayResize(payload,48);
   ArrayInitialize(payload,0);

   Kat1WriteU64LE(payload,0,uptime_ms);
   Kat1WriteU64LE(payload,8,latest_produced_sequence);
   Kat1WriteU64LE(payload,16,latest_consumed_command_sequence);
   Kat1WriteU32LE(payload,24,critical_queue_depth);
   Kat1WriteU32LE(payload,28,market_queue_depth);
   Kat1WriteU64LE(payload,32,last_broker_observation_ns);
   payload[40]=transport_state;

   return(Kat1BuildFrame(KAT1_MSG_HEARTBEAT,
                         1,
                         48,
                         KAT1_FLAG_CRC32C_PRESENT,
                         sequence,
                         source_time_ns,
                         stream_id,
                         boot_id,
                         payload,
                         frame,
                         error));
  }

bool Kat1DecodeHello(const uchar &frame[],
                     SKat1HelloMessage &hello,
                     string &error)
  {
   SKat1Header header;
   if(!Kat1ValidateFrame(frame,header,error))
      return(false);

   if(header.message_type!=KAT1_MSG_HELLO ||
      header.schema_version!=1 ||
      header.block_length!=52)
     {
      error="frame is not HELLO v1";
      return(false);
     }

   if((header.flags & KAT1_FLAG_CRITICAL_MESSAGE)==0 ||
      (header.flags & KAT1_FLAG_CRC32C_PRESENT)==0)
     {
      error="HELLO flags are invalid";
      return(false);
     }

   const int root=KAT1_HEADER_BYTES;
   if(ArraySize(frame)<root+52+4)
     {
      error="HELLO root block truncated";
      return(false);
     }

   for(int i=0;i<16;i++)
      hello.client_instance_id[i]=frame[root+i];

   hello.requested_capability_bits=Kat1ReadU64LE(frame,root+16);
   hello.last_known_stream_id=Kat1ReadU64LE(frame,root+24);
   hello.last_execution_cursor=Kat1ReadU64LE(frame,root+32);
   hello.requested_execution_mode=frame[root+40];
   hello.requested_wire_major=frame[root+41];
   hello.requested_wire_minor=frame[root+42];
   hello.last_snapshot_sequence=Kat1ReadU64LE(frame,root+44);

   if(hello.requested_wire_major!=KAT1_WIRE_MAJOR ||
      hello.requested_wire_minor!=KAT1_WIRE_MINOR)
     {
      error="HELLO requested wire version mismatch";
      return(false);
     }

   return(true);
  }

bool Kat1BuildHelloAck(const ulong sequence,
                       const ulong source_time_ns,
                       const ulong stream_id,
                       const ulong boot_id,
                       const uchar &account_id[],
                       const ulong broker_login,
                       const uint terminal_build,
                       const uint ea_build_version,
                       const ulong capability_bits,
                       const uchar account_mode,
                       const uchar trade_mode,
                       const uchar execution_mode,
                       const uchar recovery_state,
                       const uchar money_scale,
                       const uchar account_currency_digits,
                       const uchar &ea_source_hash[],
                       const uint account_unit_profile_revision,
                       const string broker_server,
                       const string account_currency,
                       uchar &frame[],
                       string &error)
  {
   if(ArraySize(account_id)!=16)
     {
      error="HELLO_ACK account_id must be 16 bytes";
      return(false);
     }

   if(ArraySize(ea_source_hash)!=32)
     {
      error="HELLO_ACK ea_source_hash must be 32 bytes";
      return(false);
     }

   uchar payload[];
   ArrayResize(payload,104);
   ArrayInitialize(payload,0);

   for(int i=0;i<16;i++)
      payload[i]=account_id[i];

   Kat1WriteU64LE(payload,16,broker_login);
   Kat1WriteU32LE(payload,24,terminal_build);
   Kat1WriteU32LE(payload,28,ea_build_version);
   Kat1WriteU64LE(payload,32,stream_id);
   Kat1WriteU64LE(payload,40,boot_id);
   Kat1WriteU64LE(payload,48,capability_bits);
   payload[56]=account_mode;
   payload[57]=trade_mode;
   payload[58]=execution_mode;
   payload[59]=recovery_state;
   payload[60]=money_scale;
   payload[61]=account_currency_digits;

   for(int i=0;i<32;i++)
      payload[64+i]=ea_source_hash[i];

   Kat1WriteU32LE(payload,96,account_unit_profile_revision);

   if(!Kat1AppendU16Utf8(payload,broker_server,64,error))
      return(false);
   if(!Kat1AppendU16Utf8(payload,account_currency,16,error))
      return(false);

   return(Kat1BuildFrame(KAT1_MSG_HELLO_ACK,
                         1,
                         104,
                         KAT1_FLAG_CRC32C_PRESENT|KAT1_FLAG_CRITICAL_MESSAGE,
                         sequence,
                         source_time_ns,
                         stream_id,
                         boot_id,
                         payload,
                         frame,
                         error));
  }

#endif
