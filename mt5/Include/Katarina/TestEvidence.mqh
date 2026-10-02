#ifndef __KATARINA_TEST_EVIDENCE_MQH__
#define __KATARINA_TEST_EVIDENCE_MQH__

#define KAT_STAGE06_EVIDENCE_DIR "Katarina\\Stage06"

string KatEvidenceSafeToken(string value)
  {
   StringReplace(value,"\\","_");
   StringReplace(value,"/","_");
   StringReplace(value,":","_");
   StringReplace(value," ","_");
   StringReplace(value,"\r","_");
   StringReplace(value,"\n","_");
   if(value=="")
      value="UNSPECIFIED";
   return(value);
  }

bool KatEnsureEvidenceDirectory(void)
  {
   if(FolderCreate(KAT_STAGE06_EVIDENCE_DIR,FILE_COMMON))
      return(true);

   // FolderCreate may return false if the folder already exists.
   const int err=GetLastError();
   ResetLastError();
   return(err==0 || err==5004);
  }

int KatOpenEvidenceFile(const string file_name)
  {
   if(!KatEnsureEvidenceDirectory())
      return(INVALID_HANDLE);

   const string path=KAT_STAGE06_EVIDENCE_DIR+"\\"+KatEvidenceSafeToken(file_name);
   return(FileOpen(path,FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI));
  }

void KatEvidenceWrite(const int handle,
                      const string key,
                      const string value)
  {
   if(handle==INVALID_HANDLE)
      return;

   string cleaned=value;
   StringReplace(cleaned,"\r"," ");
   StringReplace(cleaned,"\n"," ");
   FileWriteString(handle,key+"="+cleaned+"\r\n");
  }

void KatEvidenceWriteLong(const int handle,
                          const string key,
                          const long value)
  {
   KatEvidenceWrite(handle,key,IntegerToString(value));
  }

void KatEvidenceWriteULong(const int handle,
                           const string key,
                           const ulong value)
  {
   KatEvidenceWrite(handle,key,IntegerToString((long)value));
  }

void KatEvidenceWriteDouble(const int handle,
                            const string key,
                            const double value,
                            const int digits=8)
  {
   KatEvidenceWrite(handle,key,DoubleToString(value,digits));
  }

void KatEvidenceWriteBool(const int handle,
                          const string key,
                          const bool value)
  {
   KatEvidenceWrite(handle,key,(value ? "true" : "false"));
  }

string KatEvidenceCommonRoot(void)
  {
   return(TerminalInfoString(TERMINAL_COMMONDATA_PATH)+"\\Files\\"+KAT_STAGE06_EVIDENCE_DIR);
  }

#endif
