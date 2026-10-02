#ifndef __KATARINA_BRIDGE_IDENTITY_MQH__
#define __KATARINA_BRIDGE_IDENTITY_MQH__

uint KatHashString32(const string value)
  {
   uint hash=2166136261;
   const int length=StringLen(value);
   for(int i=0;i<length;i++)
     {
      const uint ch=(uint)StringGetCharacter(value,i);
      hash^=ch;
      hash*=16777619;
     }
   return(hash);
  }

ulong KatGenerateNonZeroId64(void)
  {
   const uint seed=(uint)(
      GetTickCount() ^
      (uint)GetMicrosecondCount() ^
      (uint)ChartID() ^
      (uint)TimeLocal()
   );

   MathSrand((int)seed);

   ulong value=0;
   for(int i=0;i<5;i++)
     {
      value=(value<<15) ^ (ulong)MathRand();
     }

   value^=(ulong)GetMicrosecondCount();
   value^=((ulong)(uint)ChartID()<<32);

   if(value==0)
      value=1;

   return(value);
  }

class CKatBridgeIdentity
  {
private:
   ulong  m_stream_id;
   ulong  m_boot_id;
   string m_stream_hi_name;
   string m_stream_lo_name;
   bool   m_ready;

   string PartName(const string prefix,
                   const ulong login,
                   const string server) const
     {
      const uint server_hash=KatHashString32(server);
      return(prefix+
             IntegerToString((long)login)+"_"+
             IntegerToString((long)server_hash));
     }

public:
                     CKatBridgeIdentity(void)
     {
      m_stream_id=0;
      m_boot_id=0;
      m_stream_hi_name="";
      m_stream_lo_name="";
      m_ready=false;
     }

   bool              Init(const ulong login,
                          const string server)
     {
      m_ready=false;
      if(login==0 || server=="")
         return(false);

      m_stream_hi_name=PartName("KAT_STREAM_HI_",login,server);
      m_stream_lo_name=PartName("KAT_STREAM_LO_",login,server);

      bool have_hi=GlobalVariableCheck(m_stream_hi_name);
      bool have_lo=GlobalVariableCheck(m_stream_lo_name);

      if(have_hi!=have_lo)
         return(false);

      if(!have_hi)
        {
         const ulong generated=KatGenerateNonZeroId64();
         const uint hi=(uint)(generated>>32);
         const ulong mask32=4294967295;
         const uint lo=(uint)(generated & mask32);

         if(GlobalVariableSet(m_stream_hi_name,(double)hi)==0)
            return(false);
         if(GlobalVariableSet(m_stream_lo_name,(double)lo)==0)
            return(false);

         GlobalVariablesFlush();
        }

      double hi_value=0.0;
      double lo_value=0.0;
      if(!GlobalVariableGet(m_stream_hi_name,hi_value) ||
         !GlobalVariableGet(m_stream_lo_name,lo_value))
         return(false);

      const ulong hi=(ulong)(uint)hi_value;
      const ulong lo=(ulong)(uint)lo_value;
      m_stream_id=(hi<<32) | lo;

      if(m_stream_id==0)
         return(false);

      m_boot_id=KatGenerateNonZeroId64();
      if(m_boot_id==m_stream_id)
         m_boot_id^=0x5A5A5A5A5A5A5A5A;

      if(m_boot_id==0)
         m_boot_id=1;

      m_ready=true;
      return(true);
     }

   bool              Ready(void) const
     {
      return(m_ready);
     }

   ulong             StreamId(void) const
     {
      return(m_stream_id);
     }

   ulong             BootId(void) const
     {
      return(m_boot_id);
     }
  };

#endif
