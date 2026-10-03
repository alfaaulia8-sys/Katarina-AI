#ifndef __KATARINA_STAGE07_KAT1_CODEC_MQH__
#define __KATARINA_STAGE07_KAT1_CODEC_MQH__

#define KAT1_HEADER_BYTES 52
#define KAT1_MAX_FRAME_BYTES 65536
#define KAT1_WIRE_MAJOR 1
#define KAT1_WIRE_MINOR 0

#define KAT1_FLAG_CRC32C_PRESENT 0x0001
#define KAT1_FLAG_CRITICAL_MESSAGE 0x0002
#define KAT1_FLAG_SNAPSHOT_TRANSACTION 0x0004
#define KAT1_FLAG_REPLAYED_FROM_DURABLE_JOURNAL 0x0008
#define KAT1_SUPPORTED_FLAGS 0x000F

struct SKat1Header
  {
   uchar  wire_major;
   uchar  wire_minor;
   ushort header_length;
   ushort message_type;
   ushort schema_version;
   ushort block_length;
   ushort flags;
   uint   frame_length;
   ulong  sequence;
   ulong  source_time_ns;
   ulong  stream_id;
   ulong  boot_id;
  };

bool Kat1RangeOk(const int size,const int offset,const int width)
  {
   return(offset>=0 && width>=0 && offset<=size && width<=size-offset);
  }

ushort Kat1ReadU16LE(const uchar &data[],const int offset)
  {
   return((ushort)((uint)data[offset] |
                   ((uint)data[offset+1]<<8)));
  }

uint Kat1ReadU32LE(const uchar &data[],const int offset)
  {
   return((uint)data[offset] |
          ((uint)data[offset+1]<<8) |
          ((uint)data[offset+2]<<16) |
          ((uint)data[offset+3]<<24));
  }

ulong Kat1ReadU64LE(const uchar &data[],const int offset)
  {
   ulong value=0;
   for(int i=7;i>=0;i--)
     {
      value<<=8;
      value|=(ulong)data[offset+i];
     }
   return(value);
  }

void Kat1WriteU16LE(uchar &data[],const int offset,const ushort value)
  {
   data[offset]=(uchar)(value & 0xFF);
   data[offset+1]=(uchar)((value>>8) & 0xFF);
  }

void Kat1WriteU32LE(uchar &data[],const int offset,const uint value)
  {
   data[offset]=(uchar)(value & 0xFF);
   data[offset+1]=(uchar)((value>>8) & 0xFF);
   data[offset+2]=(uchar)((value>>16) & 0xFF);
   data[offset+3]=(uchar)((value>>24) & 0xFF);
  }

void Kat1WriteU64LE(uchar &data[],const int offset,const ulong value)
  {
   ulong current=value;
   for(int i=0;i<8;i++)
     {
      data[offset+i]=(uchar)(current & 0xFF);
      current>>=8;
     }
  }

uint Kat1Crc32c(const uchar &data[],const int length)
  {
   uint crc=0xFFFFFFFF;
   const int size=ArraySize(data);
   const int count=(length<size ? length : size);

   for(int i=0;i<count;i++)
     {
      crc^=(uint)data[i];
      for(int bit=0;bit<8;bit++)
        {
         if((crc & 1)!=0)
            crc=(crc>>1) ^ 0x82F63B78;
         else
            crc>>=1;
        }
     }

   return(crc ^ 0xFFFFFFFF);
  }

bool Kat1DecodeHeader(const uchar &data[],
                      SKat1Header &header,
                      string &error)
  {
   error="";
   const int size=ArraySize(data);
   if(size<KAT1_HEADER_BYTES)
     {
      error="frame shorter than KAT1 header";
      return(false);
     }

   if(data[0]!=0x4B || data[1]!=0x41 || data[2]!=0x54 || data[3]!=0x31)
     {
      error="bad KAT1 magic";
      return(false);
     }

   header.wire_major=data[4];
   header.wire_minor=data[5];
   header.header_length=Kat1ReadU16LE(data,6);
   header.message_type=Kat1ReadU16LE(data,8);
   header.schema_version=Kat1ReadU16LE(data,10);
   header.block_length=Kat1ReadU16LE(data,12);
   header.flags=Kat1ReadU16LE(data,14);
   header.frame_length=Kat1ReadU32LE(data,16);
   header.sequence=Kat1ReadU64LE(data,20);
   header.source_time_ns=Kat1ReadU64LE(data,28);
   header.stream_id=Kat1ReadU64LE(data,36);
   header.boot_id=Kat1ReadU64LE(data,44);

   if(header.wire_major!=KAT1_WIRE_MAJOR ||
      header.wire_minor!=KAT1_WIRE_MINOR)
     {
      error="unsupported KAT1 wire version";
      return(false);
     }

   if(header.header_length!=KAT1_HEADER_BYTES)
     {
      error="invalid KAT1 header length";
      return(false);
     }

   if((header.flags & ~KAT1_SUPPORTED_FLAGS)!=0)
     {
      error="unknown KAT1 frame flags";
      return(false);
     }

   if(header.frame_length!=(uint)size)
     {
      error="KAT1 frame length mismatch";
      return(false);
     }

   if(header.frame_length>KAT1_MAX_FRAME_BYTES)
     {
      error="KAT1 frame exceeds maximum";
      return(false);
     }

   const int trailer=((header.flags & KAT1_FLAG_CRC32C_PRESENT)!=0 ? 4 : 0);
   if((int)header.frame_length<KAT1_HEADER_BYTES+(int)header.block_length+trailer)
     {
      error="KAT1 payload shorter than root block";
      return(false);
     }

   if((header.flags & KAT1_FLAG_CRITICAL_MESSAGE)!=0 &&
      (header.flags & KAT1_FLAG_CRC32C_PRESENT)==0)
     {
      error="critical frame missing CRC32C";
      return(false);
     }

   return(true);
  }

bool Kat1ValidateFrame(const uchar &data[],
                       SKat1Header &header,
                       string &error)
  {
   if(!Kat1DecodeHeader(data,header,error))
      return(false);

   if((header.flags & KAT1_FLAG_CRC32C_PRESENT)!=0)
     {
      const int crc_offset=(int)header.frame_length-4;
      if(!Kat1RangeOk(ArraySize(data),crc_offset,4))
        {
         error="CRC32C trailer is truncated";
         return(false);
        }

      const uint expected=Kat1ReadU32LE(data,crc_offset);
      const uint actual=Kat1Crc32c(data,crc_offset);
      if(actual!=expected)
        {
         error="CRC32C mismatch";
         return(false);
        }
     }

   return(true);
  }

bool Kat1EncodeHeader(const SKat1Header &header,
                      uchar &output[],
                      string &error)
  {
   error="";
   if(header.wire_major!=KAT1_WIRE_MAJOR ||
      header.wire_minor!=KAT1_WIRE_MINOR)
     {
      error="unsupported KAT1 wire version";
      return(false);
     }
   if(header.header_length!=KAT1_HEADER_BYTES)
     {
      error="invalid KAT1 header length";
      return(false);
     }
   if((header.flags & ~KAT1_SUPPORTED_FLAGS)!=0)
     {
      error="unknown KAT1 frame flags";
      return(false);
     }
   if(header.frame_length<KAT1_HEADER_BYTES ||
      header.frame_length>KAT1_MAX_FRAME_BYTES)
     {
      error="invalid KAT1 frame length";
      return(false);
     }

   ArrayResize(output,KAT1_HEADER_BYTES);
   ArrayInitialize(output,0);

   output[0]=0x4B;
   output[1]=0x41;
   output[2]=0x54;
   output[3]=0x31;
   output[4]=header.wire_major;
   output[5]=header.wire_minor;
   Kat1WriteU16LE(output,6,header.header_length);
   Kat1WriteU16LE(output,8,header.message_type);
   Kat1WriteU16LE(output,10,header.schema_version);
   Kat1WriteU16LE(output,12,header.block_length);
   Kat1WriteU16LE(output,14,header.flags);
   Kat1WriteU32LE(output,16,header.frame_length);
   Kat1WriteU64LE(output,20,header.sequence);
   Kat1WriteU64LE(output,28,header.source_time_ns);
   Kat1WriteU64LE(output,36,header.stream_id);
   Kat1WriteU64LE(output,44,header.boot_id);
   return(true);
  }

int Kat1HexNibble(const ushort ch)
  {
   if(ch>='0' && ch<='9')
      return((int)(ch-'0'));
   if(ch>='a' && ch<='f')
      return((int)(ch-'a'+10));
   if(ch>='A' && ch<='F')
      return((int)(ch-'A'+10));
   return(-1);
  }

bool Kat1HexToBytes(const string hex,
                    uchar &output[],
                    string &error)
  {
   error="";
   const int chars=StringLen(hex);
   if(chars<=0 || (chars%2)!=0)
     {
      error="hex length must be positive and even";
      return(false);
     }

   const int bytes=chars/2;
   ArrayResize(output,bytes);

   for(int i=0;i<bytes;i++)
     {
      const int hi=Kat1HexNibble((ushort)StringGetCharacter(hex,i*2));
      const int lo=Kat1HexNibble((ushort)StringGetCharacter(hex,i*2+1));
      if(hi<0 || lo<0)
        {
         error="invalid hex character";
         ArrayResize(output,0);
         return(false);
        }
      output[i]=(uchar)((hi<<4) | lo);
     }
   return(true);
  }

bool Kat1BytesEqual(const uchar &left[],
                    const uchar &right[])
  {
   const int left_size=ArraySize(left);
   if(left_size!=ArraySize(right))
      return(false);

   for(int i=0;i<left_size;i++)
     {
      if(left[i]!=right[i])
         return(false);
     }
   return(true);
  }

bool Kat1HeaderBytesEqual(const uchar &frame[],
                          const uchar &encoded_header[])
  {
   if(ArraySize(frame)<KAT1_HEADER_BYTES ||
      ArraySize(encoded_header)!=KAT1_HEADER_BYTES)
      return(false);

   for(int i=0;i<KAT1_HEADER_BYTES;i++)
     {
      if(frame[i]!=encoded_header[i])
         return(false);
     }
   return(true);
  }

#endif
