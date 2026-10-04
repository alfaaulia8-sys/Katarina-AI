#ifndef __KATARINA_STAGE07_IDENTITY_V1_MQH__
#define __KATARINA_STAGE07_IDENTITY_V1_MQH__

#include <Katarina/Stage07/Kat1Codec.mqh>

bool Kat1StringBytesNoNull(const string value,
                           const uint codepage,
                           uchar &output[])
  {
   ArrayResize(output,0);
   const int copied=StringToCharArray(value,output,0,WHOLE_ARRAY,codepage);
   if(copied<0)
      return(false);

   int size=ArraySize(output);
   if(size>0 && output[size-1]==0)
      ArrayResize(output,size-1);

   return(true);
  }

bool Kat1AppendBytes(uchar &target[],
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

bool Kat1AppendByte(uchar &target[],
                    const uchar value)
  {
   const int offset=ArraySize(target);
   if(ArrayResize(target,offset+1)!=(offset+1))
      return(false);
   target[offset]=value;
   return(true);
  }

bool Kat1AppendU32LEBytes(uchar &target[],
                         const uint value)
  {
   const int offset=ArraySize(target);
   if(ArrayResize(target,offset+4)!=(offset+4))
      return(false);
   Kat1WriteU32LE(target,offset,value);
   return(true);
  }

// FROZEN Stage-04 identity contract:
// SHA256(
//   UTF8("KAT1/account-id/v1") || 0x00 ||
//   uint32_le(len(server_utf8)) || server_utf8 || 0x00 ||
//   ASCII(decimal broker_login)
// )[0:16]
bool Kat1BuildAccountId(const string broker_server,
                        const ulong broker_login,
                        uchar &account_id[],
                        string &error)
  {
   error="";
   ArrayResize(account_id,0);

   if(broker_server=="" || broker_login==0)
     {
      error="broker identity is incomplete";
      return(false);
     }

   uchar prefix[];
   uchar server[];
   uchar login_ascii[];
   if(!Kat1StringBytesNoNull("KAT1/account-id/v1",CP_UTF8,prefix) ||
      !Kat1StringBytesNoNull(broker_server,CP_UTF8,server) ||
      !Kat1StringBytesNoNull(IntegerToString((long)broker_login),
                             CP_ACP,
                             login_ascii))
     {
      error="identity string encoding failed";
      return(false);
     }

   uchar material[];
   ArrayResize(material,0);

   if(!Kat1AppendBytes(material,prefix) ||
      !Kat1AppendByte(material,0) ||
      !Kat1AppendU32LEBytes(material,(uint)ArraySize(server)) ||
      !Kat1AppendBytes(material,server) ||
      !Kat1AppendByte(material,0) ||
      !Kat1AppendBytes(material,login_ascii))
     {
      error="identity material allocation failed";
      return(false);
     }

   const uchar key[]={};
   uchar digest[];
   ResetLastError();
   if(!CryptEncode(CRYPT_HASH_SHA256,material,key,digest))
     {
      error="SHA256 failed, error="+IntegerToString(GetLastError());
      return(false);
     }

   if(ArraySize(digest)!=32)
     {
      error="SHA256 digest length is not 32 bytes";
      return(false);
     }

   ArrayResize(account_id,16);
   for(int i=0;i<16;i++)
      account_id[i]=digest[i];

   return(true);
  }

#endif
