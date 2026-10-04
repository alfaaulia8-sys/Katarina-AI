#ifndef __KATARINA_STAGE07_WIRE_SEQUENCE_MQH__
#define __KATARINA_STAGE07_WIRE_SEQUENCE_MQH__

#include <Katarina/BridgeIdentity.mqh>

class CKatWireSequence
  {
private:
   ulong  m_stream_id;
   string m_lane;
   string m_hi_name;
   string m_lo_name;
   ulong  m_last;
   bool   m_ready;

   string PartName(const string part,
                   const ulong stream_id,
                   const string lane) const
     {
      const uint lane_hash=KatHashString32(lane);
      const uint stream_hi=(uint)(stream_id>>32);
      const uint stream_lo=(uint)(stream_id & 0xFFFFFFFF);
      return("KAT7_SEQ_"+part+"_"+
             IntegerToString((long)stream_hi)+"_"+
             IntegerToString((long)stream_lo)+"_"+
             IntegerToString((long)lane_hash));
     }

   bool Persist(const ulong value)
     {
      const uint hi=(uint)(value>>32);
      const uint lo=(uint)(value & 0xFFFFFFFF);

      if(GlobalVariableSet(m_hi_name,(double)hi)==0)
         return(false);
      if(GlobalVariableSet(m_lo_name,(double)lo)==0)
         return(false);

      GlobalVariablesFlush();
      m_last=value;
      return(true);
     }

public:
                     CKatWireSequence(void)
     {
      m_stream_id=0;
      m_lane="";
      m_hi_name="";
      m_lo_name="";
      m_last=0;
      m_ready=false;
     }

   bool              Init(const ulong stream_id,
                          const string lane)
     {
      m_ready=false;
      m_last=0;

      if(stream_id==0 || lane=="")
         return(false);

      m_stream_id=stream_id;
      m_lane=lane;
      m_hi_name=PartName("HI",stream_id,lane);
      m_lo_name=PartName("LO",stream_id,lane);

      const bool have_hi=GlobalVariableCheck(m_hi_name);
      const bool have_lo=GlobalVariableCheck(m_lo_name);

      // Partial persistence is ambiguous. Fail closed; do not fabricate a
      // continuation and risk reusing a previously allocated sequence.
      if(have_hi!=have_lo)
         return(false);

      if(!have_hi)
        {
         if(!Persist(0))
            return(false);
        }
      else
        {
         double hi_value=0.0;
         double lo_value=0.0;
         if(!GlobalVariableGet(m_hi_name,hi_value) ||
            !GlobalVariableGet(m_lo_name,lo_value))
            return(false);

         const ulong hi=(ulong)(uint)hi_value;
         const ulong lo=(ulong)(uint)lo_value;
         m_last=(hi<<32) | lo;
        }

      m_ready=true;
      return(true);
     }

   bool              Ready(void) const
     {
      return(m_ready);
     }

   ulong             Last(void) const
     {
      return(m_last);
     }

   bool              Next(const ulong floor,
                          ulong &sequence)
     {
      sequence=0;
      if(!m_ready)
         return(false);

      const ulong base=(m_last>floor ? m_last : floor);
      if(base==0xFFFFFFFFFFFFFFFF)
         return(false);

      const ulong next=base+1;
      if(next==0)
         return(false);

      if(!Persist(next))
         return(false);

      sequence=next;
      return(true);
     }

   bool              DeletePersistenceForTest(void)
     {
      if(m_hi_name=="" || m_lo_name=="")
         return(false);

      bool ok=true;
      if(GlobalVariableCheck(m_hi_name))
         ok=(GlobalVariableDel(m_hi_name) && ok);
      if(GlobalVariableCheck(m_lo_name))
         ok=(GlobalVariableDel(m_lo_name) && ok);
      GlobalVariablesFlush();

      m_ready=false;
      m_last=0;
      return(ok);
     }
  };

#endif
