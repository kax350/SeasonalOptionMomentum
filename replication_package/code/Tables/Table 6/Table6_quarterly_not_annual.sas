
*--------------------------------------------------------------------;

%let root=D:\vixseas;

libname here "&root\Data Raw";

*include all sas macros in the folder;
%include "&root\Code\SAS functions\*.sas";

*--------------------------------------------------------------------;




%macro seas(minlag, maxlag, periods, rr);


proc delete data= work._all_; run;
dm 'odsresults; clear';


%let row1= %sysfunc(sum(4, (2* &rr.)));
%let row2= %sysfunc(sum(5, (2* &rr.)));



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



%form_hold_period_seas_2third (input=data2, output=data3, date=date_var, id=secid,
	form_var= vix_all, hold_var= vix_posoi, form_minlag= &minlag , 
	form_maxlag= &maxlag, seasonality_period= &periods ,hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);


*CS;
%HL_CS_length (input=data3, output=CS1, date=date_var, id=secid, sortvar=fvar,
		depvar=hvar, port_weight=mcap, ngroups=5, HL_length=1);



%GMM(indst= CS1, outset=CS2, depVar= ew_ret,IndepVars=,byVars=group,lags=3); 


*prepare data for outputs;
data blank; v= .; run;
data out1;
	merge CS2 (where= (group="_L") keep= a group rename=(a= CS_L)) 
		CS2 (where= (group="_2") keep= a group rename=(a= CS_2))
		CS2 (where= (group="_3") keep= a group rename=(a= CS_3))
		CS2 (where= (group="_4") keep= a group rename=(a= CS_4))
			CS2 (where= (group="_H") keep= a group rename=(a= CS_H))
			CS2 (where= (group="_H_L") keep= a group rename=(a= CS_H_L))
			;
			drop group;
run;



*save on excel file: open a new sheet, rename it to "Seasonal vs Non-seasonal(QnotA)";

filename example1 dde "excel|Seasonal vs Non-seasonal(QnotA)!r&row1.c3:r&row2.c8";
data _null_;
	set out1;
	file example1;
	put cs_l--cs_h_l;
run;

%mend;


*quarterly;
%seas(1,11,3,1);
%seas(13,23,3,2);
%seas(25,35,3,3);
%seas(37,47,3,4);
%seas(49,59,3,5);

