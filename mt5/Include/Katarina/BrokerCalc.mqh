#ifndef __KATARINA_BROKER_CALC_MQH__
#define __KATARINA_BROKER_CALC_MQH__

struct SKatBrokerCalcResult
  {
   bool   profit_valid;
   bool   margin_valid;
   double profit_native;
   double margin_native;
   int    profit_error;
   int    margin_error;
  };

void KatResetBrokerCalcResult(SKatBrokerCalcResult &result)
  {
   result.profit_valid=false;
   result.margin_valid=false;
   result.profit_native=0.0;
   result.margin_native=0.0;
   result.profit_error=0;
   result.margin_error=0;
  }

bool KatBrokerCalc(const string symbol,
                   const ENUM_ORDER_TYPE order_type,
                   const double volume,
                   const double price_open,
                   const double price_close,
                   SKatBrokerCalcResult &result)
  {
   KatResetBrokerCalcResult(result);

   if(order_type!=ORDER_TYPE_BUY && order_type!=ORDER_TYPE_SELL)
      return(false);
   if(volume<=0.0 || price_open<=0.0 || price_close<=0.0)
      return(false);

   double profit=0.0;
   ResetLastError();
   if(OrderCalcProfit(order_type,
                      symbol,
                      volume,
                      price_open,
                      price_close,
                      profit))
     {
      result.profit_valid=true;
      result.profit_native=profit;
     }
   else
     {
      result.profit_error=GetLastError();
     }

   double margin=0.0;
   ResetLastError();
   if(OrderCalcMargin(order_type,
                      symbol,
                      volume,
                      price_open,
                      margin))
     {
      result.margin_valid=true;
      result.margin_native=margin;
     }
   else
     {
      result.margin_error=GetLastError();
     }

   return(result.profit_valid || result.margin_valid);
  }

#endif
