
/*****************************************************
******************** IBES Data *********************
******************************************************/
/*Load IBES analyst EPS forecast data from WRDS. The data contains analysts' 1 year unadjusted forecast.*/
data EPS; set yourpath.EPS_1Year_Unadjusted; if ANNDATS ne . and value ne .; run;

/*link with CRSP permno. Link_IBES_CRSP is downloaded from WRDS link suite.*/
data Link_IBES_CRSP; set yourpath.Link_IBES_CRSP;  run;
proc sql;
  create table EPS as
    select a.*,b.permno, b.score, b.ncusip
	from EPS a left join Link_IBES_CRSP b
	  on a.TICKER=b.TICKER and b.sdate<=a.ANNDATS<=b.edate; quit;
data EPS; set EPS; if score=1 and permno ne .; run;
proc sort data=EPS nodupkey; by permno ANALYS ANNDATS ANNTIMS ;run;

/*find the trading day corresponding to each revision*/
data EPS; set EPS; mkt_close_time = "16:00:00"t; format mkt_close_time time8.; if ANNTIMS>mkt_close_time then ANNDATS=ANNDATS+1; run;

/*get trading days from daily CRSP dataset*/
data trading_date; set yourpath.CRSP_stock_daily; keep date; run;
proc sort data=trading_date nodupkey; by date;run;
proc sql;
  create table EPS as
  select a.* ,b.date as trading_date
	from EPS a left join trading_date b
	  on a.ANNDATS=b.date;  quit;
data dummy; set EPS; if trading_date=.; run;
proc sort data=dummy nodupkey; by ANNDATS;run;
proc sql;
  create table dummy as
  select a.*, b.date as trading_date2
	from dummy a left join trading_date b
	          on a.ANNDATS <= b.date
              where a.ANNDATS <= b.date
                group by a.ANNDATS
                  having abs(a.ANNDATS-b.date)=min(abs(a.ANNDATS-b.date))
                    order by a.ANNDATS;quit;
proc sql;
  create table EPS as
  select a.* ,b.trading_date2
	from EPS a left join dummy b
	  on a.ANNDATS=b.ANNDATS;  quit;
data EPS; set EPS;if trading_date=. then trading_date=trading_date2;ANNDATS=trading_date;run;

proc sort data=EPS nodupkey out=EPS_firm; by permno ANNDATS;run;
data EPS_firm; set EPS_firm; flag_analyst_eps=1; run;


****************************************************
*************** magnitude of EPS revision **********
****************************************************;
/*Same analyst may issue more than one EPS forecast one day, only keep the latest one*/
proc sort data=EPS nodupkey; by permno ANALYS ANNDATS descending ANNTIMS;run;
proc sort data=EPS nodupkey; by permno ANALYS ANNDATS;run;
data dummy; set EPS; run;

proc sql;
  create table EPS as
  select a.*, b.value as value_previous, b.ANNDATS as ANNDATS_previous
	from EPS a left join dummy b
	          on a.permno=b.permno and a.ANALYS=b.ANALYS
              where b.ANNDATS < a.ANNDATS
                group by a.permno, a.ANALYS, a.ANNDATS
                  having abs(a.ANNDATS-b.ANNDATS)=min(abs(a.ANNDATS-b.ANNDATS))
                    order by a.permno, a.ANALYS, a.ANNDATS;quit;

/*adjust for share splits*/
data dummy; set yourpath.CRSP_stock_daily; keep permno date shrout cfacshr; run;
proc sort data=dummy nodupkey; by permno date;run;
proc sql;
  create table EPS as
  select a.*, b.shrout, b.cfacshr
	from EPS a left join dummy b
	  on a.permno=b.permno and a.ANNDATS=b.date;  quit;
proc sql;
  create table EPS as
  select a.*, b.shrout as shrout_previous, b.cfacshr as cfacshr_previous
	from EPS a left join dummy b
	  on a.permno=b.permno and a.ANNDATS_previous=b.date; quit;
data EPS; set EPS; 
/*EPS forecast can be negative. Scale by absolute value.*/
EPS_revise=(value*shrout*cfacshr-value_previous*shrout_previous*cfacshr_previous)/abs(value_previous*shrout_previous*cfacshr_previous);
report_interval=ANNDATS-ANNDATS_previous; run;

/*winsorize outliers at 0.5%.*/
%macro winsor(dsetin=, dsetout=, byvar=none, vars=, type=winsor, pctl=0.5 99.5);
%if &dsetout = %then %let dsetout = &dsetin;     
%let varL=;
%let varH=;
%let xn=1;  
%do %until ( %scan(&vars,&xn)= );
    %let token = %scan(&vars,&xn);
    %let varL = &varL &token.L;
    %let varH = &varH &token.H;
    %let xn=%EVAL(&xn + 1);
%end; 
%let xn=%eval(&xn-1); 
data xtemp;
    set &dsetin;
    run; 
%if &byvar = none %then %do; 
    data xtemp;
        set xtemp;
        xbyvar = 1;
        run; 
    %let byvar = xbyvar;
%end;
proc sort data = xtemp;
    by &byvar;
    run;
proc univariate data = xtemp noprint;
    by &byvar;
    var &vars;
    output out = xtemp_pctl PCTLPTS = &pctl PCTLPRE = &vars PCTLNAME = L H;
    run;  
data &dsetout;
    merge xtemp xtemp_pctl;
    by &byvar;
    array trimvars{&xn} &vars;
    array trimvarl{&xn} &varL;
    array trimvarh{&xn} &varH;  
    do xi = 1 to dim(trimvars);  
        %if &type = winsor %then %do;
            if not missing(trimvars{xi}) then do;
              if (trimvars{xi} < trimvarl{xi}) then trimvars{xi} = trimvarl{xi};
              if (trimvars{xi} > trimvarh{xi}) then trimvars{xi} = trimvarh{xi};
            end;
        %end;  
        %else %do;
            if not missing(trimvars{xi}) then do;
              if (trimvars{xi} < trimvarl{xi}) then delete;
              if (trimvars{xi} > trimvarh{xi}) then delete;
            end;
        %end;
    end;
    drop &varL &varH xbyvar xi;
    run; 
%mend winsor;
%winsor(dsetin=EPS, dsetout=EPS, byvar=none, vars=EPS_revise, type=winsor, pctl=0.5 99.5);

proc sort data=EPS; by permno ANNDATS ANALYS;run;
proc means data=EPS NOPRINT nway;
where report_interval<=365; /*delete stale reports*/
class permno ANNDATS; var EPS_revise; output out=EPS_revise mean=EPS_revise; run;
proc sql;
  create table EPS_firm as
  select a.*, b.EPS_revise
	from EPS_firm a left join EPS_revise b
	  on a.permno=b.permno and a.ANNDATS=b.ANNDATS;  quit;

/*Retrieve earnings dates from quarterly COMPUSTAT dataset.*/
data Quarterly_compustat; set yourpath.Quarterly_compustat
(keep=gvkey datadate fyearq fqtr DATACQTR DATAFQTR SIC PRCCQ CSHOQ DLTTQ DLCQ IBQ CAPXY ATQ SEQQ TXDITCQ CEQQ PSTKQ PSTKRQ LTQ DVPQ PRSTKCY DVPSXQ indfmt datafmt popsrc consol OPTFVGRQ rdq);
where indfmt='INDL' and datafmt='STD' and popsrc='D' and consol='C'; IF 1994<fyearq; run; 
data Earning; set Quarterly_compustat; if rdq ne .; flag_earning=1; run;


***********************************************************
****** Compute VIX returns with analyst updates ***********
***********************************************************;
data options;  set yourpath.options;
if open_interest>0;  
if delta ne .;
if best_bid=0 then delete;  
if best_bid>best_offer then delete; 
strike_price=strike_price/1000; 
Mid_quote=(best_offer+best_bid)/2;
days_expire=exdate_trade-date;  run;
proc sort data=options nodupkey; by secid date exdate strike_price cp_flag; run;

data ZeroCouponYieldCurve;  set yourpath.ZeroCouponYieldCurve; run;
proc expand data=ZeroCouponYieldCurve out=ZeroCouponYieldCurve to=day;
convert rate=linear_rate / method=spline(natural);  id days; by date; run;
data ZeroCouponYieldCurve; set ZeroCouponYieldCurve; format days best12.; run;
proc sort data=ZeroCouponYieldCurve; by date days; run;

data stock_prc;  set yourpath.CRSP_stock_daily; keep permno cusip date prc ret divamt shrcd shrout; run;
data stock_prc; set stock_prc; prc=abs(prc); if ret=.B | ret=.C then delete; run;
proc sort data=stock_prc nodupkey; by cusip date;run;

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
data stock_split; set yourpath.dsedist; if FACSHR ne 0; split_flag=1; run;
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
weight_times_price_ask=Weight_eachoption*best_offer;run;

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


/****************************************************************************
*****Corridor Variance Swap Return: Analyst- vs Non-analyst based ************
*****************************************************************************/
proc sql;
  create table VIX_dynamicHedge as
    select a.*,b.date as date_daily, b.ret as stock_ret, b.prc as St_daily_Corridor
	from VIX_MonthlyPrc a left join stock_prc b
	  on a.cusip=b.cusip and a.date<=b.date<=a.exdate;quit;
proc sql;
  create table VIX_dynamicHedge as
  select a.*, b.flag_analyst_eps, a.stock_ret*b.flag_analyst_eps as ret_analyst, b.EPS_revise
	from VIX_dynamicHedge a left join EPS_firm b
	  on a.permno=b.permno and a.date_daily=b.ANNDATS;quit;

/*Split EPS revision magnitudes into low vs high in the same month.*/
proc sort data=VIX_dynamicHedge; by date permno; run;
proc means data=VIX_dynamicHedge NOPRINT nway; where EPS_revise ne .;
class date; var EPS_revise; output out=EPS_revise_median median=EPS_revise_median; run;
proc sql;
  create table VIX_dynamicHedge as
  select a.*, b.EPS_revise_median
	from VIX_dynamicHedge a left join EPS_revise_median b
	  on a.date=b.date;quit;
data VIX_dynamicHedge; set VIX_dynamicHedge; 
flag_analyst_eps_low=.; flag_analyst_eps_high=.;
if EPS_revise ne . and EPS_revise<=EPS_revise_median then flag_analyst_eps_low=1;
if EPS_revise ne . and EPS_revise>EPS_revise_median then flag_analyst_eps_high=1; run;
data VIX_dynamicHedge; set VIX_dynamicHedge; Rf_daily=exp(linear_rate/100/365);Forward_daily=St_daily_Corridor*exp(linear_rate/100*(exdate_trade-date_daily)/365); run;
data VIX_dynamicHedge; set VIX_dynamicHedge;
if Forward_daily<strike_min-delta_min/2 then Forward_daily_Corridor=strike_min-delta_min/2;
else if strike_min-delta_min/2<=Forward_daily<=strike_max+delta_max/2 then Forward_daily_Corridor=Forward_daily;
else Forward_daily_Corridor=strike_max+delta_max/2; run;
proc sort data=VIX_dynamicHedge; by secid date date_daily; run;

data VIX_dynamicHedge; set VIX_dynamicHedge; by secid date;
Daily_Corridor =2*(Forward_daily/Forward_daily_Corridor*(Forward_daily_Corridor/lag(Forward_daily_Corridor)-1)-log(Forward_daily_Corridor/lag(Forward_daily_Corridor)));
Daily_Corridor_analyst = Daily_Corridor*flag_analyst_eps;
Daily_Corridor_analyst_low = Daily_Corridor*flag_analyst_eps_low; 
Daily_Corridor_analyst_high = Daily_Corridor*flag_analyst_eps_high; run;
data VIX_dynamicHedge; set VIX_dynamicHedge; stock_ret_square_analyst=ret_analyst**2;run;
data VIX_dynamicHedge; set VIX_dynamicHedge; if date_daily=date then delete; run;
proc sort data=VIX_dynamicHedge; by secid date; run;
proc means data=VIX_dynamicHedge NOPRINT nway; where Daily_Corridor_analyst ne .;
class secid date; var stock_ret_square_analyst Daily_Corridor_analyst Daily_Corridor_analyst_low Daily_Corridor_analyst_high;
output out=RV_Analyst sum=RV_Analyst RV_Corridor_Analyst RV_Corridor_Analyst_low RV_Corridor_Analyst_high; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*,b.RV_Analyst, b.RV_Corridor_Analyst,b.RV_Corridor_Analyst_low, b.RV_Corridor_Analyst_high, b._freq_ as Num_Analyst_Days
	from VIX_MonthlyPrc a left join RV_Analyst b
	  on a.secid=b.secid and a.date=b.date; quit;

/*Create earnings dummy for each firm-month.*/
proc sql;
	create table CCM_LINK as 
	select distinct a.permno, gvkey, liid as iid, date, prc, vol,SHROUT, ret
	from 
		yourpath.msf as a, 						
		yourpath.msenames as b, 
		yourpath.ccmxpf_lnkhist  /*link permno in CRSP with gvkey in COMPUSTAT*/
		(
			where=(
				linktype in ('LU' 'LC' 'LS') 	
				and LINKPRIM in ('P' 'C')   )		
		) as c
	where a.permno=b.permno=c.lpermno		
	and b.NAMEDT<=a.date<=b.NAMEENDT			
	and linkdt<=a.date<=coalesce(linkenddt, today());	
quit;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.gvkey
	from VIX_MonthlyPrc a left join CCM_LINK b
	  on a.permno=b.permno and intck('month',b.date,a.date)=0; quit;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.rdq as earning_date, b.flag_earning
	from VIX_MonthlyPrc a left join Earning b
	  on a.gvkey=b.gvkey and a.date<b.rdq<=a.exdate_trade; quit;
proc sort data=VIX_MonthlyPrc nodupkey; by secid date; run;


data VIX_MonthlyPrc; set VIX_MonthlyPrc; 
if Num_Analyst_Days=. then Num_Analyst_Days=0; 
if RV_Corridor_Analyst=. then RV_Corridor_Analyst=0; 
RV_Corridor_Noanalyst=RV_Corridor-RV_Corridor_Analyst;
VSR_Corridor_analyst = RV_Corridor_Analyst/VIX_Prc-1; /*Analyst-based corridor variance swap return.*/
VSR_Corridor_noanalyst = RV_Corridor_noAnalyst/VIX_Prc-1; /*Non-analyst-based corridor variance swap return.*/
if RV_Corridor_Analyst_Low=. then RV_Corridor_Analyst_Low=0; 
if RV_Corridor_Analyst_High=. then RV_Corridor_Analyst_High=0; 
VSR_Corridor_analyst_Low = RV_Corridor_Analyst_Low/VIX_Prc-1; 
VSR_Corridor_analyst_High = RV_Corridor_Analyst_High/VIX_Prc-1; run;


proc sort data=VIX_MonthlyPrc nodupkey out=month_index; by date; run;
data month_index; set month_index; month_index=_n_; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.month_index
	from VIX_MonthlyPrc a left join month_index b
	  on a.date=b.date; quit;
proc sort data=VIX_MonthlyPrc; by secid date; run;
data VIX_MonthlyPrc; set VIX_MonthlyPrc; Rf=Rf-1; if flag_earning=. then flag_earning=0; run;

data output.analyst_rv; set VIX_MonthlyPrc; keep secid permno date exdate exdate_trade Dynamic_VIX_Return_Corridor Rf VIX_Prc RV_Corridor RV_Corridor_Analyst RV_Corridor_Noanalyst Num_Analyst_Days gvkey earning_date RV_Corridor_Analyst_Low RV_Corridor_Analyst_High VSR_Corridor_analyst VSR_Corridor_noanalyst VSR_Corridor_analyst_Low VSR_Corridor_analyst_High month_index flag_earning; run;


***********************************************************************************
*** Calculate VIX return including options with 0 open interest and bid **********
***********************************************************************************;
/*This section recomputes VIX return in SORTING sample. The code is the same as before except that we keep options with 0 open interests or bid prices.*/
data options;  set yourpath.options;
if delta ne .;
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
weight_times_price_ask=Weight_eachoption*best_offer;run;

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

proc sql;
  create table VIX_dynamicHedge as
    select a.*,b.date as date_daily, b.ret as stock_ret, b.prc as St_daily_Corridor
	from VIX_MonthlyPrc a left join stock_prc b
	  on a.cusip=b.cusip and a.date<=b.date<=a.exdate;quit;
proc sql;
  create table VIX_dynamicHedge as
  select a.*, b.flag_analyst_eps, a.stock_ret*b.flag_analyst_eps as ret_analyst, b.EPS_revise
	from VIX_dynamicHedge a left join EPS_firm b
	  on a.permno=b.permno and a.date_daily=b.ANNDATS;quit;

proc sort data=VIX_dynamicHedge; by date permno; run;
proc means data=VIX_dynamicHedge NOPRINT nway; where EPS_revise ne .;
class date; var EPS_revise; output out=EPS_revise_median median=EPS_revise_median; run;
proc sql;
  create table VIX_dynamicHedge as
  select a.*, b.EPS_revise_median
	from VIX_dynamicHedge a left join EPS_revise_median b
	  on a.date=b.date;quit;
data VIX_dynamicHedge; set VIX_dynamicHedge; 
flag_analyst_eps_low=.; flag_analyst_eps_high=.;
if EPS_revise ne . and EPS_revise<=EPS_revise_median then flag_analyst_eps_low=1;
if EPS_revise ne . and EPS_revise>EPS_revise_median then flag_analyst_eps_high=1; run;
data VIX_dynamicHedge; set VIX_dynamicHedge; Rf_daily=exp(linear_rate/100/365);Forward_daily=St_daily_Corridor*exp(linear_rate/100*(exdate_trade-date_daily)/365); run;
data VIX_dynamicHedge; set VIX_dynamicHedge;
if Forward_daily<strike_min-delta_min/2 then Forward_daily_Corridor=strike_min-delta_min/2;
else if strike_min-delta_min/2<=Forward_daily<=strike_max+delta_max/2 then Forward_daily_Corridor=Forward_daily;
else Forward_daily_Corridor=strike_max+delta_max/2; run;
proc sort data=VIX_dynamicHedge; by secid date date_daily; run;

data VIX_dynamicHedge; set VIX_dynamicHedge; by secid date;
Daily_Corridor =2*(Forward_daily/Forward_daily_Corridor*(Forward_daily_Corridor/lag(Forward_daily_Corridor)-1)-log(Forward_daily_Corridor/lag(Forward_daily_Corridor)));
Daily_Corridor_analyst = Daily_Corridor*flag_analyst_eps;
Daily_Corridor_analyst_low = Daily_Corridor*flag_analyst_eps_low; 
Daily_Corridor_analyst_high = Daily_Corridor*flag_analyst_eps_high; run;
data VIX_dynamicHedge; set VIX_dynamicHedge; stock_ret_square_analyst=ret_analyst**2;run;
data VIX_dynamicHedge; set VIX_dynamicHedge; if date_daily=date then delete; run;
proc sort data=VIX_dynamicHedge; by secid date; run;
proc means data=VIX_dynamicHedge NOPRINT nway; where Daily_Corridor_analyst ne .;
class secid date; var stock_ret_square_analyst Daily_Corridor_analyst Daily_Corridor_analyst_low Daily_Corridor_analyst_high;
output out=RV_Analyst sum=RV_Analyst RV_Corridor_Analyst RV_Corridor_Analyst_low RV_Corridor_Analyst_high; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*,b.RV_Analyst, b.RV_Corridor_Analyst,b.RV_Corridor_Analyst_low, b.RV_Corridor_Analyst_high, b._freq_ as Num_Analyst_Days
	from VIX_MonthlyPrc a left join RV_Analyst b
	  on a.secid=b.secid and a.date=b.date; quit;

proc sql;
	create table CCM_LINK as 
	select distinct a.permno, gvkey, liid as iid, date, prc, vol,SHROUT, ret
	from 
		yourpath.msf as a, 						
		yourpath.msenames as b, 
		yourpath.ccmxpf_lnkhist  
		(
			where=(
				linktype in ('LU' 'LC' 'LS') 	
				and LINKPRIM in ('P' 'C')   )		
		) as c
	where a.permno=b.permno=c.lpermno		
	and b.NAMEDT<=a.date<=b.NAMEENDT			
	and linkdt<=a.date<=coalesce(linkenddt, today());	
quit;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.gvkey
	from VIX_MonthlyPrc a left join CCM_LINK b
	  on a.permno=b.permno and intck('month',b.date,a.date)=0; quit;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.rdq as earning_date, b.flag_earning
	from VIX_MonthlyPrc a left join Earning b
	  on a.gvkey=b.gvkey and a.date<b.rdq<=a.exdate_trade; quit;
proc sort data=VIX_MonthlyPrc nodupkey; by secid date; run;

data VIX_MonthlyPrc; set VIX_MonthlyPrc; 
if Num_Analyst_Days=. then Num_Analyst_Days=0; 
if RV_Corridor_Analyst=. then RV_Corridor_Analyst=0; 
RV_Corridor_Noanalyst=RV_Corridor-RV_Corridor_Analyst;
VSR_Corridor_analyst = RV_Corridor_Analyst/VIX_Prc-1; /*Analyst-based corridor variance swap return.*/
VSR_Corridor_noanalyst = RV_Corridor_noAnalyst/VIX_Prc-1; /*Non-analyst-based corridor variance swap return.*/
if RV_Corridor_Analyst_Low=. then RV_Corridor_Analyst_Low=0; 
if RV_Corridor_Analyst_High=. then RV_Corridor_Analyst_High=0; 
VSR_Corridor_analyst_Low = RV_Corridor_Analyst_Low/VIX_Prc-1; 
VSR_Corridor_analyst_High = RV_Corridor_Analyst_High/VIX_Prc-1; run;

proc sort data=VIX_MonthlyPrc nodupkey out=month_index; by date; run;
data month_index; set month_index; month_index=_n_; run;
proc sql;
  create table VIX_MonthlyPrc as
    select a.*, b.month_index
	from VIX_MonthlyPrc a left join month_index b
	  on a.date=b.date; quit;
proc sort data=VIX_MonthlyPrc; by secid date; run;
data VIX_MonthlyPrc; set VIX_MonthlyPrc; Rf=Rf-1; if flag_earning=. then flag_earning=0; run;

data output.analyst_rv_0_oi_bid; set VIX_MonthlyPrc; keep secid permno date exdate exdate_trade Dynamic_VIX_Return_Corridor Rf VIX_Prc RV_Corridor RV_Corridor_Analyst RV_Corridor_Noanalyst Num_Analyst_Days gvkey earning_date RV_Corridor_Analyst_Low RV_Corridor_Analyst_High VSR_Corridor_analyst VSR_Corridor_noanalyst VSR_Corridor_analyst_Low VSR_Corridor_analyst_High month_index flag_earning; run;








