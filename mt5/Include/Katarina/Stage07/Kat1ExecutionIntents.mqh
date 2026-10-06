#ifndef __KATARINA_STAGE07_KAT1_EXECUTION_INTENTS_MQH__
#define __KATARINA_STAGE07_KAT1_EXECUTION_INTENTS_MQH__

#include <Katarina/Stage07/Kat1Codec.mqh>

#define KAT1_MSG_OPEN_INTENT 300

struct SKat1OpenIntent
  {
   uchar account_id[16];
   uchar execution_intent_id[16];
   uchar order_id[16];
   uchar snapshot_id[16];
   uchar decision_id[16];
   uchar risk_decision_id[16];
   uchar risk_binding_hash[32];
   uint  instrument_id;
   uint  spec_revision;
   ulong approved_account_revision;
   ulong approved_position_revision;
   ulong submit_expiry_ns;
   uint  risk_policy_version;
   ulong pending_valid_until_ns;
   long  volume_units;
   long  requested_price_units;
   long  sl_units;
   long  tp_units;
   long  expected_net_volume_after_units;
   uint  max_deviation_points;
   uchar side;
   uchar entry_type;
   uchar expected_position_effect;
   uchar netting_guard;
   uchar time_in_force;
   uchar filling_policy;
   uchar expected_net_side;
   uint  presence_flags;
  };

void Kat1CopyFixed(const uchar &frame[],const int offset,uchar &dest[],const int count)
  {
   for(int i=0;i<count;i++)
      dest[i]=frame[offset+i];
  }

bool Kat1AnyNonZero(const uchar &data[],const int count)
  {
   for(int i=0;i<count;i++)
      if(data[i]!=0)
         return(true);
   return(false);
  }

string Kat1Id128Hex(const uchar &value[])
  {
   string result="";
   for(int i=0;i<16;i++)
      result+=StringFormat("%02x",(uint)value[i]);
   return(result);
  }

bool Kat1DecodeOpenIntent(const uchar &frame[],
                          SKat1OpenIntent &intent,
                          string &error)
  {
   SKat1Header header;
   if(!Kat1ValidateFrame(frame,header,error))
      return(false);
   if(header.message_type!=KAT1_MSG_OPEN_INTENT ||
      header.schema_version!=1 ||
      header.block_length!=232)
     {
      error="frame is not OPEN_INTENT v1";
      return(false);
     }
   if((header.flags & KAT1_FLAG_CRITICAL_MESSAGE)==0 ||
      (header.flags & KAT1_FLAG_CRC32C_PRESENT)==0)
     {
      error="OPEN_INTENT critical flags missing";
      return(false);
     }

   const int root=KAT1_HEADER_BYTES;
   if(ArraySize(frame)<root+232+4)
     {
      error="OPEN_INTENT truncated";
      return(false);
     }

   Kat1CopyFixed(frame,root+0,intent.account_id,16);
   Kat1CopyFixed(frame,root+16,intent.execution_intent_id,16);
   Kat1CopyFixed(frame,root+32,intent.order_id,16);
   Kat1CopyFixed(frame,root+48,intent.snapshot_id,16);
   Kat1CopyFixed(frame,root+64,intent.decision_id,16);
   Kat1CopyFixed(frame,root+80,intent.risk_decision_id,16);
   Kat1CopyFixed(frame,root+96,intent.risk_binding_hash,32);
   intent.instrument_id=Kat1ReadU32LE(frame,root+128);
   intent.spec_revision=Kat1ReadU32LE(frame,root+132);
   intent.approved_account_revision=Kat1ReadU64LE(frame,root+136);
   intent.approved_position_revision=Kat1ReadU64LE(frame,root+144);
   intent.submit_expiry_ns=Kat1ReadU64LE(frame,root+152);
   intent.risk_policy_version=Kat1ReadU32LE(frame,root+160);
   intent.pending_valid_until_ns=Kat1ReadU64LE(frame,root+168);
   intent.volume_units=(long)Kat1ReadU64LE(frame,root+176);
   intent.requested_price_units=(long)Kat1ReadU64LE(frame,root+184);
   intent.sl_units=(long)Kat1ReadU64LE(frame,root+192);
   intent.tp_units=(long)Kat1ReadU64LE(frame,root+200);
   intent.expected_net_volume_after_units=(long)Kat1ReadU64LE(frame,root+208);
   intent.max_deviation_points=Kat1ReadU32LE(frame,root+216);
   intent.side=frame[root+220];
   intent.entry_type=frame[root+221];
   intent.expected_position_effect=frame[root+222];
   intent.netting_guard=frame[root+223];
   intent.time_in_force=frame[root+224];
   intent.filling_policy=frame[root+225];
   intent.expected_net_side=frame[root+226];
   intent.presence_flags=Kat1ReadU32LE(frame,root+228);

   if(!Kat1AnyNonZero(intent.execution_intent_id,16) ||
      !Kat1AnyNonZero(intent.decision_id,16) ||
      !Kat1AnyNonZero(intent.risk_decision_id,16) ||
      !Kat1AnyNonZero(intent.risk_binding_hash,32))
     {
      error="OPEN_INTENT lineage is zero";
      return(false);
     }
   if(intent.instrument_id==0 || intent.spec_revision==0 ||
      intent.volume_units<=0 || intent.sl_units<=0 ||
      (intent.side!=1 && intent.side!=2) ||
      intent.entry_type!=1)
     {
      error="OPEN_INTENT invalid execution fields";
      return(false);
     }
   return(true);
  }

#endif
