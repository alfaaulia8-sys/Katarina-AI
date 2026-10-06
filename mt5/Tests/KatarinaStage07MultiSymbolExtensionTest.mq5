#property strict
#property script_show_inputs

#include <Katarina/MultiSymbolCatalog.mqh>
#include <Katarina/MultiSymbolMarketSource.mqh>
#include <Katarina/MultiSymbolExecutionGateway.mqh>
#include <Katarina/Stage07/IdentityV1.mqh>

void OnStart(void)
  {
   CKatMultiSymbolCatalog catalog;
   catalog.Reset();

   bool catalog_ok=catalog.Add(_Symbol);
   SKatMultiSymbolEntry entry;
   bool resolve_ok=(catalog_ok && catalog.EntryAt(0,entry));
   const uint expected_id=KatStableInstrumentId(_Symbol);
   bool id_ok=(resolve_ok && entry.instrument_id==expected_id && entry.spec_revision>=1);

   CKatMultiSymbolMarketSource source;
   bool source_ok=(catalog_ok && source.Bind(catalog));

   CKatMultiSymbolExecutionGateway gateway;
   bool gateway_ok=(catalog_ok && gateway.Bind(catalog));

   // Compile/runtime proof is deliberately non-mutating. The real submit path
   // exists in MultiSymbolExecutionGateway but is never called by this test.
   const bool result=(catalog_ok && resolve_ok && id_ok && source_ok && gateway_ok);

   const int handle=FileOpen("Katarina_Stage07_multi_symbol_extension_result.txt",
                             FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(handle!=INVALID_HANDLE)
     {
      FileWrite(handle,"stage=07");
      FileWrite(handle,"proof_type=MULTI_SYMBOL_EXTENSION");
      FileWrite(handle,"catalog_count="+IntegerToString(catalog.Count()));
      FileWrite(handle,"instrument_id="+IntegerToString((int)entry.instrument_id));
      FileWrite(handle,"spec_revision="+IntegerToString((int)entry.spec_revision));
      FileWrite(handle,"execution_mutation=DISABLED_IN_TEST");
      FileWrite(handle,(result ? "result=PASS" : "result=FAIL"));
      FileClose(handle);
     }
   if(!result)
      Print("KatarinaStage07MultiSymbolExtensionTest FAIL");
   else
      Print("KatarinaStage07MultiSymbolExtensionTest PASS");
  }
