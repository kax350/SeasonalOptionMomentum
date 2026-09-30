
*--------------------------------------------------------------------;

%let root=D:\vixseas;

libname here "&root\Data Raw";

*include all sas macros in the folder;
%include "&root\Code\SAS functions\*.sas";

*--------------------------------------------------------------------;


%macro seas(minlag, maxlag, periods, rr);


proc delete data= work._all_; run;
dm 'odsresults; clear';
 
%let row1= %sysfunc(sum(7, (2* &rr.)));
%let row2= %sysfunc(sum(8, (2* &rr.)));



proc sql;
	create table data1
	as select a.secid, a.exdate_trade as date_var, a.shrcd, a.dynamic_vix_return_corridor - a.rf as vix_all, b.dynamic_vix_return_corridor - b.rf as vix_posoi, a.rf as rfret, 
			 a.date as beg_date, b.atmiv_termspread, b.slope, b.iv_hv, b.idiovol, b.mkt_cap
	from here.simpson_return_0_oi_bid as a left join here.simpson_return as b
	on a.secid = b.secid and a.exdate_trade= b.exdate_trade;
quit;


data data2;
	set data1;
	mcap= mkt_cap;
run;

proc sort data= data2; by secid date_var; run;



%form_hold_period_2third (input=data2, output=mom, date=date_var, id=secid,
	form_var= vix_all, hold_var= vix_posoi, form_minlag= 2 , 
	form_maxlag=  12, hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= mom; by secid date_var; run;

%form_hold_period_seas_2third (input=data2, output=seasonality, date=date_var, id=secid,
	form_var= vix_all, hold_var= vix_posoi, form_minlag= &minlag , 
	form_maxlag= &maxlag, seasonality_period= &periods ,hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= seasonality; by secid date_var; run;


data data5;
	merge data2 mom (rename= (fvar= mom)) seasonality (rename= (fvar= seasonality)) ;
	by secid date_var;
run;




%FM_dirty (INSET=data5,OUTSET=FM1,DATEVAR=date_var,DEPVAR=vix_posoi, INDVARS= seasonality mom iv_hv idiovol mcap atmiv_termspread slope ,LAG=3);
proc transpose data= FM1 out= FM1_1; var estimate tvalue; id parameter;
run;
data FM1_2 (drop= _label_ parameter); merge FM1_1 FM1 (keep= rsq parameter where= (parameter= "seasonality")); run;
data FM1_3 (rename= (intercept_n= N_months)); merge FM1_2 _uncorr (keep= intercept_n); run;
proc sql; 	create table avg_obs as select mean(_edf_ + _p_) as avg_obs, min(_edf_ + _p_) as min_obs from _results; quit;
data FM1_4 ; merge FM1_3 avg_obs ; run;



*save on excel file: open a new sheet, rename it to "FM-Control";

filename example1 dde "excel|FM-Control!r&row1.c4:r&row2.c20";
data _null_;
	set fm1_4;
	file example1;
	put intercept seasonality mom iv_hv idiovol mcap atmiv_termspread slope rsq n_months avg_obs min_obs;
run;


%mend;


*quarterly;
%seas(1,12,3,1);
%seas(1,36,3,2);
