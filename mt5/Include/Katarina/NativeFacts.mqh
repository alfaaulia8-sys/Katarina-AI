#ifndef __KATARINA_NATIVE_FACTS_MQH__
#define __KATARINA_NATIVE_FACTS_MQH__

struct SKatAccountFacts
  {
   ulong                     login;
   long                      leverage;
   ENUM_ACCOUNT_MARGIN_MODE  margin_mode;
   ENUM_ACCOUNT_TRADE_MODE   trade_mode;
   ENUM_ACCOUNT_STOPOUT_MODE stopout_mode;
   bool                      trade_allowed;
   bool                      expert_trade_allowed;
   bool                      hedge_allowed;
   bool                      fifo_close;
   string                    server;
   string                    currency;
   int                       currency_digits;

   double                    balance;
   double                    equity;
   double                    credit;
   double                    profit;
   double                    margin;
   double                    free_margin;
   double                    margin_initial;
   double                    margin_maintenance;
   double                    margin_level;
   double                    margin_call;
   double                    stopout_level;
  };

struct SKatSymbolFacts
  {
   string                 symbol;
   int                    digits;
   ENUM_SYMBOL_CALC_MODE  calc_mode;
   ENUM_SYMBOL_TRADE_MODE trade_mode;
   ENUM_SYMBOL_SWAP_MODE  swap_mode;
   long                   order_mode;
   long                   filling_mode;
   long                   expiration_mode;
   int                    stops_level_points;
   int                    freeze_level_points;

   double                 point;
   double                 tick_size;
   double                 tick_value;
   double                 tick_value_profit;
   double                 tick_value_loss;
   double                 contract_size;
   double                 volume_min;
   double                 volume_max;
   double                 volume_step;
   double                 volume_limit;
   double                 margin_initial;
   double                 margin_maintenance;
   double                 swap_long;
   double                 swap_short;
   double                 swap_sunday;
   double                 swap_monday;
   double                 swap_tuesday;
   double                 swap_wednesday;
   double                 swap_thursday;
   double                 swap_friday;
   double                 swap_saturday;

   string                 base_currency;
   string                 profit_currency;
   string                 margin_currency;
  };

bool KatReadAccountFacts(SKatAccountFacts &facts)
  {
   facts.login=(ulong)AccountInfoInteger(ACCOUNT_LOGIN);
   facts.leverage=AccountInfoInteger(ACCOUNT_LEVERAGE);
   facts.margin_mode=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   facts.trade_mode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   facts.stopout_mode=(ENUM_ACCOUNT_STOPOUT_MODE)AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE);
   facts.trade_allowed=(bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
   facts.expert_trade_allowed=(bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
   facts.hedge_allowed=(bool)AccountInfoInteger(ACCOUNT_HEDGE_ALLOWED);
   facts.fifo_close=(bool)AccountInfoInteger(ACCOUNT_FIFO_CLOSE);
   facts.server=AccountInfoString(ACCOUNT_SERVER);
   facts.currency=AccountInfoString(ACCOUNT_CURRENCY);
   facts.currency_digits=(int)AccountInfoInteger(ACCOUNT_CURRENCY_DIGITS);

   facts.balance=AccountInfoDouble(ACCOUNT_BALANCE);
   facts.equity=AccountInfoDouble(ACCOUNT_EQUITY);
   facts.credit=AccountInfoDouble(ACCOUNT_CREDIT);
   facts.profit=AccountInfoDouble(ACCOUNT_PROFIT);
   facts.margin=AccountInfoDouble(ACCOUNT_MARGIN);
   facts.free_margin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   facts.margin_initial=AccountInfoDouble(ACCOUNT_MARGIN_INITIAL);
   facts.margin_maintenance=AccountInfoDouble(ACCOUNT_MARGIN_MAINTENANCE);
   facts.margin_level=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   facts.margin_call=AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL);
   facts.stopout_level=AccountInfoDouble(ACCOUNT_MARGIN_SO_SO);

   if(facts.login==0)
      return(false);
   if(facts.server=="")
      return(false);
   if(facts.currency=="")
      return(false);
   if(facts.currency_digits<0 || facts.currency_digits>8)
      return(false);

   // Preserve broker-reported leverage as a fact. Do not make a raw account
   // snapshot unavailable merely because a broker/account mode reports zero;
   // execution/risk capability validation belongs to the later safety layers.
   return(true);
  }

bool KatReadSymbolFacts(const string symbol,SKatSymbolFacts &facts)
  {
   long integer_value=0;
   double double_value=0.0;
   string string_value="";

   facts.symbol=symbol;

   if(!SymbolInfoInteger(symbol,SYMBOL_DIGITS,integer_value))
      return(false);
   facts.digits=(int)integer_value;

   if(!SymbolInfoInteger(symbol,SYMBOL_TRADE_CALC_MODE,integer_value))
      return(false);
   facts.calc_mode=(ENUM_SYMBOL_CALC_MODE)integer_value;

   if(!SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE,integer_value))
      return(false);
   facts.trade_mode=(ENUM_SYMBOL_TRADE_MODE)integer_value;

   if(!SymbolInfoInteger(symbol,SYMBOL_SWAP_MODE,integer_value))
      return(false);
   facts.swap_mode=(ENUM_SYMBOL_SWAP_MODE)integer_value;

   if(!SymbolInfoInteger(symbol,SYMBOL_ORDER_MODE,integer_value))
      return(false);
   facts.order_mode=integer_value;

   if(!SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE,integer_value))
      return(false);
   facts.filling_mode=integer_value;

   if(!SymbolInfoInteger(symbol,SYMBOL_EXPIRATION_MODE,integer_value))
      return(false);
   facts.expiration_mode=integer_value;

   if(!SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL,integer_value))
      return(false);
   facts.stops_level_points=(int)integer_value;

   if(!SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL,integer_value))
      return(false);
   facts.freeze_level_points=(int)integer_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_POINT,double_value))
      return(false);
   facts.point=double_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE,double_value))
      return(false);
   facts.tick_size=double_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE,double_value))
      return(false);
   facts.tick_value=double_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE_PROFIT,double_value))
      return(false);
   facts.tick_value_profit=double_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE_LOSS,double_value))
      return(false);
   facts.tick_value_loss=double_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_TRADE_CONTRACT_SIZE,double_value))
      return(false);
   facts.contract_size=double_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN,double_value))
      return(false);
   facts.volume_min=double_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX,double_value))
      return(false);
   facts.volume_max=double_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP,double_value))
      return(false);
   facts.volume_step=double_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_VOLUME_LIMIT,double_value))
      return(false);
   facts.volume_limit=double_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_MARGIN_INITIAL,double_value))
      return(false);
   facts.margin_initial=double_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_MARGIN_MAINTENANCE,double_value))
      return(false);
   facts.margin_maintenance=double_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_SWAP_LONG,double_value))
      return(false);
   facts.swap_long=double_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_SWAP_SHORT,double_value))
      return(false);
   facts.swap_short=double_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_SWAP_SUNDAY,double_value))
      return(false);
   facts.swap_sunday=double_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_SWAP_MONDAY,double_value))
      return(false);
   facts.swap_monday=double_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_SWAP_TUESDAY,double_value))
      return(false);
   facts.swap_tuesday=double_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_SWAP_WEDNESDAY,double_value))
      return(false);
   facts.swap_wednesday=double_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_SWAP_THURSDAY,double_value))
      return(false);
   facts.swap_thursday=double_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_SWAP_FRIDAY,double_value))
      return(false);
   facts.swap_friday=double_value;

   if(!SymbolInfoDouble(symbol,SYMBOL_SWAP_SATURDAY,double_value))
      return(false);
   facts.swap_saturday=double_value;

   if(!SymbolInfoString(symbol,SYMBOL_CURRENCY_BASE,string_value))
      return(false);
   facts.base_currency=string_value;

   if(!SymbolInfoString(symbol,SYMBOL_CURRENCY_PROFIT,string_value))
      return(false);
   facts.profit_currency=string_value;

   if(!SymbolInfoString(symbol,SYMBOL_CURRENCY_MARGIN,string_value))
      return(false);
   facts.margin_currency=string_value;

   if(facts.digits<0 || facts.digits>12)
      return(false);
   if(facts.point<=0.0 || facts.tick_size<=0.0)
      return(false);
   if(facts.volume_min<=0.0 ||
      facts.volume_max<facts.volume_min ||
      facts.volume_step<=0.0)
      return(false);
   if(facts.contract_size<=0.0)
      return(false);

   return(true);
  }

#endif
