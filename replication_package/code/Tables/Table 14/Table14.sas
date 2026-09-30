
*--------------------------------------------------------------------;

%let root=D:\vixseas;

libname here "&root\Data Raw";

*include all sas macros in the folder;
%include "&root\Code\SAS functions\*.sas";

*--------------------------------------------------------------------;


%macro seas(minlag, maxlag, periods, rr);


proc delete data= work._all_; run;
dm 'odsresults; clear';
 
%let row1= %sysfunc(sum(-9, (16* &rr.)));
%let row2= %sysfunc(sum(6, (16* &rr.)));


proc sql;
	create table data0
	as select a.secid, a.exdate_trade as date_var, 
			(a.rv_corridor/a.vix_prc) -1 - a.rf as vsr_all, (a.rv_corridor_analyst/a.vix_prc) - 1 - a.rf as vsr_analyst_all, (a.rv_corridor_noanalyst/a.vix_prc) -1 - a.rf as vsr_noanalyst_all, 
			(b.rv_corridor/b.vix_prc) - 1 - b.rf as vsr_posoi, (b.rv_corridor_analyst/ b.vix_prc) -1 - b.rf as vsr_analyst_posoi, (b.rv_corridor_noanalyst/b.vix_prc) - 1 - b.rf as vsr_noanalyst_posoi,
			a.rf as rfret, a.dynamic_vix_return_corridor - a.rf as vix_all, b.dynamic_vix_return_corridor - b.rf as vix_posoi
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
proc sort data= data2; by secid date_var; run;


%form_hold_period_2third (input=data2, output=mom, date=date_var, id=secid,
	form_var= vsr_all, hold_var= vsr_posoi, form_minlag= 2 , 
	form_maxlag=  &maxlag, hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= mom; by secid date_var; run;

****analyst;
%form_hold_period_seas_2third (input=data2, output=seasonal_analyst, date=date_var, id=secid,
	form_var= vsr_analyst_all, hold_var= vsr_analyst_posoi, form_minlag= &minlag , 
	form_maxlag= &maxlag, seasonality_period= &periods ,hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= seasonal_analyst; by secid date_var; run;

%form_hold_period_seas_other_2th (input=data2, output=nonseasonal_analyst, date=date_var, id=secid,
	form_var= vsr_analyst_all, hold_var= vsr_analyst_posoi, form_minlag= &minlag , 
	form_maxlag= &maxlag, seasonality_period= &periods ,hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= nonseasonal_analyst; by secid date_var; run;


****non-analyst;
%form_hold_period_seas_2third (input=data2, output=seasonal_noanalyst, date=date_var, id=secid,
	form_var= vsr_noanalyst_all, hold_var= vsr_noanalyst_posoi, form_minlag= &minlag , 
	form_maxlag= &maxlag, seasonality_period= &periods ,hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= seasonal_noanalyst; by secid date_var; run;

%form_hold_period_seas_other_2th (input=data2, output=nonseasonal_noanalyst, date=date_var, id=secid,
	form_var= vsr_noanalyst_all, hold_var= vsr_noanalyst_posoi, form_minlag= &minlag , 
	form_maxlag= &maxlag, seasonality_period= &periods ,hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= nonseasonal_noanalyst; by secid date_var; run;



data data3;
	merge  
		data2 (keep= secid date_var vix_posoi vix_all)
		mom (rename= (fvar= mom))
		seasonal_analyst (rename= (fvar= seasonal_analyst))
		nonseasonal_analyst (rename= (fvar= nonseasonal_analyst))
		seasonal_noanalyst (rename= (fvar= seasonal_noanalyst))
		nonseasonal_noanalyst (rename= (fvar= nonseasonal_noanalyst))
	;
	by secid date_Var;
run;



*FM;
%FM (INSET=data3,OUTSET=FM1,DATEVAR=date_var,DEPVAR=vix_posoi, INDVARS=seasonal_analyst nonseasonal_analyst ,LAG=3);
proc transpose data= FM1 out= FM1_1; var estimate tvalue; id parameter;
run;
data FM1_2 (drop= _label_ parameter ); merge FM1_1 FM1 (keep= rsq parameter where= (parameter= "seasonal_analyst")); run;

%FM (INSET=data3,OUTSET=FM2,DATEVAR=date_var,DEPVAR=vix_posoi, INDVARS=seasonal_noanalyst nonseasonal_noanalyst ,LAG=3);
proc transpose data= FM2 out= FM2_1; var estimate tvalue; id parameter;
run;
data FM2_2 (drop= _label_ parameter ); merge FM2_1 FM2 (keep= rsq parameter where= (parameter= "seasonal_noanalyst")); run;

%FM (INSET=data3,OUTSET=FM3,DATEVAR=date_var,DEPVAR=vix_posoi, INDVARS=seasonal_analyst nonseasonal_analyst seasonal_noanalyst nonseasonal_noanalyst ,LAG=3);
proc transpose data= FM3 out= FM3_1; var estimate tvalue; id parameter;
run;
data FM3_2 (drop= _label_ parameter ); merge FM3_1 FM3 (keep= rsq parameter where= (parameter= "seasonal_analyst")); run;




data FM_out;
	set  FM1_2  FM2_2 FM3_2 ;
run;

*save on excel file: open a new sheet, rename it to "Analyst seasonality (FM)";
filename example1 dde "excel|Analyst seasonality (FM)!r&row1.c4:r&row2.c15";
data _null_;
	set fm_out;
	file example1;
	put intercept seasonal_analyst nonseasonal_analyst seasonal_noanalyst nonseasonal_noanalyst rsq;
run;

%mend;


*quarterly;
%seas(1,12,3,1);
%seas(1,36,3,2);

