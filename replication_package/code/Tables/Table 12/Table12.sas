
*--------------------------------------------------------------------;

%let root=D:\vixseas;

libname here "&root\Data Raw";

*include all sas macros in the folder;
%include "&root\Code\SAS functions\*.sas";

*--------------------------------------------------------------------;



%macro seas(minlag, maxlag, periods, rr);


proc delete data= work._all_; run;
dm 'odsresults; clear';
 
%let row1= %sysfunc(sum(-6, (16* &rr.)));
%let row2= %sysfunc(sum(9, (16* &rr.)));

proc sql;
	create table data1
	as select a.secid, a.exdate_trade as date_var, a.dynamic_vix_return_corridor - a.rf as vix_all, b.dynamic_vix_return_corridor - b.rf as vix_posoi, a.rf as rfret, 
			 a.date as beg_date, 
			a.VIX_Prc*(1+a.Rf) as Monthly_IV_all , log(a.VIX_Prc*(1+a.Rf)) as logMonthly_IV_all,
		   log((1+a.VSR_Corridor)*a.VIX_Prc ) as logMonthly_RV_cor_all, 
		    b.VIX_Prc*(1+b.Rf) as Monthly_IV_posoi ,log(b.VIX_Prc*(1+b.Rf)) as logMonthly_IV_posoi,
		   log((1+b.VSR_Corridor)*b.VIX_Prc) as logMonthly_RV_cor_posoi
		   , a.shrcd, a.mkt_cap
	from here.simpson_return_0_oi_bid as a left join here.simpson_return as b
	on a.secid = b.secid and a.exdate_trade= b.exdate_trade;
quit;


data data2;
	set data1;
	mcap= mkt_cap;
	RV_IV_all= logMonthly_RV_cor_all - logMonthly_IV_all;
	RV_IV_posoi= logMonthly_RV_cor_posoi - logMonthly_IV_posoi;
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

	if not missing(mom) and not missing(seasonality) ;

run;

proc sort data= data5 nodupkey; by secid date_var; run;


*regressions;
%FM (INSET=data5,OUTSET=FM1,DATEVAR=date_var,DEPVAR=logMonthly_RV_cor_posoi, INDVARS= mom ,LAG=3);
proc transpose data= FM1 out= FM1_1; var estimate tvalue; id parameter;
run;
data FM1_2 (drop= _label_ parameter ); merge FM1_1 FM1 (keep= rsq parameter where= (parameter= "mom")); run;

%FM (INSET=data5,OUTSET=FM2,DATEVAR=date_var,DEPVAR=logMonthly_RV_cor_posoi, INDVARS= seasonality mom ,LAG=3);
proc transpose data= FM2 out= FM2_1; var estimate tvalue; id parameter;
run;
data FM2_2 (drop= _label_ parameter ); merge FM2_1 FM2 (keep= rsq parameter where= (parameter= "seasonality")); run;

%FM (INSET=data5,OUTSET=FM3,DATEVAR=date_var,DEPVAR=logMonthly_RV_cor_posoi, INDVARS= mom logMonthly_IV_posoi,LAG=3);
proc transpose data= FM3 out= FM3_1; var estimate tvalue; id parameter;
run;
data FM3_2 (drop= _label_ parameter ); merge FM3_1 FM3 (keep= rsq parameter where= (parameter= "mom")); run;

%FM (INSET=data5,OUTSET=FM4,DATEVAR=date_var,DEPVAR=logMonthly_RV_cor_posoi, INDVARS= seasonality mom logMonthly_IV_posoi,LAG=3);
proc transpose data= FM4 out= FM4_1; var estimate tvalue; id parameter;
run;
data FM4_2 (drop= _label_ parameter ); merge FM4_1 FM4 (keep= rsq parameter where= (parameter= "seasonality")); run;



%FM (INSET=data5,OUTSET=FM5,DATEVAR=date_var,DEPVAR=logMonthly_IV_posoi, INDVARS= seasonality mom ,LAG=3);
proc transpose data= FM5 out= FM5_1; var estimate tvalue; id parameter;
run;
data FM5_2 (drop= _label_ parameter ); merge FM5_1 FM5 (keep= rsq parameter where= (parameter= "seasonality")); run;


%FM (INSET=data5,OUTSET=FM6,DATEVAR=date_var,DEPVAR=RV_IV_posoi, INDVARS= seasonality mom ,LAG=3);
proc transpose data= FM6 out= FM6_1; var estimate tvalue; id parameter;
run;
data FM6_2 (drop= _label_ parameter ); merge FM6_1 FM6 (keep= rsq parameter where= (parameter= "seasonality")); run;

%FM (INSET=data5,OUTSET=FM7,DATEVAR=date_var,DEPVAR=RV_IV_posoi, INDVARS= mom ,LAG=3);
proc transpose data= FM7 out= FM7_1; var estimate tvalue; id parameter;
run;
data FM7_2 (drop= _label_ parameter ); merge FM7_1 FM7 (keep= rsq parameter where= (parameter= "mom")); run;


data Fm_out;
	set fm1_2 fm2_2 fm3_2 fm4_2 fm5_2 fm6_2  fm7_2;
run;


*save on excel file: open a new sheet, rename it to "IV-Corridor RV";
filename example1 dde "excel|IV-Corridor RV!r&row1.c4:r&row2.c9";
data _null_;
	set fm_out;
	file example1;
	put intercept seasonality mom  logMonthly_IV_posoi rsq ;
run;


%mend;

*3 to 12 lags;
%seas(1,12,3,1);

*3 to 36 lags;
%seas(1,36,3,2);

 	
