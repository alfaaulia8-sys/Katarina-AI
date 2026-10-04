#property script_show_inputs
#property version "1.000"
#property strict

#include <Katarina/Stage07/WireSequence.mqh>

#define PHASE_FILE "Katarina_Stage07_wire_sequence_phase.txt"
#define RESULT_FILE "Katarina_Stage07_wire_sequence_result.txt"

bool WriteCommonText(const string name,const string text)
  {
   const int handle=FileOpen(name,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(handle==INVALID_HANDLE)
      return(false);
   FileWriteString(handle,text);
   FileFlush(handle);
   FileClose(handle);
   return(true);
  }

bool CommonFileExists(const string name)
  {
   const int handle=FileOpen(name,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(handle==INVALID_HANDLE)
      return(false);
   FileClose(handle);
   return(true);
  }

void Fail(const string reason)
  {
   WriteCommonText(RESULT_FILE,
                   "stage=07\r\nresult=FAIL\r\nreason="+reason+"\r\n");
   Print("KATARINA_STAGE07_WIRE_SEQUENCE_TEST result=FAIL reason=",reason);
  }

void OnStart()
  {
   const ulong stream_id=0x12345678ABCDEF01;
   const string lane="MT5_TO_PYTHON_TEST";

   // Phase 1: a fresh terminal process allocates 1 and 2, then leaves the
   // persisted sequence intact for a second process.
   if(!CommonFileExists(PHASE_FILE))
     {
      CKatWireSequence cleanup;
      if(!cleanup.Init(stream_id,lane) || !cleanup.DeletePersistenceForTest())
        {
         Fail("phase1_cleanup");
         return;
        }

      CKatWireSequence first;
      ulong s1=0,s2=0;
      if(!first.Init(stream_id,lane) ||
         !first.Next(0,s1) || s1!=1 ||
         !first.Next(0,s2) || s2!=2)
        {
         Fail("phase1_allocation");
         return;
        }

      if(!WriteCommonText(PHASE_FILE,"phase=1\r\nlast=2\r\n"))
        {
         Fail("phase1_marker");
         return;
        }

      WriteCommonText(RESULT_FILE,
                      "stage=07\r\nresult=PHASE1_PASS\r\nobserved_last=0\r\nallocated_next=2\r\n");
      Print("KATARINA_STAGE07_WIRE_SEQUENCE_TEST result=PHASE1_PASS last=2");
      return;
     }

   // Phase 2: a new terminal process must restore 2 from terminal-global
   // persistence and allocate 3 without reuse.
   CKatWireSequence restarted;
   if(!restarted.Init(stream_id,lane))
     {
      Fail("phase2_init");
      return;
     }

   const ulong observed=restarted.Last();
   ulong next=0;
   if(observed!=2 || !restarted.Next(0,next) || next!=3)
     {
      Fail("phase2_restart_continuity");
      return;
     }

   const bool cleaned=restarted.DeletePersistenceForTest();
   FileDelete(PHASE_FILE,FILE_COMMON);
   if(!cleaned)
     {
      Fail("phase2_cleanup");
      return;
     }

   WriteCommonText(RESULT_FILE,
                   "stage=07\r\nresult=PASS\r\nobserved_last="+
                   IntegerToString((long)observed)+
                   "\r\nallocated_next="+IntegerToString((long)next)+
                   "\r\n");
   Print("KATARINA_STAGE07_WIRE_SEQUENCE_TEST result=PASS observed_last=",
         observed," allocated_next=",next);
  }
