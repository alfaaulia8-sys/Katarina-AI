#property strict
#property script_show_inputs

#include <Katarina/Stage07/WireSequence.mqh>

input ulong InpStreamId=72623859790382856;
input string InpLane="MT5_TO_PYTHON";

#define KAT_SEQ_MARKER "Katarina_Stage07_wire_sequence_phase.txt"
#define KAT_SEQ_RESULT "Katarina_Stage07_wire_sequence_result.txt"

bool WriteCommonText(const string name,const string text)
  {
   const int h=FileOpen(name,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE)
      return(false);
   FileWrite(h,text);
   FileClose(h);
   return(true);
  }

string ReadCommonText(const string name)
  {
   const int h=FileOpen(name,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE)
      return("");
   const string value=FileReadString(h);
   FileClose(h);
   return(value);
  }

void WriteResult(const string result,
                 const string detail,
                 const ulong observed,
                 const ulong allocated)
  {
   const int h=FileOpen(KAT_SEQ_RESULT,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE)
      return;
   FileWrite(h,"schema_version=1.0");
   FileWrite(h,"stage=07");
   FileWrite(h,"proof_type=MQL5_PERSISTENT_WIRE_SEQUENCE");
   FileWrite(h,"stream_id="+IntegerToString((long)InpStreamId));
   FileWrite(h,"lane="+InpLane);
   FileWrite(h,"observed_last="+IntegerToString((long)observed));
   FileWrite(h,"allocated_next="+IntegerToString((long)allocated));
   FileWrite(h,"detail="+detail);
   FileWrite(h,"result="+result);
   FileClose(h);
  }

void Finish(const int code)
  {
   if(MQLInfoInteger(MQL_STARTED_FROM_CONFIG))
      TerminalClose(code);
  }

void OnStart(void)
  {
   CKatWireSequence seq;
   if(!seq.Init(InpStreamId,InpLane))
     {
      WriteResult("FAIL","allocator init failed",0,0);
      Finish(7);
      return;
     }

   const string marker=ReadCommonText(KAT_SEQ_MARKER);

   if(marker=="")
     {
      // Phase 1: clean the test namespace, initialize it and persist two
      // allocations. The workflow then closes the terminal and starts a new
      // terminal process for phase 2.
      seq.DeletePersistenceForTest();

      CKatWireSequence fresh;
      if(!fresh.Init(InpStreamId,InpLane))
        {
         WriteResult("FAIL","phase1 clean init failed",0,0);
         Finish(7);
         return;
        }

      ulong first=0;
      ulong second=0;
      if(!fresh.Next(0,first) ||
         !fresh.Next(0,second) ||
         first!=1 ||
         second!=2 ||
         fresh.Last()!=2)
        {
         WriteResult("FAIL","phase1 allocation mismatch",fresh.Last(),second);
         Finish(7);
         return;
        }

      if(!WriteCommonText(KAT_SEQ_MARKER,"phase1=2"))
        {
         WriteResult("FAIL","unable to persist phase marker",fresh.Last(),0);
         Finish(7);
         return;
        }

      WriteResult("PHASE1_PASS","two sequences persisted before terminal restart",2,2);
      Finish(0);
      return;
     }

   if(marker!="phase1=2")
     {
      WriteResult("FAIL","unexpected phase marker",seq.Last(),0);
      Finish(7);
      return;
     }

   // Phase 2 runs in a fresh terminal process. The allocator must recover
   // sequence 2 and allocate 3; reset-to-zero would duplicate wire identity.
   if(seq.Last()!=2)
     {
      WriteResult("FAIL","persisted sequence did not survive terminal restart",seq.Last(),0);
      Finish(7);
      return;
     }

   ulong third=0;
   if(!seq.Next(0,third) || third!=3 || seq.Last()!=3)
     {
      WriteResult("FAIL","post-restart next sequence mismatch",seq.Last(),third);
      Finish(7);
      return;
     }

   FileDelete(KAT_SEQ_MARKER,FILE_COMMON);
   seq.DeletePersistenceForTest();

   WriteResult("PASS",
               "directional sequence survived terminal restart without reuse",
               2,
               third);
   Finish(0);
  }
