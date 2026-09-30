

*--------------------------------------------------------------------;

%let root=D:\vixseas;

libname here "&root\Data Raw";

*--------------------------------------------------------------------;

***********************************************************
***************** Compute straddle return *****************
***********************************************************;
/*The data 'options' contain only individual stock options on the 3rd Friday whose maturities are the 3rd Friday next month.*/
data options;set here.options;
if open_interest>0; 
if best_bid=0 then delete;
if delta ne .; 
if best_bid>best_offer then delete;
strike_price=strike_price/1000;
maturity=exdate_trade-date;  
Mid_point=(best_bid+best_offer)/2; run;
proc sort data=options nodupkey;by secid date exdate strike_price cp_flag;run;

data ZeroCouponYieldCurve;  set here.ZeroCouponYieldCurve; run;
proc expand data=ZeroCouponYieldCurve out=ZeroCouponYieldCurve to=day;
convert rate=linear_rate / method=spline(natural);  id days; by date; run;
data ZeroCouponYieldCurve; set ZeroCouponYieldCurve; format days best12.; run;
proc sort data=ZeroCouponYieldCurve; by date days; run;

data stock_prc;  set here.CRSP_stock_daily; keep permno cusip date prc ret divamt shrcd shrout; run;
data stock_prc; set stock_prc; prc=abs(prc); if ret=.B | ret=.C then delete; run;
proc sort data=stock_prc nodupkey; by cusip date;run;

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
proc sort data=options; by secid date; run;
data options; merge filter (in=a) options;  by secid date;  if a;  run;

/* Delete firm-month with stock splits. */
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


****************************************************************
**********Pick ATM options with both call and put***************
****************************************************************;
data options_findForward; set options; run;
proc sort data=options_findForward nodupkey; by secid date; run;
proc sql;
  create table options_findForward as
    select a.*,b.linear_rate
	from options_findForward a left join ZeroCouponYieldCurve b
	  on a.date=b.date and a.exdate_trade=b.date+b.days;  quit;
proc sort data=options_findForward; by secid date; run;
data options_findForward; set options_findForward;Forward=St_start*exp(linear_rate/100*maturity/365); run;
proc sql;
  create table options as
    select a.*,b.Forward,  b.linear_rate
	from options a left join options_findForward b
	  on a.secid=b.secid and a.date=b.date; quit;
data options; set options; if forward ne .; run;
proc sort data=options; by secid date strike_price; run;
proc sql;
  create table options_stock_PRC as
    select a.*,b.prc as Stockprc_end
	from options a left join stock_prc b
	  on a.cusip=b.cusip and a.exdate_trade=b.date; quit;
proc sort data=options_stock_PRC nodupkey;by secid date strike_price cp_flag;run;
data options_ATM;set options_stock_PRC; if St_start=. | Stockprc_end=. then delete; DistanceToIndex=abs(Forward-strike_price);run;

/*pick strikes with both call and put */
data options_call; set options_ATM; if cp_flag="C"; run;
data options_call; set options_call; id_Call=_N_; run;
proc sort data=options_call; by secid date exdate strike_price;run;
data options_put; set options_ATM; if cp_flag="P"; run;
proc sort data=options_put;by secid date exdate strike_price;run;
proc sql;
  create table put_call_match as
    select a.*,b.Mid_point as Mid_point_put
	from options_call a left join options_put b
	on a.secid=b.secid and a.date=b.date and a.strike_price=b.strike_price;  quit;
proc sort data=put_call_match nodupkey;by secid date exdate strike_price id_Call;run;
data put_call_match;set put_call_match; if Mid_point_put ne .;run;
proc means data=put_call_match noprint;
class secid date; var DistanceToIndex; output out=DistanceToIndex min=DistanceToIndex_Min; run;
data DistanceToIndex;set DistanceToIndex; if secid=. then delete;run;
proc sql;
  create table options_ATM as
    select a.*,b.DistanceToIndex_Min
	from options_ATM a left join DistanceToIndex b
	  on a.secid=b.secid and a.date=b.date; quit;
data options_ATM; set options_ATM; if DistanceToIndex ne DistanceToIndex_Min then delete; run;

data Put_ATM;set options_ATM; if cp_flag='P';rename Mid_point=Mid_point_put; run;
proc sort data=Put_ATM;by secid date;run;
data Call_ATM;set options_ATM; if cp_flag='C';rename Mid_point=Mid_point_call; call_bid=best_bid; call_ask=best_offer;run;
proc sort data=Call_ATM;by secid date;run;
proc sql;
  create table straddle as
  select a.*, b.best_bid as put_bid, b.best_offer as put_ask, b.Mid_point_put, b.optionid as optionid_put, b.delta as delta_put ,b.impl_volatility as impl_volatility_put
  from Call_ATM a left join Put_ATM b
  on a.secid=b.secid and a.date=b.date and a.strike_price=b.strike_price; quit;
proc sort data=straddle nodupkey;by secid date cp_flag;run;


*************************************************************
**********************Straddle Return ***********************
*************************************************************;
/*The data 'options_daily' is extracted from OptionMetrics. It contains the daily information of those individual stock options in the dataset 'Options' from 3rd Friday to the 3rd Friday next month.*/
data OM; set here.options_daily; keep optionid date secid delta impl_volatility; run;
proc sort data=OM nodupkey; by optionid date; run;

data options; set options_ATM; Rf_daily=log(1+linear_rate/100/365); run;
proc sql;
  create table options as
    select a.*,b.date as date_daily, b.prc as St_daily
	from options a left join stock_prc b
	  on a.cusip=b.cusip and a.date<=b.date<=a.exdate_trade;quit;
proc sort data=options nodupkey; by secid date date_daily strike_price cp_flag;  run;
proc sort data=options nodupkey out=daily_information;by secid date descending date_daily;run;
data daily_information; set daily_information; by secid date; 
St_dailychange=lag(St_daily)-St_daily; days_change=lag(date_daily)-date_daily;
if first.date then St_dailychange=.;  if first.date then days_change=.; run;
data options; set options; if date_daily=exdate_trade then delete; run;

data options; set options; drop delta; run;
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
proc means data=daily_hedge noprint; 
class secid date date_daily; var delta; 
output out=straddle_delta_daily sum=option_delta_daily; run;
data straddle_delta_daily; set straddle_delta_daily; if secid ne . and date ne . and date_daily ne .; run;
proc sql;
  create table straddle_delta_daily as
    select a.*, b.cusip, b.St_daily, b.St_daily+b.St_dailychange as St_NextDay, b.days_change, b.Rf_daily
	from straddle_delta_daily a left join daily_information b
	  on a.secid=b.secid and a.date=b.date and a.date_daily=b.date_daily;quit;
proc sql;
  create table straddle_delta_daily as
    select a.*, b.exdate_trade
	from straddle_delta_daily a left join straddle b
	  on a.secid=b.secid and a.date=b.date;quit;

data straddle_delta_daily; set straddle_delta_daily; next_trade_day = date_daily+days_change; run;
proc sql;
  create table straddle_delta_daily as
    select a.*, b.ret as stock_ret_next_day
	from straddle_delta_daily a left join stock_prc b
	  on a.cusip=b.cusip and a.next_trade_day=b.date;quit;
data straddle_delta_daily; set straddle_delta_daily;  
BS_Payoff_daily= -option_delta_daily*( St_NextDay - St_daily*exp(Rf_daily*days_change) )*exp(Rf_daily*(exdate_trade-next_trade_day)); run;
proc means data=straddle_delta_daily noprint; 
class secid date; var BS_Payoff_daily; output out=Hedge_Payoff  sum=BS_Hedge_Payoff;  run;
proc sql;
  create table straddle as
    select a.*, b.BS_Hedge_Payoff
	from straddle a left join  Hedge_Payoff b
	  on a.secid=b.secid and a.date=b.date;quit;

data straddle; set straddle;  
straddle_ret=abs(Stockprc_end-strike_price)/(Mid_point_call+Mid_point_put)-1; /*Unhedged straddle return*/
straddle_dynamic_return= (abs(Stockprc_end-strike_price)+BS_Hedge_Payoff)/(Mid_point_call+Mid_point_put)-1; /*"Straddle return with Black-Scholes hedge" in Table 3*/
run;


/* link OptionMetrics with CRSP permno. "Link_OptionMetrics_CRSP" is downloaded from WRDS Linking Queries. */
data Link_OM_CRSP; set here.Link_OptionMetrics_CRSP; run;
proc sort data=Link_OM_CRSP nodupkey; by secid permno sdate edate; run;
proc sql;
  create table straddle as
    select a.*, b.permno
	from straddle a left join Link_OM_CRSP b
	  on a.secid=b.secid and b.sdate<=a.date<=b.edate;quit;

data here.straddle_return; set straddle; keep secid permno date exdate exdate_trade straddle_ret straddle_dynamic_return; run;


***********************************************************
****************** Generate Table 3************************
***********************************************************;
data sum_stat; set here.simpson_return; run;
proc sql;
  create table sum_stat as
    select a.*, b.straddle_dynamic_return
	from sum_stat a left join straddle b
	  on a.secid=b.secid and a.date=b.date;  quit;

proc sort data=sum_stat; by date; run;
proc corr data=sum_stat noprint out=corr_cs; by date; 
var VSR BS_VIX_Return Dynamic_VIX_Return VSR_Corridor Dynamic_VIX_Return_Corridor straddle_dynamic_return; run;

/* Row 1, 2, and 5 in Table 3. */
proc means data=corr_cs n mean std P10 median P90; where _type_='CORR' and _name_='VSR';
var BS_VIX_Return Dynamic_VIX_Return straddle_dynamic_return; run;

/* Row 3, 4, and 6 in Table 3. */
proc means data=corr_cs n mean std P10 median P90; where _type_='CORR' and _name_='VSR_Corridor';
var BS_VIX_Return Dynamic_VIX_Return_Corridor straddle_dynamic_return; run;


