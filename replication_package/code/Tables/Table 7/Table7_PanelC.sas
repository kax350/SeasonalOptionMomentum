
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
	create table data1
	as select a.secid, a.exdate_trade as date_var, a.shrcd, a.dynamic_vix_return_corridor - a.rf as vix_all, b.dynamic_vix_return_corridor - b.rf as vix_posoi, a.rf as rfret, a.mkt_cap
	from here.simpson_return_0_oi_bid as a left join here.simpson_return as b
	on a.secid = b.secid and a.exdate_trade= b.exdate_trade;
quit;

data data2;
	set data1;
	mcap= mkt_cap;
run;


%form_hold_period_2third (input=data2, output=mom, date=date_var, id=secid,
	form_var= vix_all, hold_var= vix_posoi, form_minlag= 2 , 
	form_maxlag=  12, hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= mom; by secid date_var; run;

%form_hold_period_seas_2third (input=data2, output=seasonality, date=date_var, id=secid,
	form_var= vix_all, hold_var= vix_posoi, form_minlag= &minlag , 
	form_maxlag= &maxlag, seasonality_period= &periods ,hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= seasonality; by secid date_var; run;

%form_hold_period_seas_2third (input=data2, output=seasonality_a, date=date_var, id=secid,
	form_var= vix_all, hold_var= vix_posoi, form_minlag= &minlag , 
	form_maxlag= &maxlag, seasonality_period= 12 ,hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= seasonality_a; by secid date_var; run;

*FM;
%FM (INSET=seasonality,OUTSET=FM1,DATEVAR=date_var,DEPVAR=hvar, INDVARS=fvar  ,LAG=3);
proc transpose data= FM1 out= FM1_1; var estimate tvalue; id parameter;
run;
data FM1_2 (drop= _label_ parameter rename= (fvar= fvar_seasonality)); merge FM1_1 FM1 (keep= rsq parameter where= (parameter= "fvar")); run;

%FM (INSET=seasonality_a,OUTSET=FM1a,DATEVAR=date_var,DEPVAR=hvar, INDVARS=fvar  ,LAG=3);
proc transpose data= FM1a out= FM1a_1; var estimate tvalue; id parameter;
run;
data FM1a_2 (drop= _label_ parameter rename= (fvar= fvar_seasonality_a)); merge FM1a_1 FM1a (keep= rsq parameter where= (parameter= "fvar")); run;

%FM (INSET=mom,OUTSET=FM2,DATEVAR=date_var,DEPVAR=hvar, INDVARS=fvar  ,LAG=3);
proc transpose data= FM2 out= FM2_1; var estimate tvalue; id parameter;
run;
data FM2_2 (drop= _label_ parameter rename= (fvar= fvar_mom)); merge FM2_1 FM2 (keep= rsq parameter where= (parameter= "fvar")); run;

data merge0; merge seasonality (rename= (fvar= fvar_seasonality)) seasonality_a (rename= (fvar= fvar_seasonality_a)); by secid date_var; run;
%FM (INSET=merge0,OUTSET=FM3,DATEVAR=date_var,DEPVAR=hvar, INDVARS=fvar_seasonality fvar_seasonality_a ,LAG=3);
proc transpose data= FM3 out= FM3_1; var estimate tvalue; id parameter;
run;
data FM3_2 (drop= _label_ parameter); merge FM3_1 FM3 (keep= rsq parameter where= (parameter= "fvar_seasonality")); run;

data merge1; merge seasonality (rename= (fvar= fvar_seasonality)) mom (rename= (fvar= fvar_mom)); by secid date_var; run;
%FM (INSET=merge1,OUTSET=FM4,DATEVAR=date_var,DEPVAR=hvar, INDVARS=fvar_seasonality fvar_mom ,LAG=3);
proc transpose data= FM4 out= FM4_1; var estimate tvalue; id parameter;
run;
data FM4_2 (drop= _label_ parameter); merge FM4_1 FM4 (keep= rsq parameter where= (parameter= "fvar_seasonality")); run;

data merge2; merge seasonality_a (rename= (fvar= fvar_seasonality_a)) mom (rename= (fvar= fvar_mom)); by secid date_var; run;
%FM (INSET=merge2,OUTSET=FM5,DATEVAR=date_var,DEPVAR=hvar, INDVARS=fvar_seasonality_a fvar_mom ,LAG=3);
proc transpose data= FM5 out= FM5_1; var estimate tvalue; id parameter;
run;
data FM5_2 (drop= _label_ parameter); merge FM5_1 FM5 (keep= rsq parameter where= (parameter= "fvar_seasonality_a")); run;

data merge3; merge seasonality (rename= (fvar= fvar_seasonality)) seasonality_a (rename= (fvar= fvar_seasonality_a)) mom (rename= (fvar= fvar_mom)); by secid date_var; run;
%FM (INSET=merge3,OUTSET=FM6,DATEVAR=date_var,DEPVAR=hvar, INDVARS=fvar_seasonality fvar_seasonality_a fvar_mom ,LAG=3);
proc transpose data= FM6 out= FM6_1; var estimate tvalue; id parameter;
run;
data FM6_2 (drop= _label_ parameter); merge FM6_1 FM6 (keep= rsq parameter where= (parameter= "fvar_seasonality")); run;



data FM_out;
	set  FM1_2 FM1a_2 FM2_2 FM3_2 FM4_2 FM5_2 FM6_2;
run;


*save on excel file: open a new sheet, rename it to "FM (seas q&a and mom- 2 third)";

filename example1 dde "excel|FM (seas q&a and mom- 2 third)!r&row1.c14:r&row2.c20";
data _null_;
	set fm_out;
	file example1;
	put intercept fvar_seasonality fvar_seasonality_a fvar_mom rsq;
run;

%mend;


*quarterly;
%seas(1,36,3,3);

