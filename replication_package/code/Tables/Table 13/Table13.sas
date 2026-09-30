
*--------------------------------------------------------------------;

%let root=D:\vixseas;

libname here "&root\Data Raw";

*include all sas macros in the folder;
%include "&root\Code\SAS functions\*.sas";

*--------------------------------------------------------------------;


%macro seas(minlag, maxlag, periods, rr, int_var);


proc delete data= work._all_; run;
dm 'odsresults; clear';
 
%let row1= %sysfunc(sum(7, (2* &rr.)));
%let row2= %sysfunc(sum(8, (2* &rr.)));

proc sql;
	create table data0
	as select a.secid, a.exdate_trade as date_var, a.dynamic_vix_return_corridor - a.rf as vix_all, b.dynamic_vix_return_corridor - b.rf as vix_posoi, a.rf as rfret, 
			 a.date as beg_date, 
			a.VIX_Prc*(1+a.Rf) as Monthly_IV_all , 
		   sqrt(a.&int_var.) as logMonthly_RV_cor_all, 
		   b.VIX_Prc*(1+b.Rf) as Monthly_IV_posoi ,
		   sqrt(b.&int_var.) as logMonthly_RV_cor_posoi
	from here.analyst_rv_0_oi_bid as a left join here.analyst_rv as b
	on a.secid = b.secid and a.exdate_trade= b.exdate_trade;
quit;

proc sql;
	create table data1
	as select a.*, b.shrcd, b.mkt_cap
	from data0 as a, here.simpson_return_0_oi_bid as b
	where a.secid= b.secid and  a.date_var= b.exdate_trade;
quit;


data data2;
	set data1;
	mcap= mkt_cap;
run;

proc sort data= data2 nodupkey; by secid date_var; run;


%form_hold_period_2third (input=data2, output=mom, date=date_var, id=secid,
	form_var=  logMonthly_RV_cor_all, hold_var= logMonthly_RV_cor_posoi, form_minlag= &minlag , 
	form_maxlag=  &maxlag, hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= mom; by secid date_var; run;

%form_hold_period_seas_2third (input=data2, output=seasonality, date=date_var, id=secid,
	form_var=  logMonthly_RV_cor_all, hold_var= logMonthly_RV_cor_posoi, form_minlag= &minlag , 
	form_maxlag= &maxlag, seasonality_period= &periods ,hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= seasonality; by secid date_var; run;


data data5;
	merge data2 mom (rename= (fvar= mom)) seasonality (rename= (fvar= seasonality)) ;
	by secid date_var;
run;



%FM_dirty (INSET=data5,OUTSET=FM1,DATEVAR=date_var,DEPVAR=logMonthly_RV_cor_posoi, INDVARS= seasonality mom ,LAG=3);
proc transpose data= FM1 out= FM1_1; var estimate tvalue; id parameter;
run;
data FM1_2 (drop= _label_ parameter); merge FM1_1 FM1 (keep= rsq parameter where= (parameter= "seasonality")); run;
data FM1_3 (rename= (intercept_n= N_months)); merge FM1_2 _uncorr (keep= intercept_n); run;
proc sql; 	create table avg_obs as select mean(_edf_ + _p_) as avg_obs, min(_edf_ + _p_) as min_obs from _results; quit;
data FM1_4 ; merge FM1_3 avg_obs ; run;


*save on excel file: open a new sheet, rename it to "Seasonality in RV & analyst";
filename example1 dde "excel|Seasonality in RV & analyst!r&row1.c4:r&row2.c9";
data _null_;
	set fm1_4;
	file example1;
	put intercept seasonality mom  rsq n_months avg_obs min_obs;
run;


%mend;

*3 to 12 lags;
%seas(1,12,3,1, rv_Corridor);
%seas(1,12,3,3, rv_Corridor_analyst);
%seas(1,12,3,4, rv_Corridor_noanalyst);

*3 to 36 lags;
%seas(1,36,3,8, rv_Corridor);
%seas(1,36,3,10, rv_Corridor_analyst);
%seas(1,36,3,11, rv_Corridor_noanalyst);



*******************************************************;
**** RV per day measure;

%macro seas_aday(minlag, maxlag, periods, rr, int_var);


proc delete data= work._all_; run;
dm 'odsresults; clear';
 
%let row1= %sysfunc(sum(7, (2* &rr.)));
%let row2= %sysfunc(sum(8, (2* &rr.)));

proc sql;
	create table data0
	as select a.secid, a.exdate_trade as date_var, a.dynamic_vix_return_corridor - a.rf as vix_all, b.dynamic_vix_return_corridor - b.rf as vix_posoi, a.rf as rfret, 
			 a.date as beg_date, 
			a.VIX_Prc*(1+a.Rf) as Monthly_IV_all , 
		    sqrt((a.&int_var/max(1,a.num_analyst_days))) as logMonthly_RV_cor_all, 
		   b.VIX_Prc*(1+b.Rf) as Monthly_IV_posoi ,
		   sqrt((b.&int_var/max(1,b.num_analyst_days))) as logMonthly_RV_cor_posoi
	from here.analyst_rv_0_oi_bid as a left join here.analyst_rv as b
	on a.secid = b.secid and a.exdate_trade= b.exdate_trade;
quit;

proc sql;
	create table data1
	as select a.*, b.shrcd, b.mkt_cap
	from data0 as a, here.simpson_return_0_oi_bid as b
	where a.secid= b.secid and  a.date_var= b.exdate_trade;
quit;


data data2;
	set data1;
	mcap= mkt_cap;
run;

proc sort data= data2 nodupkey; by secid date_var; run;


%form_hold_period_2third (input=data2, output=mom, date=date_var, id=secid,
	form_var=  logMonthly_RV_cor_all, hold_var= logMonthly_RV_cor_posoi, form_minlag= &minlag , 
	form_maxlag=  &maxlag, hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= mom; by secid date_var; run;

%form_hold_period_seas_2third (input=data2, output=seasonality, date=date_var, id=secid,
	form_var=  logMonthly_RV_cor_all, hold_var= logMonthly_RV_cor_posoi, form_minlag= &minlag , 
	form_maxlag= &maxlag, seasonality_period= &periods ,hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= seasonality; by secid date_var; run;


data data5;
	merge data2 mom (rename= (fvar= mom)) seasonality (rename= (fvar= seasonality)) ;
	by secid date_var;
run;



%FM_dirty (INSET=data5,OUTSET=FM1,DATEVAR=date_var,DEPVAR=logMonthly_RV_cor_posoi, INDVARS= seasonality mom ,LAG=3);
proc transpose data= FM1 out= FM1_1; var estimate tvalue; id parameter;
run;
data FM1_2 (drop= _label_ parameter); merge FM1_1 FM1 (keep= rsq parameter where= (parameter= "seasonality")); run;
data FM1_3 (rename= (intercept_n= N_months)); merge FM1_2 _uncorr (keep= intercept_n); run;
proc sql; 	create table avg_obs as select mean(_edf_ + _p_) as avg_obs, min(_edf_ + _p_) as min_obs from _results; quit;
data FM1_4 ; merge FM1_3 avg_obs ; run;



*save on excel file: open a new sheet, rename it to "Seasonality in RV & analyst";
filename example1 dde "excel|Seasonality in RV & analyst!r&row1.c4:r&row2.c9";
data _null_;
	set fm1_4;
	file example1;
	put intercept seasonality mom  rsq n_months avg_obs min_obs;
run;


%mend;


*3 to 12 lags;
%seas_aday(1,12,3,5, rv_Corridor_analyst);

*3 to 36 lags;
%seas_aday(1,36,3,12, rv_Corridor_analyst);





*******************************************************;

%macro seas_nday(minlag, maxlag, periods, rr, int_var);


proc delete data= work._all_; run;
dm 'odsresults; clear';
 
%let row1= %sysfunc(sum(7, (2* &rr.)));
%let row2= %sysfunc(sum(8, (2* &rr.)));

*counting trading days between first day and last day;
data raw_data; set here.analyst_rv_0_oi_bid; run;
proc sort data= raw_data nodupkey out= tdates1 (keep= exdate_trade date); by exdate_trade; run;
proc sql;
	create table tdates2
	as select a.exdate_trade, a.date as beg_date, b.date
	from tdates1 as a, here.ff_daily_26_23 as b
	where     a.date <= b.date <= a.exdate_trade;
quit;
proc sql;
	create table tdates3
	as select exdate_trade, n(date) as n_dates
	from tdates2
	group by exdate_trade;
quit;

proc sql;
	create table raw_data
	as select a.*, b.n_dates
	from raw_data as a, tdates3 as b
	where a.exdate_trade = b.exdate_trade;
quit;

proc sql;
	create table data0
	as select a.secid, a.exdate_trade as date_var, a.dynamic_vix_return_corridor - a.rf as vix_all, b.dynamic_vix_return_corridor - b.rf as vix_posoi, a.rf as rfret, 
			 a.date as beg_date, 
			a.VIX_Prc*(1+a.Rf) as Monthly_IV_all , 
		    sqrt((a.&int_var/max(1,a.n_dates-a.num_analyst_days))) as logMonthly_RV_cor_all, 
		   b.VIX_Prc*(1+b.Rf) as Monthly_IV_posoi ,
		   sqrt((b.&int_var/max(1,a.n_dates-b.num_analyst_days))) as logMonthly_RV_cor_posoi
	from raw_data as a left join here.analyst_rv as b
	on a.secid = b.secid and a.exdate_trade= b.exdate_trade;
quit;

proc sql;
	create table data1
	as select a.*, b.shrcd, b.mkt_cap
	from data0 as a, here.simpson_return_0_oi_bid as b
	where a.secid= b.secid and  a.date_var= b.exdate_trade;
quit;


data data2;
	set data1;
	mcap= mkt_cap;
run;

proc sort data= data2 nodupkey; by secid date_var; run;



%form_hold_period_2third (input=data2, output=mom, date=date_var, id=secid,
	form_var=  logMonthly_RV_cor_all, hold_var= logMonthly_RV_cor_posoi, form_minlag= &minlag , 
	form_maxlag=  &maxlag, hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= mom; by secid date_var; run;

%form_hold_period_seas_2third (input=data2, output=seasonality, date=date_var, id=secid,
	form_var=  logMonthly_RV_cor_all, hold_var= logMonthly_RV_cor_posoi, form_minlag= &minlag , 
	form_maxlag= &maxlag, seasonality_period= &periods ,hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= seasonality; by secid date_var; run;


data data5;
	merge data2 mom (rename= (fvar= mom)) seasonality (rename= (fvar= seasonality)) ;
	by secid date_var;
run;



%FM_dirty (INSET=data5,OUTSET=FM1,DATEVAR=date_var,DEPVAR=logMonthly_RV_cor_posoi, INDVARS= seasonality mom ,LAG=3);
proc transpose data= FM1 out= FM1_1; var estimate tvalue; id parameter;
run;
data FM1_2 (drop= _label_ parameter); merge FM1_1 FM1 (keep= rsq parameter where= (parameter= "seasonality")); run;
data FM1_3 (rename= (intercept_n= N_months)); merge FM1_2 _uncorr (keep= intercept_n); run;
proc sql; 	create table avg_obs as select mean(_edf_ + _p_) as avg_obs, min(_edf_ + _p_) as min_obs from _results; quit;
data FM1_4 ; merge FM1_3 avg_obs ; run;



*save on excel file: open a new sheet, rename it to "Seasonality in RV & analyst";
filename example1 dde "excel|Seasonality in RV & analyst!r&row1.c4:r&row2.c9";
data _null_;
	set fm1_4;
	file example1;
	put intercept seasonality mom  rsq n_months avg_obs min_obs;
run;


%mend;


*3 to 12 lags;
%seas_nday(1,12,3,6, rv_Corridor_noanalyst);


*3 to 36 lags;
%seas_nday(1,36,3,13, rv_Corridor_noanalyst);








******************************* # of analyst days;

%macro seas(minlag, maxlag, periods, rr, int_var);


proc delete data= work._all_; run;
dm 'odsresults; clear';
 
%let row1= %sysfunc(sum(7, (2* &rr.)));
%let row2= %sysfunc(sum(8, (2* &rr.)));

proc sql;
	create table data0
	as select a.secid, a.exdate_trade as date_var, a.dynamic_vix_return_corridor - a.rf as vix_all, b.dynamic_vix_return_corridor - b.rf as vix_posoi, a.rf as rfret, 
			 a.date as beg_date, 
			a.VIX_Prc*(1+a.Rf) as Monthly_IV_all , 
		   a.&int_var. as logMonthly_RV_cor_all, 
		   b.VIX_Prc*(1+b.Rf) as Monthly_IV_posoi ,
		   b.&int_var. as logMonthly_RV_cor_posoi
	from here.analyst_rv_0_oi_bid as a left join here.analyst_rv as b
	on a.secid = b.secid and a.exdate_trade= b.exdate_trade;
quit;

proc sql;
	create table data1
	as select a.*, b.shrcd, b.mkt_cap
	from data0 as a, here.simpson_return_0_oi_bid as b
	where a.secid= b.secid and  a.date_var= b.exdate_trade;
quit;

data data2;
	set data1;
	mcap= mkt_cap;
run;

proc sort data= data2 nodupkey; by secid date_var; run;


%form_hold_period_2third (input=data2, output=mom, date=date_var, id=secid,
	form_var=  logMonthly_RV_cor_all, hold_var= logMonthly_RV_cor_posoi, form_minlag= &minlag , 
	form_maxlag=  &maxlag, hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= mom; by secid date_var; run;

%form_hold_period_seas_2third (input=data2, output=seasonality, date=date_var, id=secid,
	form_var=  logMonthly_RV_cor_all, hold_var= logMonthly_RV_cor_posoi, form_minlag= &minlag , 
	form_maxlag= &maxlag, seasonality_period= &periods ,hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= seasonality; by secid date_var; run;


data data5;
	merge data2 mom (rename= (fvar= mom)) seasonality (rename= (fvar= seasonality)) ;
	by secid date_var;
run;



%FM_dirty (INSET=data5,OUTSET=FM1,DATEVAR=date_var,DEPVAR=logMonthly_RV_cor_posoi, INDVARS= seasonality mom ,LAG=3);
proc transpose data= FM1 out= FM1_1; var estimate tvalue; id parameter;
run;
data FM1_2 (drop= _label_ parameter); merge FM1_1 FM1 (keep= rsq parameter where= (parameter= "seasonality")); run;
data FM1_3 (rename= (intercept_n= N_months)); merge FM1_2 _uncorr (keep= intercept_n); run;
proc sql; 	create table avg_obs as select mean(_edf_ + _p_) as avg_obs, min(_edf_ + _p_) as min_obs from _results; quit;
data FM1_4 ; merge FM1_3 avg_obs ; run;


*save on excel file: open a new sheet, rename it to "Seasonality in RV & analyst";
filename example1 dde "excel|Seasonality in RV & analyst!r&row1.c4:r&row2.c9";
data _null_;
	set fm1_4;
	file example1;
	put intercept seasonality mom  rsq n_months avg_obs min_obs;
run;


%mend;

*3 to 12 lags;
%seas(1,12,3,2, num_analyst_days);

*3 to 36 lags;
%seas(1,36,3,9, num_analyst_days);
