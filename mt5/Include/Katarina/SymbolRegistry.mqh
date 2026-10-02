#ifndef __KATARINA_SYMBOL_REGISTRY_MQH__
#define __KATARINA_SYMBOL_REGISTRY_MQH__

class CKatSymbolRegistry
  {
private:
   string m_approved[];
   string m_observed[];

   bool Contains(const string &items[],const string symbol) const
     {
      const int total=ArraySize(items);
      for(int i=0;i<total;i++)
        {
         if(items[i]==symbol)
            return(true);
        }
      return(false);
     }

   bool AddUnique(string &items[],const string symbol)
     {
      if(symbol=="")
         return(false);
      if(Contains(items,symbol))
         return(true);

      const int old_size=ArraySize(items);
      if(ArrayResize(items,old_size+1)!=old_size+1)
         return(false);
      items[old_size]=symbol;
      return(true);
     }

public:
   void Reset(void)
     {
      ArrayResize(m_approved,0);
      ArrayResize(m_observed,0);
     }

   bool AddApproved(const string symbol)
     {
      if(!AddUnique(m_approved,symbol))
         return(false);
      return(AddUnique(m_observed,symbol));
     }

   bool AddApprovedCsv(const string csv)
     {
      if(csv=="")
         return(true);

      string parts[];
      const ushort separator=(ushort)StringGetCharacter(",",0);
      const int count=StringSplit(csv,separator,parts);
      if(count<0)
         return(false);

      for(int i=0;i<count;i++)
        {
         string item=parts[i];
         StringTrimLeft(item);
         StringTrimRight(item);
         if(item=="" || !AddApproved(item))
            return(false);
        }
      return(true);
     }

   bool Observe(const string symbol)
     {
      return(AddUnique(m_observed,symbol));
     }

   bool IsApproved(const string symbol) const
     {
      return(Contains(m_approved,symbol));
     }

   int ApprovedCount(void) const
     {
      return(ArraySize(m_approved));
     }

   int ObservedCount(void) const
     {
      return(ArraySize(m_observed));
     }

   bool ApprovedAt(const int index,string &symbol) const
     {
      if(index<0 || index>=ArraySize(m_approved))
         return(false);
      symbol=m_approved[index];
      return(true);
     }

   bool ObservedAt(const int index,string &symbol) const
     {
      if(index<0 || index>=ArraySize(m_observed))
         return(false);
      symbol=m_observed[index];
      return(true);
     }
  };

#endif
