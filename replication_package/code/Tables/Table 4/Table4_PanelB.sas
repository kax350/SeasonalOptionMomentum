

*--------------------------------------------------------------------;

%let root=D:\vixseas;

libname here "&root\Data Raw";
libname mom "&root\mom";

*include all sas macros in the folder;
%include "&root\Code\SAS functions\*.sas";

*--------------------------------------------------------------------;



%macro mom(minlag, maxlag, rr);

proc delete data= work._all_; run;
dm 'odsresults; clear';

%let row1= %sysfunc(sum(4, (2* &rr.)));
%let row2= %sysfunc(sum(5, (2* &rr.)));



proc sql;
	create table data1
	as select a.secid, a.exdate_trade as date_var, a.shrcd, a.dynamic_vix_return_corridor - a.rf as vix_all, b.dynamic_vix_return_corridor - b.rf as vix_posoi, a.rf as rfret,
		a.mkt_cap
	from here.simpson_return_0_oi_bid as a left join here.simpson_return as b
	on a.secid = b.secid and a.exdate_trade= b.exdate_trade;
quit;

data data2;
	set data1;
	mcap= mkt_cap;
run;


%form_hold_period_2third (input=data2, output=data3, date=date_var, id=secid,
	form_var= vix_all, hold_var= vix_posoi, form_minlag= &minlag , 
	form_maxlag= &maxlag, hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);


*CS;
%HL_CS_length (input=data3, output=CS1, date=date_var, id=secid, sortvar=fvar,
		depvar=hvar, port_weight=mcap, ngroups=5, HL_length=1);

%GMM(indst= CS1, outset=CS2, depVar= ew_ret,IndepVars=,byVars=group,lags=3); 



proc sql;	create table monthly_avg as select n(fvar) as num_firm from data3 where vix_posoi ne . and fvar ne . group by date_var; quit;
proc sql; create table avg as select mean(num_firm) as num_firm , min(num_firm) as min_num_firm from monthly_avg; quit;


* save momentums;
data mom.CS_DVIX_MF_&minlag._&maxlag.; set CS1; run;




*prepare data for outputs;
data blank; v= .; run;
data out1;
	merge CS2 (where= (group="_L") keep= a group rename=(a= CS_L)) 
		CS2 (where= (group="_2") keep= a group rename=(a= CS_2))
		CS2 (where= (group="_3") keep= a group rename=(a= CS_3))
		CS2 (where= (group="_4") keep= a group rename=(a= CS_4))
		CS2 (where= (group="_H") keep= a group rename=(a= CS_H))
		CS2 (where= (group="_H_L") keep= a group rename=(a= CS_H_L))
		avg
			;
			drop group;
run;


*save on excel file: open a new sheet, rename it to "Univariate sorts";
filename example1 dde "excel|Univariate sorts!r&row1.c3:r&row2.c10";
data _null_;
	set out1;
	file example1;
	put cs_l--min_num_firm;
run;

%mend;



%mom(2,12,7);
%mom(2,36,8);

