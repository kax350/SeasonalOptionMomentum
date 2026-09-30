
*--------------------------------------------------------------------;

%let root=D:\vixseas;

libname here "&root\Data Raw";

*include all sas macros in the folder;
%include "&root\Code\SAS functions\*.sas";

*--------------------------------------------------------------------;



%macro seas(minlag, maxlag, periods, rr);


proc delete data= work._all_; run;
dm 'odsresults; clear';


%let row1= %sysfunc(sum(-2, (8* &rr.)));
%let row2= %sysfunc(sum(4, (8* &rr.)));



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
	form_var= vix_all, hold_var= vix_posoi, form_minlag= &minlag , 
	form_maxlag=  &maxlag, hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= mom; by secid date_var; run;

%form_hold_period_seas_2third (input=data2, output=seasonality, date=date_var, id=secid,
	form_var= vix_all, hold_var= vix_posoi, form_minlag= &minlag , 
	form_maxlag= &maxlag, seasonality_period= &periods ,hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= seasonality; by secid date_var; run;

%form_hold_period_seas_other_2th (input=data2, output=Seasonal_reversal, date=date_var, id=secid,
	form_var= vix_all, hold_var= vix_posoi, form_minlag= &minlag , 
	form_maxlag= &maxlag, seasonality_period= &periods ,hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= Seasonal_reversal; by secid date_var; run;


data data3;
	merge  
		mom (rename= (fvar= mom))
		seasonality (rename= (fvar= seasonality))
		seasonal_reversal (rename= (fvar= seasonal_reversal))
	;
	by secid date_Var;
run;


proc sort data= data3 nodupkey; by secid date_var; run;

*CS-mom;
%HL_CS_length (input=data3, output=CS1a, date=date_var, id=secid, sortvar=mom,
		depvar=hvar, port_weight=mcap, ngroups=5, HL_length=1);
%GMM(indst= CS1a, outset=CS2a, depVar= ew_ret,IndepVars=,byVars=group,lags=3); 

%HL_CS_length (input=data3, output=CS1b, date=date_var, id=secid, sortvar=seasonality,
		depvar=hvar, port_weight=mcap, ngroups=5, HL_length=1);
%GMM(indst= CS1b, outset=CS2b, depVar= ew_ret,IndepVars=,byVars=group,lags=3); 

%HL_CS_length (input=data3, output=CS1c, date=date_var, id=secid, sortvar=seasonal_reversal,
		depvar=hvar, port_weight=mcap, ngroups=5, HL_length=1);
%GMM(indst= CS1c, outset=CS2c, depVar= ew_ret,IndepVars=,byVars=group,lags=3); 



*prepare data for outputs;
data blank; v= .; run;
data out1;
	merge CS2a (where= (group="_L") keep= a group rename=(a= CS_L)) 
		CS2a (where= (group="_2") keep= a group rename=(a= CS_2))
		CS2a (where= (group="_3") keep= a group rename=(a= CS_3))
		CS2a (where= (group="_4") keep= a group rename=(a= CS_4))
		CS2a (where= (group="_H") keep= a group rename=(a= CS_H))
		CS2a (where= (group="_H_L") keep= a group rename=(a= CS_H_L))
		;
		drop group;
run;

data out2;
	merge CS2b (where= (group="_L") keep= a group rename=(a= CS_L)) 
		CS2b (where= (group="_2") keep= a group rename=(a= CS_2))
		CS2b (where= (group="_3") keep= a group rename=(a= CS_3))
		CS2b (where= (group="_4") keep= a group rename=(a= CS_4))
		CS2b (where= (group="_H") keep= a group rename=(a= CS_H))
		CS2b (where= (group="_H_L") keep= a group rename=(a= CS_H_L))
		;
		drop group;
run;

data out3;
	merge CS2c (where= (group="_L") keep= a group rename=(a= CS_L)) 
		CS2c (where= (group="_2") keep= a group rename=(a= CS_2))
		CS2c (where= (group="_3") keep= a group rename=(a= CS_3))
		CS2c (where= (group="_4") keep= a group rename=(a= CS_4))
		CS2c (where= (group="_H") keep= a group rename=(a= CS_H))
		CS2c (where= (group="_H_L") keep= a group rename=(a= CS_H_L))
		;
		drop group;
run;


data out;
	set out1 out2 out3;
run;


*save on excel file: open a new sheet, rename it to "Seasonal vs Non-seasonal";

filename example1 dde "excel|Seasonal vs Non-seasonal!r&row1.c3:r&row2.c8";
data _null_;
	set out;
	file example1;
	put cs_l--cs_h_l;
run;

%mend;


*quarterly;
%seas(1,12,3,1);
%seas(13,24,3,2);
%seas(25,36,3,3);
%seas(37,48,3,4);
%seas(49,60,3,5);

*annually;
%seas(1,12,12,7);
%seas(13,24,12,8);
%seas(25,36,12,9);
%seas(37,48,12,10);
%seas(49,60,12,11);
