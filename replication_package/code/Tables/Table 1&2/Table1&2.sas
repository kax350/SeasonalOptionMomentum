
*--------------------------------------------------------------------;

%let root=D:\vixseas;

libname here "&root\Data Raw";

*--------------------------------------------------------------------;

***********************************************************
**********************load data****************************
***********************************************************;
/*The data 'options' contain only individual stock options on the 3rd Friday whose maturities are the 3rd Friday next month. It is at firm-month frequency.*/
data options;  set here.options;
if open_interest>0;  
if delta ne .;
if best_bid=0 then delete;  
if best_bid>best_offer then delete; 
strike_price=strike_price/1000; /* strike in OptionMetrics is multiplied by 1000*/
Mid_quote=(best_offer+best_bid)/2;
days_expire=exdate_trade-date;  /*exdate_trade is created as the last trading day of option holding period.*/ 
run;
proc sort data=options nodupkey; by secid date exdate strike_price cp_flag; run;

/* Load the Zero Coupon Yield Curve data in OptionMetrics and interpolate Rf. */
data ZeroCouponYieldCurve;  set here.ZeroCouponYieldCurve; run;
proc expand data=ZeroCouponYieldCurve out=ZeroCouponYieldCurve to=day;
convert rate=linear_rate / method=spline(natural);  id days; by date; run;
data ZeroCouponYieldCurve; set ZeroCouponYieldCurve; format days best12.; run;
proc sort data=ZeroCouponYieldCurve; by date days; run;

/* Load your daily CRSP stock data. */
data stock_prc;  set here.CRSP_stock_daily; keep permno cusip date prc ret divamt shrcd shrout; run;
data stock_prc; set stock_prc; prc=abs(prc); if ret=.B | ret=.C then delete; run;
proc sort data=stock_prc nodupkey; by cusip date;run;


***********************************************************
*****Other filters at firm-month frequency******************
***********************************************************;
/* Delete firm-months with dividends. */
proc sort data=options nodupkey out=filter; by secid date; run;
data dividend; set stock_prc; where divamt>0; run;
proc sql;
  create table firm_divd as
    select a.*, b.divamt
	from filter a left join dividend b
	  on a.cusip=b.cusip and a.date<b.date<=a.exdate_trade;quit;
proc sort data=firm_divd; by secid date;run;
proc means data=firm_divd NOPRINT nway;
class secid date; var divamt; output out=firm_month_divd  sum=divamt;run;
proc sql;
  create table filter as
    select a.*, b.divamt 
	from filter a left join firm_month_divd b
	  on a.secid=b.secid and a.date=b.date;quit;
data filter; set filter; if divamt=.; run;
proc sort data=filter; by secid date; run;
data options; merge filter (in=a) options;  by secid date;  if a;  run;

/* Delete firm-month with stock splits. Need the 'dsedist' data in CRSP. */
proc sort data=options nodupkey out=filter; by secid date; run;
data stock_split; set here.dsedist; if FACSHR ne 0; split_flag=1; run;
proc sql;
  create table filter as
    select a.*,b.split_flag
	from filter a left join stock_split b
	  on a.cusip=b.cusip and a.date<b.exdt<=a.exdate_trade;quit;
proc sort data=filter nodupkey; by secid date;  run;
data filter; set filter; if split_flag ne 1; run;
proc sort data=options;  by secid date;  run;
data options; merge filter (in=a) options; by secid date; if a;  run;

/* Keep only options whose underlying stock prices are at least $5 at the formation date.*/
proc sql;
  create table options as
    select a.*, b.prc as St_start
	from options a left join stock_prc b
	on a.cusip=b.cusip and a.date=b.date; quit;
proc sort data=options nodupkey; by secid date strike_price descending cp_flag; run;
data options; set options; if 5=<st_start; run;

/*Keep common shares*/
proc sql;
  create table options as
    select a.*, b.shrcd
	from options a left join stock_prc b
	  on a.cusip=b.cusip and a.date=b.date;  quit;
data options; set options; if shrcd=10 | shrcd=11;; run;


/*************************************************
******************** Options filters ************
**************************************************/
/* Compute forward price = S0*exp(rf) */
data options_findForward; set options; run;
proc sort data=options_findForward nodupkey; by secid date; run;
proc sql;
  create table options_findForward as
    select a.*,b.linear_rate
	from options_findForward a left join ZeroCouponYieldCurve b
	  on a.date=b.date and a.exdate_trade=b.date+b.days;  quit;
proc sort data=options_findForward; by secid date; run;
proc sql;
  create table options_findForward as
    select a.*,b.prc as stock_prc_start
	from options_findForward a left join stock_prc b
	  on a.cusip=b.cusip and a.date=b.date;  quit;
proc sort data=options_findForward nodupkey; by cusip date; run;
data options_findForward;  set options_findForward;
Forward=stock_prc_start*exp(linear_rate/100*days_expire/365); run;
proc sql;
  create table options as
    select a.*,b.Forward,  b.linear_rate
	from options a left join options_findForward b
	  on a.secid=b.secid and a.date=b.date; quit;
data options;   set options;
if cp_flag="P" and strike_price>forward then delete;
if cp_flag="C" and strike_price<=forward then delete;  run;
proc sort data=options; by secid date strike_price; run;

/* Delete options violate arbitrage bound */
data options;  set options; 
if cp_flag='P' and strike_price<best_bid then delete;
if cp_flag='P' and best_offer<max(0,strike_price-st_start) then delete;
if cp_flag='C' and st_start<best_bid then delete;
if cp_flag='C' and best_offer<max(0,st_start-strike_price) then delete; run;
data options;retain secid date exdate exdate_trade days_expire cp_flag strike_price forward mid_quote;set options; run;

/* Save options for computing VIX prc with half strikes later.*/
data options_half_strikes; set options; run;

/* save options for computing VIX prc with interpolation & extrapolation later.*/
data options_interpo_extrapo; set options; run;

/* Find K0: the strike immediately below forward. */
data options_findK0; set options; distance_toForward=Forward-strike_price; if distance_toForward<0 then delete; run;
proc sort data=options_findK0; by secid date distance_toForward; run;
data options_findK0; set options_findK0; by secid date; if first.secid | first.date; run;
data options_findK0; set options_findK0; rename strike_price=K0; run;
proc sql;
  create table options as
    select a.*, b.K0
	from options a left join options_findK0 b
	  on a.secid=b.secid and a.date=b.date; quit;
data options; set options; if K0 ne .; run;

/* Find K1: the strike immediately above forward*/
data options_findK1; set options; distance_toForward=strike_price-Forward; if distance_toForward<0 then delete; run;
proc sort data=options_findK1; by secid date distance_toForward; run;
data options_findK1; set options_findK1; by secid date; if first.secid | first.date; run;
data options_findK1; set options_findK1; rename strike_price=K1; run;
proc sql;
  create table options as
    select a.*, b.K1 
	from options a left join options_findK1 b
	  on a.secid=b.secid and a.date=b.date;quit;
data options; set options;  if K1 ne .; run;

/* Pick put at K0 & call at K1, which will be used later in Simpson formula*/
data options_at_K0_K1; set options; if strike_price=K0 | strike_price=K1; run;

/* For each firm-month, get the number of puts and calls. */
data call_used; set options; if cp_flag='C'; run;
proc sort data=call_used; by secid date strike_price; run;
data put_used; set options; if cp_flag='P'; run;
proc sort data=put_used; by secid date descending strike_price;run;
proc means data=call_used NOPRINT nway;
class secid date;   var strike_price;
output out=num_call_eachobs n=num_call; run;
proc means data=put_used NOPRINT nway;
class secid date;  var strike_price;
output out=num_put_eachobs n=num_put; run;
proc sql;
  create table num_put_eachobs as
    select a.*,b.num_call
	from num_put_eachobs a left join num_call_eachobs b
	on a.secid=b.secid and a.date=b.date;  quit;
data num_put_eachobs;  set num_put_eachobs; if num_call ne .;
num_min=min(num_put,num_call); num_sum=num_put+num_call ; run;
proc sort data=options; by secid date strike_price; run;

/* Find the strike range. */
proc means data=options NOPRINT nway;
class secid date; var strike_price; output out=strike_interval min=strike_min max=strike_max; run;
proc means data=options NOPRINT nway;
class secid date; var impl_volatility; output out=IV_avg mean=IV_avg; run;
proc sql;
  create table strike_interval as
    select a.*,b.IV_avg
	from strike_interval a left join IV_avg b
	on a.secid=b.secid and a.date=b.date; quit;


/*************************************************************
********Calculate the weight of each option in VIX ***********
**************************************************************/
data options_weight; set options; run;
proc sort data=options_weight; by secid date strike_price; run;
data options_weight; set options_weight;
by secid date; lagged_strike_price=lag(strike_price);if first.secid | first.date then lagged_strike_price=.; run;
proc sort data=options_weight; by secid date descending strike_price descending cp_flag;run;
data options_weight; set options_weight;
by secid date; lead_strike_price=lag(strike_price);
if first.secid | first.date  then lead_strike_price=.; run;
proc sort data=options_weight; by secid date strike_price descending cp_flag; run;
data options_weight; set options_weight;  by secid date ;
delta_K=(lead_strike_price-lagged_strike_price)/2;
if first.secid | first.date then delta_K=lead_strike_price-strike_price;
if last.secid | last.date then delta_K=strike_price-lagged_strike_price; run;

data options_weight;  set options_weight;
Weight_eachoption=2*delta_K/(strike_price**2);

/* Simpson formula puts extra weights on Put(K0) & Call(K1). */
if strike_price=K0 then Weight_eachoption = Weight_eachoption+(K1-K0-delta_K)/3/(K0**2);
if strike_price=K1 then Weight_eachoption = Weight_eachoption+(K1-K0-delta_K)/3/(K1**2);

weight_times_price=Weight_eachoption*mid_quote;
weight_times_price_bid=Weight_eachoption*best_bid;
weight_times_price_ask=Weight_eachoption*best_offer;
weight_delta=Weight_eachoption*delta; run;


/* Save delta_K at K0 & K1, which will be used later. */
data options_weight_at_K0_K1; set options_weight; if strike_price=K0 | strike_price=K1; run;


/* Merge delta_K of min and max strike, used later to determine corridor barriers. */
proc sql;
  create table strike_interval as
    select a.*,b.delta_K as delta_min
	from strike_interval a left join options_weight b
	on a.secid=b.secid and a.date=b.date and a.strike_min=b.strike_price; quit;
proc sql;
  create table strike_interval as
    select a.*,b.delta_K as delta_max
	from strike_interval a left join options_weight b
	on a.secid=b.secid and a.date=b.date and a.strike_max=b.strike_price; quit;


/* "Options_VIXPort" will be used later for computing daily Black-Scholes hedged VIX return. */
proc sql;
  create table Options_VIXPort as
    select a.*,b.Weight_eachoption
	from options a left join options_weight b
	on a.secid=b.secid and a.date=b.date and a.strike_price=b.strike_price; quit;
data Options_VIXPort; set Options_VIXPort; keep secid cusip date exdate exdate_trade optionid cp_flag strike_price Weight_eachoption linear_rate; run;


/**************************************************
********* VIX portfolio price *********************
***************************************************/
proc sort data=options_weight; by secid date strike_price; run;
proc means data=options_weight NOPRINT nway;
class secid date;  
var weight_times_price weight_times_price_bid weight_times_price_ask weight_delta;
output out=sigma2_each_exdate  sum=sigma2 sigma2_bid sigma2_ask Initial_delta; run;
proc sql;
  create table sigma2_each_exdate as
    select a.*,b.Forward, b.K0, b.days_expire
	from sigma2_each_exdate a left join options_weight b
	  on a.secid=b.secid and a.date=b.date;  quit;
proc sort data=sigma2_each_exdate nodupkey; by secid date; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*,b.linear_rate
	from sigma2_each_exdate a left join ZeroCouponYieldCurve b
	  on a.date=b.date and b.days=a.days_expire;quit;
proc sort data=VIX_MonthlyPrc; by secid date; run;


/***********************************************
********* Unhedged VIX return ******************
************************************************/
/* Calculate the payoff of option component. */
proc sort data=options_weight; by cusip exdate; run;
proc sql;
  create table options_weight as
    select a.*,b.prc as stock_prc_end
	from options_weight a left join stock_prc b
	  on a.cusip=b.cusip and a.exdate_trade=b.date;quit;
data options_weight; set options_weight;   
if stock_prc_end ne . ; 
if cp_flag='C' then option_payoff=max(stock_prc_end-strike_price,0);
if cp_flag='P' then option_payoff=max(strike_price-stock_prc_end,0);
Option_TerminalPayoff=Weight_eachoption*option_payoff; run;
proc sort data=options_weight; by secid date strike_price; run;
proc means data=options_weight  NOPRINT nway;
class secid date; var Option_TerminalPayoff;
output out=actual_VIXPort_payoff sum=Option_TerminalPayoff; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*,b.Option_TerminalPayoff 
	from VIX_MonthlyPrc a left join actual_VIXPort_payoff b
	on a.secid=b.secid and a.date=b.date;  quit;


/*merge other necessary variables*/
proc sort data=options_weight nodupkey out=identifier; by secid date; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*,b.cusip, b.exdate_trade
	from VIX_MonthlyPrc a left join identifier b
	  on a.secid=b.secid and a.date=b.date;quit;
proc sort data=VIX_MonthlyPrc; by cusip date; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.prc as St_start, b.prc*b.shrout*1000/1000000000 as mkt_cap, b.permno
	from VIX_MonthlyPrc a left join stock_prc b
	on a.cusip=b.cusip and a.date=b.date;   quit;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.prc as St_end
	from VIX_MonthlyPrc a left join stock_prc b
	on a.cusip=b.cusip and a.exdate_trade=b.date;   quit;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.K1
	from VIX_MonthlyPrc a left join options_findK1 b
	on a.secid=b.secid and a.date=b.date ;  quit;
data delta_K0; set options_weight_at_K0_K1; if strike_price=K0; run;
data delta_K1; set options_weight_at_K0_K1; if strike_price=K1;  run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.delta_K as delta_K0
	from VIX_MonthlyPrc a left join delta_K0 b
	on a.secid=b.secid and a.date=b.date ;  quit;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.delta_K as delta_K1
	from VIX_MonthlyPrc a left join delta_K1 b
	on a.secid=b.secid and a.date=b.date ;  quit;


data VIX_MonthlyPrc; set VIX_MonthlyPrc; 
Rf=exp(linear_rate/100*days_expire/365);

/*The actual payoff of VIX portfolio is the sum of the option portfolio in Eqn (3) and a portfolio of stocks and bonds described in Page 9.*/
Static_VIX_Payoff = Option_TerminalPayoff + ( (K1-K0)/3 * (1/K0**2 - 1/K1**2) + (2/Forward - 1/K0 - 1/K1) ) * St_end + (K1-K0)/3 * (1/K1 - 1/K0) + ( log(forward/K0) + log(forward/K1) );

/* VIX_Prc is the price of VIX portfolio. */
VIX_Prc =sigma2 + ( (K1-K0)/3 * (1/K0**2 - 1/K1**2) + (2/Forward - 1/K0 - 1/K1) ) * St_start + ( (K1-K0)/3 * (1/K1 - 1/K0) + ( log(forward/K0) + log(forward/K1) ) ) / Rf;

/* "Static_VIX_Return" is the variable "Simpson's VIX portfolio return (unhedged)" in Table 2. */
Static_VIX_Return = Static_VIX_Payoff/VIX_Prc-1;  

VIX_Prc_bid = sigma2_bid + ( (K1-K0)/3 * (1/K0**2 - 1/K1**2) + (2/Forward - 1/K0 - 1/K1) ) * St_start + ( (K1-K0)/3 * (1/K1 - 1/K0) + ( log(forward/K0) + log(forward/K1) ) ) / Rf;
VIX_Prc_ask = sigma2_ask + ( (K1-K0)/3 * (1/K0**2 - 1/K1**2) + (2/Forward - 1/K0 - 1/K1) ) * St_start + ( (K1-K0)/3 * (1/K1 - 1/K0) + ( log(forward/K0) + log(forward/K1) ) ) / Rf;
VIX_BA_percent = (VIX_Prc_ask-VIX_Prc_bid)/VIX_Prc;  
if VIX_Prc_bid>0;  run;


/*****************************************************************
********* Dynamic VIX Return & Variance Swap Return ************
******************************************************************/
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.strike_min, b.strike_max, b.delta_min, b.delta_max, b.IV_avg
	from VIX_MonthlyPrc a left join strike_interval b
	  on a.secid=b.secid and a.date=b.date; quit;
data VIX_MonthlyPrc; set VIX_MonthlyPrc; 
/*define corridor price following Eqn 9 in Andersen, Bondarenko, Gonzalez*/
if forward<strike_min-delta_min/2 then forward_start_Corridor=strike_min-delta_min/2;
else if strike_min-delta_min/2<=forward<=strike_max+delta_max/2 then forward_start_Corridor=forward;
else forward_start_Corridor=strike_max+delta_max/2;

if St_end<strike_min-delta_min/2 then forward_end_Corridor=strike_min-delta_min/2;
else if strike_min-delta_min/2<=St_end<=strike_max+delta_max/2 then forward_end_Corridor=St_end;
else forward_end_Corridor=strike_max+delta_max/2;
run;
proc sort data=options nodupkey out=dummy; by secid date; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.exdate
	from VIX_MonthlyPrc a left join dummy b
	on a.secid=b.secid and a.date=b.date;   quit;
proc sql;
  create table VIX_dynamicHedge as
    select a.*,b.date as date_daily, b.ret as stock_ret, b.prc as St_daily_Corridor
	from VIX_MonthlyPrc a left join stock_prc b
	  on a.cusip=b.cusip and a.date<=b.date<=a.exdate;quit;
data VIX_dynamicHedge; set VIX_dynamicHedge; Rf_daily=exp(linear_rate/100/365);
Forward_daily=St_daily_Corridor*exp(linear_rate/100*(exdate_trade-date_daily)/365);  run;

/*Define corridor price following Eqn 9 in Andersen, Bondarenko, Gonzalez (2015)*/
data VIX_dynamicHedge; set VIX_dynamicHedge;
if Forward_daily<strike_min-delta_min/2 then Forward_daily_Corridor=strike_min-delta_min/2;
else if strike_min-delta_min/2<=Forward_daily<=strike_max+delta_max/2 then Forward_daily_Corridor=Forward_daily;
else Forward_daily_Corridor=strike_max+delta_max/2;   run;
proc sort data=VIX_dynamicHedge; by secid date date_daily; run;

data VIX_dynamicHedge; set VIX_dynamicHedge; by secid date;
/* Each day, the model-free hedge borrows $2/exp{rf*(T-t)} at Rf and invest in stock for 1 trading day; Reinvest the delta-hedged payoff next trading day to the expiration at Rf. */
Delta_Hedge_Reinvt=2/(Rf_daily**(exdate_trade-lag(date_daily)))*(1+stock_ret - Rf_daily**(date_daily-lag(date_daily)))*(Rf_daily**(exdate_trade-date_daily));

/*Corridor model-free hedge: Each day, borrow at Rf to invest in 2/lag(Forward_daily_Corridor) shares of stock; Reinvest the delta-hedged payoff next trading day to the expiration at Rf. */
Delta_Hedge_Corridor = 2/lag(Forward_daily_Corridor)*lag(St_daily_Corridor) * (1+stock_ret- Rf_daily**(date_daily-lag(date_daily))) * Rf_daily**(exdate_trade-date_daily);

/*"Delta_Hedge_Corridor_Theory" is the theoretical corridor payoff tracked by the corridor model-free hedge.*/
Delta_Hedge_Corridor_Theory =2*(Forward_daily/Forward_daily_Corridor)*(Forward_daily_Corridor/lag(Forward_daily_Corridor)-1);
run;

data VIX_dynamicHedge; set VIX_dynamicHedge; if date_daily=date then delete;  run;
proc sort data=VIX_dynamicHedge;by secid date;run;
proc means data=VIX_dynamicHedge NOPRINT nway;
class secid date; var Delta_Hedge_Reinvt Delta_Hedge_Corridor Delta_Hedge_Corridor_Theory;
output out=Delta_Hedge_payoff  sum=Delta_Hedge_payoff Delta_Hedge_payoff_Corridor Delta_Hedge_Corridor_Theory; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*,b.Delta_Hedge_payoff, b.Delta_Hedge_payoff_Corridor, b.Delta_Hedge_Corridor_Theory
	from VIX_MonthlyPrc a left join Delta_Hedge_payoff b
	  on a.secid=b.secid and a.date=b.date; quit;
data VIX_dynamicHedge; set VIX_dynamicHedge; stock_ret_square=stock_ret**2; run;
proc sort data=VIX_dynamicHedge; by secid date; run;
proc means data=VIX_dynamicHedge NOPRINT nway;
class secid date;   var stock_ret_square;
output out=Monthly_RV sum=Monthly_RV; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*,b.Monthly_RV
	from VIX_MonthlyPrc a left join Monthly_RV b
	  on a.secid=b.secid and a.date=b.date; quit;

data VIX_MonthlyPrc;  set VIX_MonthlyPrc;
/*Model-free hedge long option portfolio that generates payoff 'Static_VIX_Payoff', short 2/(St*exp{rf*(T-t)}) shares of stock from t to T, and daily model-free hedge. */
Dynamic_VIX_Payoff=Static_VIX_Payoff-2*(St_end/St_start/Rf-1)+Delta_Hedge_payoff;
Dynamic_VIX_Return=Dynamic_VIX_Payoff/VIX_Prc-1; /*Dynamic_VIX_Return is "Simpson's VIX portfolio return with model-free hedge" in Table 2.*/
VSR=Monthly_RV/VIX_Prc-1; /*VSR is "Simpson's variance swap approximation" in Table 2.*/

Dynamic_VIX_Payoff_Corridor = Static_VIX_Payoff - 2*(St_end/St_start/Rf-1) + Delta_Hedge_payoff_Corridor; /* "-2*(St_end/St_start/Rf-1)" is equivalent to the total payoff of investing -2/F0_hat shares in stock each day in Eqn 10. */
Dynamic_VIX_Return_Corridor = Dynamic_VIX_Payoff_Corridor/VIX_Prc - 1; /*Dynamic_VIX_Return_Corridor is "Simpson's VIX portfolio return with model-free corridor hedge" in Table 2.*/

RV_Corridor = -2*log(forward_end_Corridor/forward_start_Corridor) + Delta_Hedge_Corridor_Theory;
VSR_Corridor = RV_Corridor/VIX_Prc-1; /*VSR_Corridor is "Simpson's corridor variance swap approximation" in Table 2.*/
run;

/* Require firm-month to have at least 3 strikes.*/
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.num_sum as num_strikes, b.num_put, b.num_call
	from VIX_MonthlyPrc a left join num_put_eachobs b
	  on a.secid=b.secid and a.date=b.date; quit;
data VIX_MonthlyPrc; set VIX_MonthlyPrc; if num_strikes>2; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.shrcd
	from VIX_MonthlyPrc a left join stock_prc b
	  on a.cusip=b.cusip and a.date=b.date;  quit;


/*****************************************************
***** Black-Scholes Hedged VIX returns ******* *******
******************************************************/
/*The data 'options_daily' is extracted from OptionMetrics. It contains the daily information of those individual stock options in the dataset 'Options' from 3rd Friday to the 3rd Friday next month.*/
data OM; set here.options_daily; keep optionid date secid delta impl_volatility; run;
proc sort data=OM nodupkey; by optionid date; run;
data options; set Options_VIXPort; Rf_daily=log(1+linear_rate/100/365); run;
data filter; set VIX_MonthlyPrc; keep secid date; run;
proc sort data=filter nodupkey; by secid date; run;
data options; merge filter (in=a) options;  by secid date; if a; run;
proc sql;
  create table options as
    select a.*,b.date as date_daily, b.prc as St_daily
	from options a left join stock_prc b
	  on a.cusip=b.cusip and a.date<=b.date<=a.exdate_trade;quit;
proc sort data=options nodupkey; by secid date date_daily strike_price; run;
proc sort data=options nodupkey out=daily_information;by secid date descending date_daily;run;
data daily_information; set daily_information; by secid date; 
St_dailychange=lag(St_daily)-St_daily; days_change=lag(date_daily)-date_daily;
if first.date then St_dailychange=.;  if first.date then days_change=.; run;
data options; set options; if date_daily=exdate_trade then delete; run;

/* Merge delta from OptionMetrics for daily Black-Scholes hedge. If deltas are missing, impute it with the current St and the most recent available IV on the same option contract.*/
proc sql;
  create table daily_hedge as
    select a.*, b.delta, b.impl_volatility as IV
	from options a left join OM b
	  on a.optionid=b.optionid and a.date_daily=b.date; quit;
data delta_nonmissing; set daily_hedge; if delta ne .; run;
data delta_missing; set daily_hedge; if delta = .; run;
proc sql;
  create table delta_missing as
    select a.*, b.IV as IV_missing, b.date_daily as date_close
	from delta_missing a left join delta_nonmissing b
            on a.optionid=b.optionid
              where b.date_daily < a.date_daily
                group by a.optionid, a.date_daily
                  having abs(a.date_daily-b.date_daily)=min(abs(a.date_daily-b.date_daily))
                    order by a.optionid, a.date_daily;quit;
proc sort data=delta_missing nodupkey; by optionid date_daily; run;
data delta_missing;  set delta_missing;  
delta_missing = .;  maturity = exdate_trade-date_daily; 
d1 = (log(St_daily/strike_price)+(365*Rf_daily+IV_missing**2/2)*maturity/365)/(IV_missing*sqrt(maturity/365));
d2 = d1 - IV_missing*sqrt(maturity/365);
if cp_flag='P' then delta_missing = CDF('NORMAL',d1,0,1) - 1;
if cp_flag='C' then delta_missing = CDF('NORMAL',d1,0,1);  run;
proc sql;
  create table daily_hedge as
    select a.*, b.delta_missing
	from daily_hedge a left join delta_missing b
	  on a.optionid=b.optionid and a.date_daily=b.date_daily ;quit;
data daily_hedge; set daily_hedge; if delta=. then delta=delta_missing; run;
proc sort data=daily_hedge; by secid date date_daily strike_price;  run;


/* Each day, aggregate delta across strikes. */
data daily_hedge; set daily_hedge; weight_delta=Weight_eachoption*delta; run;
proc means data=daily_hedge noprint; 
class secid date date_daily; var weight_delta; 
output out=VIX_delta_daily sum=option_delta_daily;  run;
data VIX_delta_daily; set VIX_delta_daily; if secid ne . and date ne . and date_daily ne .; run;
proc sql;
  create table VIX_delta_daily as
    select a.*, b.cusip, b.St_daily, b.St_daily+b.St_dailychange as St_NextDay, b.days_change, b.Rf_daily
	from VIX_delta_daily a left join daily_information b
	  on a.secid=b.secid and a.date=b.date and a.date_daily=b.date_daily;quit;
proc sql;
  create table VIX_delta_daily as
    select a.*, b.K0, b.K1, b.forward, b.VIX_Prc, b.exdate_trade, b.delta_K0 
	from VIX_delta_daily a left join VIX_MonthlyPrc b
	  on a.secid=b.secid and a.date=b.date;quit;

data VIX_delta_daily; set VIX_delta_daily; 
/*Adjust deltas of option portfolio for: 
1. ( (K1-K0)/3*(1/K0**2-1/K1**2)+(2/Forward-1/K0-1/K1) ) shares of stocks in VIX portfolio;
2. short 2/(St*exp{rf*(T-t)}) shares of stock. */
delta_daily = option_delta_daily + ( (K1-K0)/3*(1/K0**2-1/K1**2)+(2/Forward-1/K0-1/K1) )-2/forward;
run;

data VIX_delta_daily; set VIX_delta_daily; next_trade_day = date_daily+days_change; run;
proc sql;
  create table VIX_delta_daily as
    select a.*, b.ret as stock_ret_next_day
	from VIX_delta_daily a left join stock_prc b
	  on a.cusip=b.cusip and a.next_trade_day=b.date;quit;
data VIX_delta_daily; set VIX_delta_daily;  
BS_Payoff_daily= -delta_daily*( St_NextDay - St_daily*exp(Rf_daily*days_change) )*exp(Rf_daily*(exdate_trade-next_trade_day));
run;
proc sort data=VIX_delta_daily; by secid date date_daily;  run;
proc means data=VIX_delta_daily noprint; 
class secid date;   var BS_Payoff_daily; 
output out=Hedge_Payoff  sum=BS_Hedge_Payoff; run;
data Hedge_Payoff; set Hedge_Payoff; if secid ne . and date ne .; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.BS_Hedge_Payoff
	from VIX_MonthlyPrc a left join Hedge_Payoff b
	  on a.secid=b.secid and a.date=b.date;quit;
data VIX_MonthlyPrc;  set VIX_MonthlyPrc;
BS_VIX_Payoff=Static_VIX_Payoff-2*(St_end/St_start/Rf-1)+BS_Hedge_Payoff;
BS_VIX_Return=BS_VIX_Payoff/VIX_Prc - 1; /*BS_VIX_Return is "Simpson’s VIX portfolio return (unhedged)" in Table 2.*/
run;


/*The following code generates the first 6 rows in Table 2.*/
proc means data=VIX_MonthlyPrc mean std P10 median P90; where shrcd=10 | shrcd=11; 
var Static_VIX_Return BS_VIX_Return Dynamic_VIX_Return Dynamic_VIX_Return_Corridor VSR VSR_Corridor ;  run;


*************************************************************
******Table 1: Use half options to get VIX prices ***********
*************************************************************;
/*This section generates the block "Simpson's formula" in Table 1. */
proc sort data=options_half_strikes; by secid date strike_price; run;
data options; retain count; set options_half_strikes;
count + 1; by secid date; if first.secid | first.date then count = 1; run;
proc sql;
  create table options as
    select a.*,b.num_strikes, b.num_put, b.num_call
	from options a left join VIX_MonthlyPrc b
	  on a.secid=b.secid and a.date=b.date;quit;
data options; set options; if num_strikes ne .;  run;
data options;  set options; if mod(num_strikes,2)=1; 
if num_strikes>6; if num_put>2; if num_call>2; run;
proc sort data=options; by secid date strike_price;run;
data options; set options; if mod(count,2)=1; run;

/*Below just repeats the steps to recompute VIX prices.*/
data options_findK0; set options;distance_toForward=Forward-strike_price; if distance_toForward<0 then delete; run;
proc sort data=options_findK0; by secid date distance_toForward; run;
data options_findK0; set options_findK0; by secid date; if first.secid | first.date; run;
data options_findK0; set options_findK0; rename strike_price=K0; run;
data options_findK0; set options_findK0; if K0 ne .;  run;
proc sql;
  create table options as
    select a.*, b.K0
	from options a left join options_findK0 b
	  on a.secid=b.secid and a.date=b.date; quit;
data options; set options; if K0 ne .; run;
data options_findK1; set options;  distance_toForward=strike_price-Forward; if distance_toForward<0 then delete; run;
proc sort data=options_findK1; by secid date distance_toForward; run;
data options_findK1; set options_findK1; by secid date; if first.secid | first.date; run;
data options_findK1; set options_findK1; rename strike_price=K1; run;
proc sql;
  create table options as
    select a.*, b.K1 
	from options a left join options_findK1 b
	  on a.secid=b.secid and a.date=b.date;quit;
data options; set options;  if K1 ne .; run;
data options_at_K0_K1; set options; if strike_price=K0 | strike_price=K1; run;
data options_weight;  set options; run;
proc sort data=options_weight; by secid date strike_price; run;
data options_weight; set options_weight;
by secid date ;  lagged_strike_price=lag(strike_price);
if first.secid | first.date then lagged_strike_price=.; run;
proc sort data=options_weight; by secid date descending strike_price descending cp_flag;run;
data options_weight; set options_weight; by secid date; 
lead_strike_price=lag(strike_price); if first.secid | first.date  then lead_strike_price=.; run;
proc sort data=options_weight; by secid date strike_price descending cp_flag; run;
data options_weight; set options_weight;  by secid date ;
delta_K=(lead_strike_price-lagged_strike_price)/2;
if first.secid | first.date then delta_K=lead_strike_price-strike_price;
if last.secid | last.date then delta_K=strike_price-lagged_strike_price; run;
data options_weight;  set options_weight;
Weight_eachoption=2*delta_K/(strike_price**2);
if strike_price=K0 then Weight_eachoption = Weight_eachoption+(K1-K0-delta_K)/3/(K0**2);
if strike_price=K1 then Weight_eachoption = Weight_eachoption+(K1-K0-delta_K)/3/(K1**2);
weight_times_price=Weight_eachoption*mid_quote; run;
data options_weight_at_K0_K1; set options_weight; if strike_price=K0 | strike_price=K1; run;
proc sort data=options_weight; by secid date strike_price; run;

proc means data=options_weight NOPRINT nway;
class secid date; var weight_times_price; output out=sigma2_each_exdate  sum=sigma2;run;
proc sql;
  create table sigma2_each_exdate as
    select a.*,b.Forward, b.K0, b.days_expire
	from sigma2_each_exdate a left join options_weight b
	  on a.secid=b.secid and a.date=b.date;  quit;
proc sort data=sigma2_each_exdate nodupkey; by secid date; run;
proc sql;
  create table VIX_Prc_Half as
    select a.*,b.linear_rate
	from sigma2_each_exdate a left join ZeroCouponYieldCurve b
	  on a.date=b.date and b.days=a.days_expire;quit;
proc sort data=VIX_Prc_Half; by secid date; run;

proc sort data=stock_prc; by cusip date; run;
proc sort data=options_weight; by cusip exdate; run;
proc sql;
  create table options_weight as
    select a.*,b.prc as stock_prc_end
	from options_weight a left join stock_prc b
	  on a.cusip=b.cusip and a.exdate_trade=b.date;quit;
data options_weight; set options_weight;   
if stock_prc_end ne . ; 
if cp_flag='C' then option_payoff=max(stock_prc_end-strike_price,0);
if cp_flag='P' then option_payoff=max(strike_price-stock_prc_end,0);
Option_TerminalPayoff=Weight_eachoption*option_payoff; run;
proc sort data=options_weight; by secid date strike_price; run;
proc means data=options_weight  NOPRINT nway;
class secid date;  var Option_TerminalPayoff;
output out=actual_VIXPort_payoff sum=Option_TerminalPayoff; run;
proc sql;
  create table VIX_Prc_Half as
    select a.*,b.Option_TerminalPayoff 
	from VIX_Prc_Half a left join actual_VIXPort_payoff b
	on a.secid=b.secid and a.date=b.date;  quit;
proc sort data=options_weight nodupkey out=identifier; by secid date; run;
proc sql;
  create table VIX_Prc_Half as
    select a.*,b.cusip, b.exdate_trade
	from VIX_Prc_Half a left join identifier b
	  on a.secid=b.secid and a.date=b.date;quit;
proc sort data=VIX_Prc_Half; by cusip date; run;
proc sql;
  create table VIX_Prc_Half as
    select a.*, b.prc as St_start
	from VIX_Prc_Half a left join stock_prc b
	on a.cusip=b.cusip and a.date=b.date;   quit;
proc sql;
  create table VIX_Prc_Half as
    select a.*, b.prc as St_end
	from VIX_Prc_Half a left join stock_prc b
	on a.cusip=b.cusip and a.exdate_trade=b.date;   quit;
proc sql;
  create table VIX_Prc_Half as
    select a.*, b.K1
	from VIX_Prc_Half a left join options_findK1 b
	on a.secid=b.secid and a.date=b.date ;  quit;
data delta_K0; set options_weight_at_K0_K1; if strike_price=K0;  run;
data delta_K1; set options_weight_at_K0_K1; if strike_price=K1;  run;
proc sql;
  create table VIX_Prc_Half as
    select a.*, b.delta_K as delta_K0
	from VIX_Prc_Half a left join delta_K0 b
	on a.secid=b.secid and a.date=b.date ;  quit;
proc sql;
  create table VIX_Prc_Half as
    select a.*, b.delta_K as delta_K1
	from VIX_Prc_Half a left join delta_K1 b
	on a.secid=b.secid and a.date=b.date ;  quit;
data VIX_Prc_Half; set VIX_Prc_Half; 
Rf=exp(linear_rate/100*days_expire/365);
VIX_Prc =sigma2 + ( (K1-K0)/3 * (1/K0**2 - 1/K1**2) + (2/Forward - 1/K0 - 1/K1) ) * St_start 
+ ( (K1-K0)/3 * (1/K1 - 1/K0) + ( log(forward/K0) + log(forward/K1) ) ) / Rf; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.VIX_Prc as VIX_Prc_Half_Strike
	from VIX_MonthlyPrc a left join VIX_Prc_Half b
	on a.secid=b.secid and a.date=b.date ;  quit;

/*The code below generates the section "Simpson's formula" in Table 1.*/
data Table1; set VIX_MonthlyPrc; 
error=(VIX_Prc_Half_Strike-VIX_Prc)/VIX_Prc; absolute_error=abs(error); run;

proc means data=Table1 mean std P10 median P90; var absolute_error error;  run;
proc means data=Table1 mean std P10 median P90; where num_strikes=7; var absolute_error error;  run;
proc means data=Table1 mean std P10 median P90; where num_strikes=11; var absolute_error error;  run;
proc means data=Table1 mean std P10 median P90; where num_strikes=15; var absolute_error error;  run;


/****************************************************************
**** Interpolate IV with 500 grids within [K_min, K_max] ********
*****************************************************************/
/*This section generates the last row "Implied volatility surface corridor variance swap approximation" in Table 2.*/
data options; set options_interpo_extrapo; keep secid date exdate exdate_trade days_expire cp_flag strike_price forward mid_quote impl_volatility St_start linear_rate; run;

proc sort data=VIX_MonthlyPrc nodupkey out=filter; by secid date; run;
data filter;  set filter; keep secid date;  run;
data options; merge filter (in=a) options;  by secid date;  if a;  run;
proc sort data=options; by secid date strike_price; run;

proc sql;
  create table options as
    select a.*, b.strike_min, b.strike_max, b.IV_avg, b.delta_min, b.delta_max
	from options a left join strike_interval b
	on a.secid=b.secid and a.date=b.date ;  quit;
proc sort data=options nodupkey; by secid date strike_price; run;
data strike_interpolate; set options; if strike_price=strike_min | strike_price=strike_max; run;
proc sort data=strike_interpolate; by secid date strike_price; run;
proc expand data=strike_interpolate out=strike_grid FACTOR=(500:1);
convert strike_price=strike_grid / method=join; by secid date; id strike_price; run;
data strike_grid; set strike_grid; drop strike_price;run;
data strike_grid; set strike_grid;  strike_grid=input(strike_grid,best12.);  run;
proc sql;
  create table options_strike_grid_closest as
    select a.*, b.strike_grid as strike_grid_closest
	from options a left join strike_grid b
            on a.secid=b.secid and a.date=b.date
                group by a.secid, a.date, a.strike_price
             having abs(a.strike_price-b.strike_grid)=min(abs(a.strike_price-b.strike_grid))
                    order by a.secid, a.date, a.strike_price;quit;
proc sort data=options_strike_grid_closest nodupkey; by secid date strike_price; run;
proc sql;
  create table IV_grid  as
    select a.*, b.impl_volatility as IV
	from strike_grid a left join options_strike_grid_closest b
	on a.secid=b.secid and a.date=b.date and a.strike_grid=b.strike_grid_closest;  quit;
proc sort data=IV_grid nodupkey; by secid date strike_grid; run;
proc expand data=IV_grid out=IV_grid;convert IV / method=join; by secid date; id strike_grid; run;

/* Compute option prices using BS. */
proc sort data=options nodupkey out=dummy; by secid date; run;
proc sql;
  create table IV_grid  as
    select a.*, b.days_expire as maturity, b.St_start, b.Forward, b.linear_rate/100/365 as Rf_daily
	from IV_grid a left join dummy b
	on a.secid=b.secid and a.date=b.date;  quit;
data IV_grid; set IV_grid; strike_price=strike_grid;
if strike_price<=Forward then cp_flag='P'; if strike_price>Forward  then cp_flag='C'; run;
data IV_grid;  set IV_grid; 
d1=(log(St_start/strike_price)+(365*Rf_daily+IV**2/2)*maturity/365)/(IV*sqrt(maturity/365));
d2=d1 - IV*sqrt(maturity/365);
if cp_flag='P' then mid_quote = strike_price*exp(-Rf_daily*maturity)*CDF('NORMAL',-d2,0,1) - St_start*CDF('NORMAL',-d1,0,1);
if cp_flag='C' then mid_quote = St_start*CDF('NORMAL',d1,0,1) - strike_price*exp(-Rf_daily*maturity)*CDF('NORMAL',d2,0,1) ;  run;
proc sort data=IV_grid nodupkey; by secid date strike_price; run;

/*The code below repeats the steps to recompute VIX prices. */
data options_weight; set IV_grid; drop d1 d2;  run;
data options_weight; set options_weight; by secid date ; 
lagged_strike_price=lag(strike_price); if first.secid | first.date then lagged_strike_price=.; run;
proc sort data=options_weight; by secid date descending strike_price;run;
data options_weight; set options_weight; by secid date;   
lead_strike_price=lag(strike_price); if first.secid | first.date then lead_strike_price=.; run;
proc sort data=options_weight; by secid date strike_price; run;
data options_weight; set options_weight;  by secid date ;
delta_K=(lead_strike_price-lagged_strike_price)/2;
if first.secid | first.date then delta_K=lead_strike_price-strike_price;
if last.secid | last.date then delta_K=strike_price-lagged_strike_price; run;
data options_weight;  set options_weight; Weight_eachoption=2*delta_K/(strike_price**2); 
weight_times_price=Weight_eachoption*mid_quote; run;
proc means data=options_weight NOPRINT nway; class secid date; 
var weight_times_price; output out=VIX_Prc_Interpolate  sum=VIX_Prc_Interpolate;run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*,b.VIX_Prc_Interpolate
	from VIX_MonthlyPrc a left join VIX_Prc_Interpolate b
	  on a.secid=b.secid and a.date=b.date;  quit;

/* Recompute corridor RV in [K_min, K_max] */
data VIX_MonthlyPrc2; set VIX_MonthlyPrc; 
if forward<strike_min then forward_start_Corridor=strike_min;
else if strike_min<=forward<=strike_max then forward_start_Corridor=forward; else forward_start_Corridor=strike_max;
if St_end<strike_min then forward_end_Corridor=strike_min;
else if strike_min<=St_end<=strike_max then forward_end_Corridor=St_end; else forward_end_Corridor=strike_max; run;
proc sql;
  create table VIX_dynamicHedge as
    select a.*,b.date as date_daily, b.ret as stock_ret, b.prc as St_daily_Corridor
	from VIX_MonthlyPrc2 a left join stock_prc b
	  on a.cusip=b.cusip and a.date<=b.date<=a.exdate;quit;
data VIX_dynamicHedge; set VIX_dynamicHedge; Rf_daily=exp(linear_rate/100/365);
Forward_daily=St_daily_Corridor*exp(linear_rate/100*(exdate_trade-date_daily)/365);  run;
data VIX_dynamicHedge; set VIX_dynamicHedge;
if Forward_daily<strike_min then Forward_daily_Corridor=strike_min;
else if strike_min<=Forward_daily<=strike_max then Forward_daily_Corridor=Forward_daily; else Forward_daily_Corridor=strike_max;   run;
proc sort data=VIX_dynamicHedge; by secid date date_daily; run;
data VIX_dynamicHedge; set VIX_dynamicHedge; by secid date;
Delta_Hedge_Corridor_Theory =2 * (Forward_daily/Forward_daily_Corridor) * (Forward_daily_Corridor/lag(Forward_daily_Corridor)-1);run;
data VIX_dynamicHedge; set VIX_dynamicHedge; if date_daily=date then delete;  run;
proc sort data=VIX_dynamicHedge;by secid date;run;
proc means data=VIX_dynamicHedge NOPRINT nway; class secid date; 
var Delta_Hedge_Corridor_Theory; output out=Delta_Hedge_payoff  sum= Delta_Hedge_Corridor_Theory; run;
data VIX_MonthlyPrc2;  set VIX_MonthlyPrc2; drop Delta_Hedge_Corridor_Theory; run;
proc sql;
  create table VIX_MonthlyPrc2 as
    select a.*, b.Delta_Hedge_Corridor_Theory
	from VIX_MonthlyPrc2 a left join Delta_Hedge_payoff b
	  on a.secid=b.secid and a.date=b.date; quit;
data VIX_MonthlyPrc2;  set VIX_MonthlyPrc2;
RV_Corridor = -2*log(forward_end_Corridor/forward_start_Corridor) + Delta_Hedge_Corridor_Theory;
VSR_Corridor_Interpolate = RV_Corridor/VIX_Prc_Interpolate-1; /*VSR_Corridor_Interpolate is "Implied volatility surface corridor variance swap approximation" in Table 2.*/
run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.VSR_Corridor_Interpolate
	from VIX_MonthlyPrc a left join VIX_MonthlyPrc2 b
	  on a.secid=b.secid and a.date=b.date; quit;

/*The code below generates the last row "Implied volatility surface corridor variance swap approximation" in Table 2.*/
proc means data=VIX_MonthlyPrc mean std P10 median P90; var VSR_Corridor_Interpolate;  run;


/*Output data to be used in other tables later. Define 'output' as your own path.*/
data here.simpson_return; set VIX_MonthlyPrc; Rf=Rf-1;
keep secid cusip permno shrcd date exdate exdate_trade VIX_Prc Monthly_RV Dynamic_VIX_Return VSR BS_VIX_Return Dynamic_VIX_Return_Corridor VSR_Corridor Rf VIX_BA_percent mkt_cap num_strikes num_put num_call forward strike_min strike_max IV_avg VSR_Corridor_Interpolate;  run;



*************************************************************
************* CBOE method for VIX portfolio ****************
*************************************************************;
data options;  set here.options;
if open_interest>0;  
if delta ne .;
if best_bid=0 then delete;  
if best_bid>best_offer then delete; 
strike_price=strike_price/1000; 
Mid_quote=(best_offer+best_bid)/2;
days_expire=exdate_trade-date;  run;
proc sort data=options nodupkey; by secid date exdate strike_price cp_flag; run;
proc sort data=options nodupkey out=filter; by secid date; run;
data dividend; set stock_prc; where divamt>0; run;
proc sql;
  create table firm_divd as
    select a.*, b.divamt
	from filter a left join dividend b
	  on a.cusip=b.cusip and a.date<b.date<=a.exdate_trade;quit;
proc sort data=firm_divd; by secid date;run;
proc means data=firm_divd NOPRINT nway;
class secid date; var divamt; output out=firm_month_divd  sum=divamt;run;
proc sql;
  create table filter as
    select a.*, b.divamt 
	from filter a left join firm_month_divd b
	  on a.secid=b.secid and a.date=b.date;quit;
data filter; set filter; if divamt=.; run;
proc sort data=filter; by secid date; run;
data options; merge filter (in=a) options;  by secid date;  if a;  run;

proc sort data=options nodupkey out=filter; by secid date; run;
data stock_split; set crsp.dsedist; if FACSHR ne 0; split_flag=1; run;
proc sql;
  create table filter as
    select a.*,b.split_flag
	from filter a left join stock_split b
	  on a.cusip=b.cusip and a.date<b.exdt<=a.exdate_trade;quit;
proc sort data=filter nodupkey; by secid date;  run;
data filter; set filter; if split_flag ne 1; run;
proc sort data=options;  by secid date;  run;
data options; merge filter (in=a) options; by secid date; if a;  run;

proc sql;
  create table options as
    select a.*, b.prc as St_start
	from options a left join stock_prc b
	on a.cusip=b.cusip and a.date=b.date; quit;
proc sort data=options nodupkey; by secid date strike_price descending cp_flag; run;
data options; set options; if 5=<st_start; run;

proc sql;
  create table options as
    select a.*, b.shrcd
	from options a left join stock_prc b
	  on a.cusip=b.cusip and a.date=b.date;  quit;
data options; set options; if shrcd=10 | shrcd=11;; run;

data options_findForward; set options; run;
proc sort data=options_findForward nodupkey; by secid date; run;
proc sql;
  create table options_findForward as
    select a.*,b.linear_rate
	from options_findForward a left join ZeroCouponYieldCurve b
	  on a.date=b.date and a.exdate_trade=b.date+b.days;  quit;
proc sort data=options_findForward; by secid date; run;
proc sql;
  create table options_findForward as
    select a.*,b.prc as stock_prc_start
	from options_findForward a left join stock_prc b
	  on a.cusip=b.cusip and a.date=b.date;  quit;
proc sort data=options_findForward nodupkey; by cusip date; run;
data options_findForward;  set options_findForward;
Forward=stock_prc_start*exp(linear_rate/100*days_expire/365); run;
proc sql;
  create table options as
    select a.*,b.Forward,  b.linear_rate
	from options a left join options_findForward b
	  on a.secid=b.secid and a.date=b.date; quit;
data options;   set options;
if cp_flag="P" and strike_price>forward then delete;
if cp_flag="C" and strike_price<=forward then delete;  run;
proc sort data=options; by secid date strike_price; run;

data options;  set options; 
if cp_flag='P' and strike_price<best_bid then delete;
if cp_flag='P' and best_offer<max(0,strike_price-st_start) then delete;
if cp_flag='C' and st_start<best_bid then delete;
if cp_flag='C' and best_offer<max(0,st_start-strike_price) then delete; run;
data options;retain secid date exdate exdate_trade days_expire cp_flag strike_price forward mid_quote;set options; run;

data options_half_strikes; set options; run;

data options_findK0; set options; distance_toForward=Forward-strike_price; if distance_toForward<0 then delete; run;
proc sort data=options_findK0; by secid date distance_toForward; run;
data options_findK0; set options_findK0; by secid date; if first.secid | first.date; run;
data options_findK0; set options_findK0; rename strike_price=K0; run;
proc sql;
  create table options as
    select a.*, b.K0
	from options a left join options_findK0 b
	  on a.secid=b.secid and a.date=b.date; quit;
data options; set options; if K0 ne .; run;

data options_findK1; set options; distance_toForward=strike_price-Forward; if distance_toForward<0 then delete; run;
proc sort data=options_findK1; by secid date distance_toForward; run;
data options_findK1; set options_findK1; by secid date; if first.secid | first.date; run;
data options_findK1; set options_findK1; rename strike_price=K1; run;
proc sql;
  create table options as
    select a.*, b.K1 
	from options a left join options_findK1 b
	  on a.secid=b.secid and a.date=b.date;quit;
data options; set options;  if K1 ne .; run;
data options_at_K0_K1; set options; if strike_price=K0 | strike_price=K1; run;

data call_used; set options; if cp_flag='C'; run;
proc sort data=call_used; by secid date strike_price; run;
data put_used; set options; if cp_flag='P'; run;
proc sort data=put_used; by secid date descending strike_price;run;
proc means data=call_used NOPRINT nway;
class secid date;   var strike_price;
output out=num_call_eachobs n=num_call; run;
proc means data=put_used NOPRINT nway;
class secid date;  var strike_price;
output out=num_put_eachobs n=num_put; run;
proc sql;
  create table num_put_eachobs as
    select a.*,b.num_call
	from num_put_eachobs a left join num_call_eachobs b
	on a.secid=b.secid and a.date=b.date;  quit;
data num_put_eachobs;  set num_put_eachobs; if num_call ne .;
num_min=min(num_put,num_call); num_sum=num_put+num_call ; run;
proc sort data=options; by secid date strike_price; run;
proc means data=options NOPRINT nway;
class secid date; var strike_price; output out=strike_interval min=strike_min max=strike_max; run;

data options_weight; set options; run;
proc sort data=options_weight; by secid date strike_price; run;
data options_weight; set options_weight;
by secid date; lagged_strike_price=lag(strike_price);if first.secid | first.date then lagged_strike_price=.; run;
proc sort data=options_weight; by secid date descending strike_price descending cp_flag;run;
data options_weight; set options_weight;
by secid date; lead_strike_price=lag(strike_price);
if first.secid | first.date  then lead_strike_price=.; run;
proc sort data=options_weight; by secid date strike_price descending cp_flag; run;
data options_weight; set options_weight;  by secid date ;
delta_K=(lead_strike_price-lagged_strike_price)/2;
if first.secid | first.date then delta_K=lead_strike_price-strike_price;
if last.secid | last.date then delta_K=strike_price-lagged_strike_price; run;

data options_weight;  set options_weight;
Weight_eachoption=2*delta_K/(strike_price**2);
weight_times_price=Weight_eachoption*mid_quote;
weight_times_price_bid=Weight_eachoption*best_bid;
weight_times_price_ask=Weight_eachoption*best_offer; run;

data options_weight_at_K0_K1; set options_weight; if strike_price=K0 | strike_price=K1; run;
proc sql;
  create table strike_interval as
    select a.*,b.delta_K as delta_min
	from strike_interval a left join options_weight b
	on a.secid=b.secid and a.date=b.date and a.strike_min=b.strike_price; quit;
proc sql;
  create table strike_interval as
    select a.*,b.delta_K as delta_max
	from strike_interval a left join options_weight b
	on a.secid=b.secid and a.date=b.date and a.strike_max=b.strike_price; quit;

proc sort data=options_weight; by secid date strike_price; run;
proc means data=options_weight NOPRINT nway;
class secid date;  
var weight_times_price weight_times_price_bid weight_times_price_ask ;
output out=sigma2_each_exdate  sum=sigma2 sigma2_bid sigma2_ask ; run;
proc sql;
  create table sigma2_each_exdate as
    select a.*,b.Forward, b.K0, b.days_expire
	from sigma2_each_exdate a left join options_weight b
	  on a.secid=b.secid and a.date=b.date;  quit;
proc sort data=sigma2_each_exdate nodupkey; by secid date; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*,b.linear_rate
	from sigma2_each_exdate a left join ZeroCouponYieldCurve b
	  on a.date=b.date and b.days=a.days_expire;quit;
proc sort data=VIX_MonthlyPrc; by secid date; run;

proc sort data=options_weight; by cusip exdate; run;
proc sql;
  create table options_weight as
    select a.*,b.prc as stock_prc_end
	from options_weight a left join stock_prc b
	  on a.cusip=b.cusip and a.exdate_trade=b.date;quit;
data options_weight; set options_weight;   
if stock_prc_end ne . ; 
if cp_flag='C' then option_payoff=max(stock_prc_end-strike_price,0);
if cp_flag='P' then option_payoff=max(strike_price-stock_prc_end,0);
Option_TerminalPayoff=Weight_eachoption*option_payoff; run;
proc sort data=options_weight; by secid date strike_price; run;
proc means data=options_weight  NOPRINT nway;
class secid date; var Option_TerminalPayoff;
output out=actual_VIXPort_payoff sum=Option_TerminalPayoff; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*,b.Option_TerminalPayoff 
	from VIX_MonthlyPrc a left join actual_VIXPort_payoff b
	on a.secid=b.secid and a.date=b.date;  quit;

proc sort data=options_weight nodupkey out=identifier; by secid date; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*,b.cusip, b.exdate_trade
	from VIX_MonthlyPrc a left join identifier b
	  on a.secid=b.secid and a.date=b.date;quit;
proc sort data=VIX_MonthlyPrc; by cusip date; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.prc as St_start, b.prc*b.shrout*1000/1000000000 as mkt_cap, b.permno
	from VIX_MonthlyPrc a left join stock_prc b
	on a.cusip=b.cusip and a.date=b.date;   quit;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.prc as St_end
	from VIX_MonthlyPrc a left join stock_prc b
	on a.cusip=b.cusip and a.exdate_trade=b.date;   quit;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.K1
	from VIX_MonthlyPrc a left join options_findK1 b
	on a.secid=b.secid and a.date=b.date ;  quit;
data delta_K0; set options_weight_at_K0_K1; if strike_price=K0; run;
data delta_K1; set options_weight_at_K0_K1; if strike_price=K1;  run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.delta_K as delta_K0
	from VIX_MonthlyPrc a left join delta_K0 b
	on a.secid=b.secid and a.date=b.date ;  quit;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.delta_K as delta_K1
	from VIX_MonthlyPrc a left join delta_K1 b
	on a.secid=b.secid and a.date=b.date ;  quit;


data VIX_MonthlyPrc; set VIX_MonthlyPrc; 
Rf=exp(linear_rate/100*days_expire/365);

/*The actual payoff of VIX portfolio is the sum of the option portfolio in Eqn (2), (delta_K0-forward0+K0)/K0**2 shares of stocks and (delta_K0-forward0+K0)/K0/Rf dollar in risk-free bonds.*/
Static_VIX_Payoff = Option_TerminalPayoff + (delta_K0-forward+K0)/K0**2 * St_end - (delta_K0-forward+K0)/K0;

/* VIX_Prc is the price of VIX portfolio constructed with CBOE method in Eqn (2) of the paper. */
VIX_Prc = sigma2 + (delta_K0-forward+K0)/K0**2 * St_start - (delta_K0-forward+K0)/K0/Rf;

Static_VIX_Return = Static_VIX_Payoff/VIX_Prc-1;  

VIX_Prc_bid = sigma2_bid + (delta_K0-forward+K0)/K0**2 * St_start - (delta_K0-forward+K0)/K0/Rf;
VIX_Prc_ask = sigma2_ask + (delta_K0-forward+K0)/K0**2 * St_start - (delta_K0-forward+K0)/K0/Rf;
VIX_BA_percent = (VIX_Prc_ask-VIX_Prc_bid)/VIX_Prc;  
if VIX_Prc_bid>0;  run;

proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.strike_min, b.strike_max, b.delta_min, b.delta_max
	from VIX_MonthlyPrc a left join strike_interval b
	  on a.secid=b.secid and a.date=b.date; quit;
data VIX_MonthlyPrc; set VIX_MonthlyPrc; 
if forward<strike_min-delta_min/2 then forward_start_Corridor=strike_min-delta_min/2;
else if strike_min-delta_min/2<=forward<=strike_max+delta_max/2 then forward_start_Corridor=forward;
else forward_start_Corridor=strike_max+delta_max/2;

if St_end<strike_min-delta_min/2 then forward_end_Corridor=strike_min-delta_min/2;
else if strike_min-delta_min/2<=St_end<=strike_max+delta_max/2 then forward_end_Corridor=St_end;
else forward_end_Corridor=strike_max+delta_max/2;
run;
proc sort data=options nodupkey out=dummy; by secid date; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.exdate
	from VIX_MonthlyPrc a left join dummy b
	on a.secid=b.secid and a.date=b.date;   quit;
proc sql;
  create table VIX_dynamicHedge as
    select a.*,b.date as date_daily, b.ret as stock_ret, b.prc as St_daily_Corridor
	from VIX_MonthlyPrc a left join stock_prc b
	  on a.cusip=b.cusip and a.date<=b.date<=a.exdate;quit;
data VIX_dynamicHedge; set VIX_dynamicHedge; Rf_daily=exp(linear_rate/100/365);
Forward_daily=St_daily_Corridor*exp(linear_rate/100*(exdate_trade-date_daily)/365);  run;

data VIX_dynamicHedge; set VIX_dynamicHedge;
if Forward_daily<strike_min-delta_min/2 then Forward_daily_Corridor=strike_min-delta_min/2;
else if strike_min-delta_min/2<=Forward_daily<=strike_max+delta_max/2 then Forward_daily_Corridor=Forward_daily;
else Forward_daily_Corridor=strike_max+delta_max/2;   run;
proc sort data=VIX_dynamicHedge; by secid date date_daily; run;

data VIX_dynamicHedge; set VIX_dynamicHedge; by secid date;
Delta_Hedge_Reinvt=2/(Rf_daily**(exdate_trade-lag(date_daily)))*(1+stock_ret - Rf_daily**(date_daily-lag(date_daily)))*(Rf_daily**(exdate_trade-date_daily));
Delta_Hedge_Corridor = 2/lag(Forward_daily_Corridor)*lag(St_daily_Corridor) * (1+stock_ret- Rf_daily**(date_daily-lag(date_daily))) * Rf_daily**(exdate_trade-date_daily);
Delta_Hedge_Corridor_Theory =2*(Forward_daily/Forward_daily_Corridor)*(Forward_daily_Corridor/lag(Forward_daily_Corridor)-1);
run;

data VIX_dynamicHedge; set VIX_dynamicHedge; if date_daily=date then delete;  run;
proc sort data=VIX_dynamicHedge;by secid date;run;
proc means data=VIX_dynamicHedge NOPRINT nway;
class secid date; var Delta_Hedge_Reinvt Delta_Hedge_Corridor Delta_Hedge_Corridor_Theory;
output out=Delta_Hedge_payoff  sum=Delta_Hedge_payoff Delta_Hedge_payoff_Corridor Delta_Hedge_Corridor_Theory; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*,b.Delta_Hedge_payoff, b.Delta_Hedge_payoff_Corridor, b.Delta_Hedge_Corridor_Theory
	from VIX_MonthlyPrc a left join Delta_Hedge_payoff b
	  on a.secid=b.secid and a.date=b.date; quit;
data VIX_dynamicHedge; set VIX_dynamicHedge; stock_ret_square=stock_ret**2; run;
proc sort data=VIX_dynamicHedge; by secid date; run;
proc means data=VIX_dynamicHedge NOPRINT nway;
class secid date;   var stock_ret_square;
output out=Monthly_RV sum=Monthly_RV; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*,b.Monthly_RV
	from VIX_MonthlyPrc a left join Monthly_RV b
	  on a.secid=b.secid and a.date=b.date; quit;

data VIX_MonthlyPrc;  set VIX_MonthlyPrc;
Dynamic_VIX_Payoff=Static_VIX_Payoff-2*(St_end/St_start/Rf-1)+Delta_Hedge_payoff;
Dynamic_VIX_Return=Dynamic_VIX_Payoff/VIX_Prc-1; 
VSR=Monthly_RV/VIX_Prc-1; /*VSR is "CBOE variance swap approximation" in Table 2.*/

Dynamic_VIX_Payoff_Corridor = Static_VIX_Payoff - 2*(St_end/St_start/Rf-1) + Delta_Hedge_payoff_Corridor;
Dynamic_VIX_Return_Corridor = Dynamic_VIX_Payoff_Corridor/VIX_Prc - 1; 

RV_Corridor = -2*log(forward_end_Corridor/forward_start_Corridor) + Delta_Hedge_Corridor_Theory;
VSR_Corridor = RV_Corridor/VIX_Prc-1; /*VSR_Corridor is "CBOE corridor variance swap approximation" in Table 2.*/
run;

proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.num_sum as num_strikes, b.num_put, b.num_call
	from VIX_MonthlyPrc a left join num_put_eachobs b
	  on a.secid=b.secid and a.date=b.date; quit;
data VIX_MonthlyPrc; set VIX_MonthlyPrc; if num_strikes>2; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.shrcd
	from VIX_MonthlyPrc a left join stock_prc b
	  on a.cusip=b.cusip and a.date=b.date;  quit;


/*The code below generates Row 7&8 ("CBOE variance swap approximation";"CBOE corridor variance swap approximation") in Table 2.*/
proc means data=VIX_MonthlyPrc mean std P10 median P90; var VSR VSR_Corridor; run;


/*Output data to be used in other tables later.*/
data here.cboe_return_corridor; set VIX_MonthlyPrc; Rf=Rf-1;
keep secid cusip permno shrcd date exdate exdate_trade VIX_Prc Monthly_RV Dynamic_VIX_Return VSR Dynamic_VIX_Return_Corridor VSR_Corridor Rf VIX_BA_percent mkt_cap num_strikes num_put num_call forward strike_min strike_max;  run;




*************************************************************
**** Use half options to get CBOE VIX prices in Table 1******
*************************************************************;
/*This section generates the block "CBOE formula" in Table 1. */
proc sort data=options_half_strikes; by secid date strike_price; run;
data options; retain count; set options_half_strikes;
count + 1; by secid date; if first.secid | first.date then count = 1; run;
proc sql;
  create table options as
    select a.*,b.num_strikes, b.num_put, b.num_call
	from options a left join VIX_MonthlyPrc b
	  on a.secid=b.secid and a.date=b.date;quit;
data options; set options; if num_strikes ne .;  run;
data options;  set options; if mod(num_strikes,2)=1; 
if num_strikes>6; if num_put>2; if num_call>2; run;
proc sort data=options; by secid date strike_price;run;
data options; set options; if mod(count,2)=1; run;

data options_findK0; set options;distance_toForward=Forward-strike_price; if distance_toForward<0 then delete; run;
proc sort data=options_findK0; by secid date distance_toForward; run;
data options_findK0; set options_findK0; by secid date; if first.secid | first.date; run;
data options_findK0; set options_findK0; rename strike_price=K0; run;
data options_findK0; set options_findK0; if K0 ne .;  run;
proc sql;
  create table options as
    select a.*, b.K0
	from options a left join options_findK0 b
	  on a.secid=b.secid and a.date=b.date; quit;
data options; set options; if K0 ne .; run;
data options_findK1; set options;  distance_toForward=strike_price-Forward; if distance_toForward<0 then delete; run;
proc sort data=options_findK1; by secid date distance_toForward; run;
data options_findK1; set options_findK1; by secid date; if first.secid | first.date; run;
data options_findK1; set options_findK1; rename strike_price=K1; run;
proc sql;
  create table options as
    select a.*, b.K1 
	from options a left join options_findK1 b
	  on a.secid=b.secid and a.date=b.date;quit;
data options; set options;  if K1 ne .; run;
data options_at_K0_K1; set options; if strike_price=K0 | strike_price=K1; run;
data options_weight;  set options; run;
proc sort data=options_weight; by secid date strike_price; run;
data options_weight; set options_weight;
by secid date ;  lagged_strike_price=lag(strike_price);
if first.secid | first.date then lagged_strike_price=.; run;
proc sort data=options_weight; by secid date descending strike_price descending cp_flag;run;
data options_weight; set options_weight; by secid date; 
lead_strike_price=lag(strike_price); if first.secid | first.date  then lead_strike_price=.; run;
proc sort data=options_weight; by secid date strike_price descending cp_flag; run;
data options_weight; set options_weight;  by secid date ;
delta_K=(lead_strike_price-lagged_strike_price)/2;
if first.secid | first.date then delta_K=lead_strike_price-strike_price;
if last.secid | last.date then delta_K=strike_price-lagged_strike_price; run;
data options_weight;  set options_weight;
Weight_eachoption=2*delta_K/(strike_price**2);
weight_times_price=Weight_eachoption*mid_quote; run;
data options_weight_at_K0_K1; set options_weight; if strike_price=K0 | strike_price=K1; run;
proc sort data=options_weight; by secid date strike_price; run;

proc means data=options_weight NOPRINT nway;
class secid date; var weight_times_price; output out=sigma2_each_exdate  sum=sigma2;run;
proc sql;
  create table sigma2_each_exdate as
    select a.*,b.Forward, b.K0, b.days_expire
	from sigma2_each_exdate a left join options_weight b
	  on a.secid=b.secid and a.date=b.date;  quit;
proc sort data=sigma2_each_exdate nodupkey; by secid date; run;
proc sql;
  create table VIX_Prc_Half as
    select a.*,b.linear_rate
	from sigma2_each_exdate a left join ZeroCouponYieldCurve b
	  on a.date=b.date and b.days=a.days_expire;quit;
proc sort data=VIX_Prc_Half; by secid date; run;

proc sort data=stock_prc; by cusip date; run;
proc sort data=options_weight; by cusip exdate; run;
proc sql;
  create table options_weight as
    select a.*,b.prc as stock_prc_end
	from options_weight a left join stock_prc b
	  on a.cusip=b.cusip and a.exdate_trade=b.date;quit;
data options_weight; set options_weight;   
if stock_prc_end ne . ; 
if cp_flag='C' then option_payoff=max(stock_prc_end-strike_price,0);
if cp_flag='P' then option_payoff=max(strike_price-stock_prc_end,0);
Option_TerminalPayoff=Weight_eachoption*option_payoff; run;
proc sort data=options_weight; by secid date strike_price; run;
proc means data=options_weight  NOPRINT nway;
class secid date;  var Option_TerminalPayoff;
output out=actual_VIXPort_payoff sum=Option_TerminalPayoff; run;
proc sql;
  create table VIX_Prc_Half as
    select a.*,b.Option_TerminalPayoff 
	from VIX_Prc_Half a left join actual_VIXPort_payoff b
	on a.secid=b.secid and a.date=b.date;  quit;
proc sort data=options_weight nodupkey out=identifier; by secid date; run;
proc sql;
  create table VIX_Prc_Half as
    select a.*,b.cusip, b.exdate_trade
	from VIX_Prc_Half a left join identifier b
	  on a.secid=b.secid and a.date=b.date;quit;
proc sort data=VIX_Prc_Half; by cusip date; run;
proc sql;
  create table VIX_Prc_Half as
    select a.*, b.prc as St_start
	from VIX_Prc_Half a left join stock_prc b
	on a.cusip=b.cusip and a.date=b.date;   quit;
proc sql;
  create table VIX_Prc_Half as
    select a.*, b.prc as St_end
	from VIX_Prc_Half a left join stock_prc b
	on a.cusip=b.cusip and a.exdate_trade=b.date;   quit;
proc sql;
  create table VIX_Prc_Half as
    select a.*, b.K1
	from VIX_Prc_Half a left join options_findK1 b
	on a.secid=b.secid and a.date=b.date ;  quit;
data delta_K0; set options_weight_at_K0_K1; if strike_price=K0;  run;
data delta_K1; set options_weight_at_K0_K1; if strike_price=K1;  run;
proc sql;
  create table VIX_Prc_Half as
    select a.*, b.delta_K as delta_K0
	from VIX_Prc_Half a left join delta_K0 b
	on a.secid=b.secid and a.date=b.date ;  quit;
proc sql;
  create table VIX_Prc_Half as
    select a.*, b.delta_K as delta_K1
	from VIX_Prc_Half a left join delta_K1 b
	on a.secid=b.secid and a.date=b.date ;  quit;
data VIX_Prc_Half; set VIX_Prc_Half; 
Rf=exp(linear_rate/100*days_expire/365);
VIX_Prc = sigma2 + (delta_K0-forward+K0)/K0**2 * St_start - (delta_K0-forward+K0)/K0/Rf;run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.VIX_Prc as VIX_Prc_Half_Strike
	from VIX_MonthlyPrc a left join VIX_Prc_Half b
	on a.secid=b.secid and a.date=b.date ;  quit;

/*The code below generates the section "CBOE formula" in Table 1.*/
data Table1; set VIX_MonthlyPrc; 
error=(VIX_Prc_Half_Strike-VIX_Prc)/VIX_Prc; absolute_error=abs(error); run;

proc means data=Table1 n mean std P10 median P90; var absolute_error error;  run;
proc means data=Table1 n mean std P10 median P90; where num_strikes=7; var absolute_error error;  run;
proc means data=Table1 n mean std P10 median P90; where num_strikes=11; var absolute_error error;  run;
proc means data=Table1 n mean std P10 median P90; where num_strikes=15; var absolute_error error;  run;



***********************************************************
***Construct Simpson's return in sorting sample **********
***********************************************************;
/*This section constructs Simpson's return in SORTING sample. The code is the same as before except that we keep options with 0 open interests or bid prices.*/
data options;  set here.options;
if delta ne .;
if best_bid>best_offer then delete; 
strike_price=strike_price/1000; 
Mid_quote=(best_offer+best_bid)/2;
days_expire=exdate_trade-date;  
run;
proc sort data=options nodupkey; by secid date exdate strike_price cp_flag; run;

proc sort data=options nodupkey out=filter; by secid date; run;
data dividend; set stock_prc; where divamt>0; run;
proc sql;
  create table firm_divd as
    select a.*, b.divamt
	from filter a left join dividend b
	  on a.cusip=b.cusip and a.date<b.date<=a.exdate_trade;quit;
proc sort data=firm_divd; by secid date;run;
proc means data=firm_divd NOPRINT nway;
class secid date; var divamt; output out=firm_month_divd  sum=divamt;run;
proc sql;
  create table filter as
    select a.*, b.divamt 
	from filter a left join firm_month_divd b
	  on a.secid=b.secid and a.date=b.date;quit;
data filter; set filter; if divamt=.; run;
proc sort data=filter; by secid date; run;
data options; merge filter (in=a) options;  by secid date;  if a;  run;

proc sort data=options nodupkey out=filter; by secid date; run;
data stock_split; set crsp.dsedist; if FACSHR ne 0; split_flag=1; run;
proc sql;
  create table filter as
    select a.*,b.split_flag
	from filter a left join stock_split b
	  on a.cusip=b.cusip and a.date<b.exdt<=a.exdate_trade;quit;
proc sort data=filter nodupkey; by secid date;  run;
data filter; set filter; if split_flag ne 1; run;
proc sort data=options;  by secid date;  run;
data options; merge filter (in=a) options; by secid date; if a;  run;

proc sql;
  create table options as
    select a.*, b.prc as St_start
	from options a left join stock_prc b
	on a.cusip=b.cusip and a.date=b.date; quit;
proc sort data=options nodupkey; by secid date strike_price descending cp_flag; run;
data options; set options; if 5=<st_start; run;

proc sql;
  create table options as
    select a.*, b.shrcd
	from options a left join stock_prc b
	  on a.cusip=b.cusip and a.date=b.date;  quit;
data options; set options; if shrcd=10 | shrcd=11;; run;

data options_findForward; set options; run;
proc sort data=options_findForward nodupkey; by secid date; run;
proc sql;
  create table options_findForward as
    select a.*,b.linear_rate
	from options_findForward a left join ZeroCouponYieldCurve b
	  on a.date=b.date and a.exdate_trade=b.date+b.days;  quit;
proc sort data=options_findForward; by secid date; run;
proc sql;
  create table options_findForward as
    select a.*,b.prc as stock_prc_start
	from options_findForward a left join stock_prc b
	  on a.cusip=b.cusip and a.date=b.date;  quit;
proc sort data=options_findForward nodupkey; by cusip date; run;
data options_findForward;  set options_findForward;
Forward=stock_prc_start*exp(linear_rate/100*days_expire/365); run;
proc sql;
  create table options as
    select a.*,b.Forward,  b.linear_rate
	from options a left join options_findForward b
	  on a.secid=b.secid and a.date=b.date; quit;
data options;   set options;
if cp_flag="P" and strike_price>forward then delete;
if cp_flag="C" and strike_price<=forward then delete;  run;
proc sort data=options; by secid date strike_price; run;

data options;  set options; 
if cp_flag='P' and strike_price<best_bid then delete;
if cp_flag='P' and best_offer<max(0,strike_price-st_start) then delete;
if cp_flag='C' and st_start<best_bid then delete;
if cp_flag='C' and best_offer<max(0,st_start-strike_price) then delete; run;
data options;retain secid date exdate exdate_trade days_expire cp_flag strike_price forward mid_quote;set options; run;

data options_findK0; set options; distance_toForward=Forward-strike_price; if distance_toForward<0 then delete; run;
proc sort data=options_findK0; by secid date distance_toForward; run;
data options_findK0; set options_findK0; by secid date; if first.secid | first.date; run;
data options_findK0; set options_findK0; rename strike_price=K0; run;
proc sql;
  create table options as
    select a.*, b.K0
	from options a left join options_findK0 b
	  on a.secid=b.secid and a.date=b.date; quit;
data options; set options; if K0 ne .; run;

data options_findK1; set options; distance_toForward=strike_price-Forward; if distance_toForward<0 then delete; run;
proc sort data=options_findK1; by secid date distance_toForward; run;
data options_findK1; set options_findK1; by secid date; if first.secid | first.date; run;
data options_findK1; set options_findK1; rename strike_price=K1; run;
proc sql;
  create table options as
    select a.*, b.K1 
	from options a left join options_findK1 b
	  on a.secid=b.secid and a.date=b.date;quit;
data options; set options;  if K1 ne .; run;

data options_at_K0_K1; set options; if strike_price=K0 | strike_price=K1; run;

data call_used; set options; if cp_flag='C'; run;
proc sort data=call_used; by secid date strike_price; run;
data put_used; set options; if cp_flag='P'; run;
proc sort data=put_used; by secid date descending strike_price;run;
proc means data=call_used NOPRINT nway;
class secid date;   var strike_price;
output out=num_call_eachobs n=num_call; run;
proc means data=put_used NOPRINT nway;
class secid date;  var strike_price;
output out=num_put_eachobs n=num_put; run;
proc sql;
  create table num_put_eachobs as
    select a.*,b.num_call
	from num_put_eachobs a left join num_call_eachobs b
	on a.secid=b.secid and a.date=b.date;  quit;
data num_put_eachobs;  set num_put_eachobs; if num_call ne .;
num_min=min(num_put,num_call); num_sum=num_put+num_call ; run;
proc sort data=options; by secid date strike_price; run;

proc means data=options NOPRINT nway;
class secid date; var strike_price; output out=strike_interval min=strike_min max=strike_max; run;
proc means data=options NOPRINT nway;
class secid date; var impl_volatility; output out=IV_avg mean=IV_avg; run;
proc sql;
  create table strike_interval as
    select a.*,b.IV_avg
	from strike_interval a left join IV_avg b
	on a.secid=b.secid and a.date=b.date; quit;

data options_weight; set options; run;
proc sort data=options_weight; by secid date strike_price; run;
data options_weight; set options_weight;
by secid date; lagged_strike_price=lag(strike_price);if first.secid | first.date then lagged_strike_price=.; run;
proc sort data=options_weight; by secid date descending strike_price descending cp_flag;run;
data options_weight; set options_weight;
by secid date; lead_strike_price=lag(strike_price);
if first.secid | first.date  then lead_strike_price=.; run;
proc sort data=options_weight; by secid date strike_price descending cp_flag; run;
data options_weight; set options_weight;  by secid date ;
delta_K=(lead_strike_price-lagged_strike_price)/2;
if first.secid | first.date then delta_K=lead_strike_price-strike_price;
if last.secid | last.date then delta_K=strike_price-lagged_strike_price; run;

data options_weight;  set options_weight;
Weight_eachoption=2*delta_K/(strike_price**2);
if strike_price=K0 then Weight_eachoption = Weight_eachoption+(K1-K0-delta_K)/3/(K0**2);
if strike_price=K1 then Weight_eachoption = Weight_eachoption+(K1-K0-delta_K)/3/(K1**2);

weight_times_price=Weight_eachoption*mid_quote;
weight_times_price_bid=Weight_eachoption*best_bid;
weight_times_price_ask=Weight_eachoption*best_offer;
weight_delta=Weight_eachoption*delta; run;

data options_weight_at_K0_K1; set options_weight; if strike_price=K0 | strike_price=K1; run;

proc sql;
  create table strike_interval as
    select a.*,b.delta_K as delta_min
	from strike_interval a left join options_weight b
	on a.secid=b.secid and a.date=b.date and a.strike_min=b.strike_price; quit;
proc sql;
  create table strike_interval as
    select a.*,b.delta_K as delta_max
	from strike_interval a left join options_weight b
	on a.secid=b.secid and a.date=b.date and a.strike_max=b.strike_price; quit;

proc sort data=options_weight; by secid date strike_price; run;
proc means data=options_weight NOPRINT nway;
class secid date;  
var weight_times_price weight_times_price_bid weight_times_price_ask weight_delta;
output out=sigma2_each_exdate  sum=sigma2 sigma2_bid sigma2_ask Initial_delta; run;
proc sql;
  create table sigma2_each_exdate as
    select a.*,b.Forward, b.K0, b.days_expire
	from sigma2_each_exdate a left join options_weight b
	  on a.secid=b.secid and a.date=b.date;  quit;
proc sort data=sigma2_each_exdate nodupkey; by secid date; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*,b.linear_rate
	from sigma2_each_exdate a left join ZeroCouponYieldCurve b
	  on a.date=b.date and b.days=a.days_expire;quit;
proc sort data=VIX_MonthlyPrc; by secid date; run;

proc sort data=options_weight; by cusip exdate; run;
proc sql;
  create table options_weight as
    select a.*,b.prc as stock_prc_end
	from options_weight a left join stock_prc b
	  on a.cusip=b.cusip and a.exdate_trade=b.date;quit;
data options_weight; set options_weight;   
if stock_prc_end ne . ; 
if cp_flag='C' then option_payoff=max(stock_prc_end-strike_price,0);
if cp_flag='P' then option_payoff=max(strike_price-stock_prc_end,0);
Option_TerminalPayoff=Weight_eachoption*option_payoff; run;
proc sort data=options_weight; by secid date strike_price; run;
proc means data=options_weight  NOPRINT nway;
class secid date; var Option_TerminalPayoff;
output out=actual_VIXPort_payoff sum=Option_TerminalPayoff; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*,b.Option_TerminalPayoff 
	from VIX_MonthlyPrc a left join actual_VIXPort_payoff b
	on a.secid=b.secid and a.date=b.date;  quit;

proc sort data=options_weight nodupkey out=identifier; by secid date; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*,b.cusip, b.exdate_trade
	from VIX_MonthlyPrc a left join identifier b
	  on a.secid=b.secid and a.date=b.date;quit;
proc sort data=VIX_MonthlyPrc; by cusip date; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.prc as St_start, b.prc*b.shrout*1000/1000000000 as mkt_cap, b.permno
	from VIX_MonthlyPrc a left join stock_prc b
	on a.cusip=b.cusip and a.date=b.date;   quit;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.prc as St_end
	from VIX_MonthlyPrc a left join stock_prc b
	on a.cusip=b.cusip and a.exdate_trade=b.date;   quit;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.K1
	from VIX_MonthlyPrc a left join options_findK1 b
	on a.secid=b.secid and a.date=b.date ;  quit;
data delta_K0; set options_weight_at_K0_K1; if strike_price=K0; run;
data delta_K1; set options_weight_at_K0_K1; if strike_price=K1;  run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.delta_K as delta_K0
	from VIX_MonthlyPrc a left join delta_K0 b
	on a.secid=b.secid and a.date=b.date ;  quit;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.delta_K as delta_K1
	from VIX_MonthlyPrc a left join delta_K1 b
	on a.secid=b.secid and a.date=b.date ;  quit;

data VIX_MonthlyPrc; set VIX_MonthlyPrc; 
Rf=exp(linear_rate/100*days_expire/365);

Static_VIX_Payoff = Option_TerminalPayoff + ( (K1-K0)/3 * (1/K0**2 - 1/K1**2) + (2/Forward - 1/K0 - 1/K1) ) * St_end + (K1-K0)/3 * (1/K1 - 1/K0) + ( log(forward/K0) + log(forward/K1) );
VIX_Prc =sigma2 + ( (K1-K0)/3 * (1/K0**2 - 1/K1**2) + (2/Forward - 1/K0 - 1/K1) ) * St_start + ( (K1-K0)/3 * (1/K1 - 1/K0) + ( log(forward/K0) + log(forward/K1) ) ) / Rf;
Static_VIX_Return = Static_VIX_Payoff/VIX_Prc-1;  

VIX_Prc_bid = sigma2_bid + ( (K1-K0)/3 * (1/K0**2 - 1/K1**2) + (2/Forward - 1/K0 - 1/K1) ) * St_start + ( (K1-K0)/3 * (1/K1 - 1/K0) + ( log(forward/K0) + log(forward/K1) ) ) / Rf;
VIX_Prc_ask = sigma2_ask + ( (K1-K0)/3 * (1/K0**2 - 1/K1**2) + (2/Forward - 1/K0 - 1/K1) ) * St_start + ( (K1-K0)/3 * (1/K1 - 1/K0) + ( log(forward/K0) + log(forward/K1) ) ) / Rf;
VIX_BA_percent = (VIX_Prc_ask-VIX_Prc_bid)/VIX_Prc;  
if VIX_Prc_bid>0;  run;

proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.strike_min, b.strike_max, b.delta_min, b.delta_max, b.IV_avg
	from VIX_MonthlyPrc a left join strike_interval b
	  on a.secid=b.secid and a.date=b.date; quit;
data VIX_MonthlyPrc; set VIX_MonthlyPrc; 
if forward<strike_min-delta_min/2 then forward_start_Corridor=strike_min-delta_min/2;
else if strike_min-delta_min/2<=forward<=strike_max+delta_max/2 then forward_start_Corridor=forward;
else forward_start_Corridor=strike_max+delta_max/2;

if St_end<strike_min-delta_min/2 then forward_end_Corridor=strike_min-delta_min/2;
else if strike_min-delta_min/2<=St_end<=strike_max+delta_max/2 then forward_end_Corridor=St_end;
else forward_end_Corridor=strike_max+delta_max/2;
run;
proc sort data=options nodupkey out=dummy; by secid date; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.exdate
	from VIX_MonthlyPrc a left join dummy b
	on a.secid=b.secid and a.date=b.date;   quit;
proc sql;
  create table VIX_dynamicHedge as
    select a.*,b.date as date_daily, b.ret as stock_ret, b.prc as St_daily_Corridor
	from VIX_MonthlyPrc a left join stock_prc b
	  on a.cusip=b.cusip and a.date<=b.date<=a.exdate;quit;
data VIX_dynamicHedge; set VIX_dynamicHedge; Rf_daily=exp(linear_rate/100/365);
Forward_daily=St_daily_Corridor*exp(linear_rate/100*(exdate_trade-date_daily)/365);  run;

data VIX_dynamicHedge; set VIX_dynamicHedge;
if Forward_daily<strike_min-delta_min/2 then Forward_daily_Corridor=strike_min-delta_min/2;
else if strike_min-delta_min/2<=Forward_daily<=strike_max+delta_max/2 then Forward_daily_Corridor=Forward_daily;
else Forward_daily_Corridor=strike_max+delta_max/2;   run;
proc sort data=VIX_dynamicHedge; by secid date date_daily; run;

data VIX_dynamicHedge; set VIX_dynamicHedge; by secid date;
Delta_Hedge_Reinvt=2/(Rf_daily**(exdate_trade-lag(date_daily)))*(1+stock_ret - Rf_daily**(date_daily-lag(date_daily)))*(Rf_daily**(exdate_trade-date_daily));
Delta_Hedge_Corridor = 2/lag(Forward_daily_Corridor)*lag(St_daily_Corridor) * (1+stock_ret- Rf_daily**(date_daily-lag(date_daily))) * Rf_daily**(exdate_trade-date_daily);
Delta_Hedge_Corridor_Theory =2*(Forward_daily/Forward_daily_Corridor)*(Forward_daily_Corridor/lag(Forward_daily_Corridor)-1);
run;

data VIX_dynamicHedge; set VIX_dynamicHedge; if date_daily=date then delete;  run;
proc sort data=VIX_dynamicHedge;by secid date;run;
proc means data=VIX_dynamicHedge NOPRINT nway;
class secid date; var Delta_Hedge_Reinvt Delta_Hedge_Corridor Delta_Hedge_Corridor_Theory;
output out=Delta_Hedge_payoff  sum=Delta_Hedge_payoff Delta_Hedge_payoff_Corridor Delta_Hedge_Corridor_Theory; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*,b.Delta_Hedge_payoff, b.Delta_Hedge_payoff_Corridor, b.Delta_Hedge_Corridor_Theory
	from VIX_MonthlyPrc a left join Delta_Hedge_payoff b
	  on a.secid=b.secid and a.date=b.date; quit;
data VIX_dynamicHedge; set VIX_dynamicHedge; stock_ret_square=stock_ret**2; run;
proc sort data=VIX_dynamicHedge; by secid date; run;
proc means data=VIX_dynamicHedge NOPRINT nway;
class secid date;   var stock_ret_square;
output out=Monthly_RV sum=Monthly_RV; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*,b.Monthly_RV
	from VIX_MonthlyPrc a left join Monthly_RV b
	  on a.secid=b.secid and a.date=b.date; quit;

data VIX_MonthlyPrc;  set VIX_MonthlyPrc;
Dynamic_VIX_Payoff=Static_VIX_Payoff-2*(St_end/St_start/Rf-1)+Delta_Hedge_payoff;
Dynamic_VIX_Return=Dynamic_VIX_Payoff/VIX_Prc-1; 
VSR=Monthly_RV/VIX_Prc-1; 

Dynamic_VIX_Payoff_Corridor = Static_VIX_Payoff - 2*(St_end/St_start/Rf-1) + Delta_Hedge_payoff_Corridor;
Dynamic_VIX_Return_Corridor = Dynamic_VIX_Payoff_Corridor/VIX_Prc - 1; 

RV_Corridor = -2*log(forward_end_Corridor/forward_start_Corridor) + Delta_Hedge_Corridor_Theory;
VSR_Corridor = RV_Corridor/VIX_Prc-1; run;

proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.num_sum as num_strikes, b.num_put, b.num_call
	from VIX_MonthlyPrc a left join num_put_eachobs b
	  on a.secid=b.secid and a.date=b.date; quit;
data VIX_MonthlyPrc; set VIX_MonthlyPrc; if num_strikes>2; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.shrcd
	from VIX_MonthlyPrc a left join stock_prc b
	  on a.cusip=b.cusip and a.date=b.date;  quit;

/*Output data to be used in other tables later.*/
data here.simpson_return_0_oi_bid; set VIX_MonthlyPrc; Rf=Rf-1;
keep secid cusip permno shrcd date exdate exdate_trade VIX_Prc Monthly_RV Dynamic_VIX_Return VSR Dynamic_VIX_Return_Corridor VSR_Corridor Rf VIX_BA_percent mkt_cap;  run;





