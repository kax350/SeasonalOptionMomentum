
*--------------------------------------------------------------------;

%let root=D:\vixseas;

libname here "&root\Data Raw";
libname data "&root\Data Out";

*include all sas macros in the folder;
%include "&root\Code\SAS functions\*.sas";

*--------------------------------------------------------------------;




%macro seas(minlag, maxlag, periods, rr);


proc delete data= work._all_; run;
dm 'odsresults; clear';


%let row1= %sysfunc(sum(6, (2* &rr.)));
%let row2= %sysfunc(sum(7, (2* &rr.)));


proc sql;
	create table data1
	as select a.secid, a.exdate_trade as date_var, a.shrcd, a.dynamic_vix_return_corridor - a.rf as vix_all, b.dynamic_vix_return_corridor - b.rf as vix_posoi, a.rf as rfret,
		a.mkt_cap, a.date as beg_date, a.permno
	from here.simpson_return_0_oi_bid as a left join here.simpson_return as b
	on a.secid = b.secid and a.exdate_trade= b.exdate_trade;
quit;

data data2;
	set data1;
	mcap= mkt_cap;
run;

proc sort data= data2 nodupkey; by permno date_var; run;
proc sort data= data2 nodupkey; by secid date_var; run;

* Adding typical cycles for each firm;
proc sql;
	create table data3
	as select a.*, b.*
	from data2 as a left join here.expiration_cycle as b
	on a.secid = b.secid ;
quit;

proc sort data= data3 nodupkey; by secid date_var; run;

%form_hold_period_seas_2third (input=data3, output=data4, date=date_var, id=secid,
	form_var= vix_all, hold_var= vix_posoi, form_minlag= &minlag , 
	form_maxlag= &maxlag, seasonality_period= &periods ,hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);

******** in cycle months;
data data4_with_ea;
	set data4;
	if month(date_var) = cycle or  month(date_var)= cycle +3 or  month(date_var)= cycle +6 or  month(date_var)= cycle +9; 
run;

*CS;
%HL_CS_length (input=data4_with_ea, output=CS1, date=date_var, id=secid, sortvar=fvar,
		depvar=hvar, port_weight=mcap, ngroups=5, HL_length=1);

%GMM(indst= CS1, outset=CS2, depVar= ew_ret,IndepVars=,byVars=group,lags=3); 



proc sql;	create table monthly_avg as select n(fvar) as num_firm from data4_with_ea where vix_posoi ne . and fvar ne . group by date_var; quit;
proc sql; create table avg as select mean(num_firm) as num_firm , min(num_firm) as min_num_firm from monthly_avg; quit;


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


*save on excel file: open a new sheet, rename it to "Usorts-cyclic-patterns";

filename example1 dde "excel|Usorts-cyclic-patterns!r&row1.c3:r&row2.c10";
data _null_;
	set out1;
	file example1;
	put cs_l--min_num_firm;
run;


******** non-cyclic months;
data data4_without_ea;
	set data4;
	if month(date_var) = cycle or  month(date_var)= cycle +3 or  month(date_var)= cycle +6 or  month(date_var)= cycle +9 then delete;
run;

*CS;
%HL_CS_length (input=data4_without_ea, output=CS1wo, date=date_var, id=secid, sortvar=fvar,
		depvar=hvar, port_weight=mcap, ngroups=5, HL_length=1);

%GMM(indst= CS1wo, outset=CS2wo, depVar= ew_ret,IndepVars=,byVars=group,lags=3); 



proc sql;	create table monthly_avg_wo as select n(fvar) as num_firm from data4_without_ea where vix_posoi ne . and fvar ne . group by date_var; quit;
proc sql; create table avg_wo as select mean(num_firm) as num_firm , min(num_firm) as min_num_firm from monthly_avg_wo; quit;


*prepare data for outputs;
data blank; v= .; run;
data out1wo;
	merge CS2wo (where= (group="_L") keep= a group rename=(a= CS_L)) 
		CS2wo (where= (group="_2") keep= a group rename=(a= CS_2))
		CS2wo (where= (group="_3") keep= a group rename=(a= CS_3))
		CS2wo (where= (group="_4") keep= a group rename=(a= CS_4))
			CS2wo (where= (group="_H") keep= a group rename=(a= CS_H))
			CS2wo (where= (group="_H_L") keep= a group rename=(a= CS_H_L))
			avg_wo
			;
			drop group;
run;

*save on excel file: open a new sheet, rename it to "Usorts-cyclic-patterns";
filename example1 dde "excel|Usorts-cyclic-patterns!r&row1.c12:r&row2.c19";
data _null_;
	set out1wo;
	file example1;
	put cs_l--min_num_firm;
run;

%mend;


*quarterly;
%seas(1,12,3,1);
%seas(1,36,3,2);

