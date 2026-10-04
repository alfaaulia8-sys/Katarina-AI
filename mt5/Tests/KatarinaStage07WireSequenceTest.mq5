#property script_show_inputs
#property version "1.000"
#property strict

#include <Katarina/Stage07/WireSequence.mqh>

int failures=0;

void Check(const bool condition,const string name)
  {
   if(condition) Print("PASS ",name);
   else { Print("FAIL ",name); failures++; }
  }

void OnStart()
  {
   const ulong stream_id=0x12345678ABCDEF01;
   const string lane="MT5_TO_PYTHON_TEST";

   CKatWireSequence cleanup;
   Check(cleanup.Init(stream_id,lane),"cleanup init");
   Check(cleanup.DeletePersistenceForTest(),"cleanup persistence");

   CKatWireSequence first;
   Check(first.Init(stream_id,lane),"first init");
   ulong s1=0,s2=0;
   Check(first.Next(0,s1) && s1==1,"first sequence");
   Check(first.Next(0,s2) && s2==2,"second sequence");

   // Simulate EA restart by constructing a fresh allocator over the same
   // stream/lane persistence namespace.
   CKatWireSequence restarted;
   Check(restarted.Init(stream_id,lane),"restart init");
   Check(restarted.Last()==2,"restart restores last");
   ulong s3=0;
   Check(restarted.Next(0,s3) && s3==3,"restart continues sequence");

   // Recovery floor from peer heartbeat must move forward, never backward.
   ulong s4=0;
   Check(restarted.Next(100,s4) && s4==101,"peer floor advances sequence");
   ulong s5=0;
   Check(restarted.Next(50,s5) && s5==102,"lower floor cannot rewind");

   Check(restarted.DeletePersistenceForTest(),"final cleanup");

   PrintFormat("KATARINA_STAGE07_WIRE_SEQUENCE_TEST result=%s failures=%d",
               failures==0 ? "PASS" : "FAIL",failures);
  }
