

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


* merge crsp link table to get permnos;
proc sort data=data.ccmxpf_lnkhist_2022feb out=lnk;
  	where LINKTYPE in ("LU", "LC", "LD", "LF", "LN", "LO", "LS", "LX") and
    		(2021 >= year(LINKDT) or LINKDT = .B) and (1950 <= year(LINKENDDT) or LINKENDDT = .E);
  	by GVKEY LINKDT; 
run;	
 
proc sql; create table temp as select a.lpermno as permno,b.*
	from lnk a, data.rdq_2022 b where a.gvkey=b.gvkey 
		and (LINKDT <= b.datadate or LINKDT = .B) and (b.datadate <= LINKENDDT or LINKENDDT = .E) and lpermno ne . ;
quit; 
 
data rdq;
	set temp;
	where not missing(permno) and not missing(datadate);
run;  	
proc sort data= rdq nodupkey; by permno rdq; run;



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

* Adding earning dates;
proc sql;
	create table data3
	as select a.*, b.rdq
	from data2 as a left join rdq as b
	on a.permno = b.permno and a.beg_date <= b.rdq <= a.date_var;
quit;



******** earning months;
data data3_with_ea;
	set data3;
	if rdq ne . ; 
run;

%form_hold_period_seas_2third (input=data3_with_ea, output=data4_with_ea, date=date_var, id=secid,
	form_var= vix_all, hold_var= vix_posoi, form_minlag= &minlag , 
	form_maxlag= &maxlag, seasonality_period= &periods ,hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);


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


*save on excel file: open a new sheet, rename it to "Usorts-Earning-announcements";

filename example1 dde "excel|Usorts-Earning-announcements!r&row1.c3:r&row2.c10";
data _null_;
	set out1;
	file example1;
	put cs_l--min_num_firm;
run;


******** non-earning months;

data data3_without_ea;
	set data3;
	if rdq = . ; 
run;

%form_hold_period_seas_2third (input=data3_without_ea, output=data4_without_ea, date=date_var, id=secid,
	form_var= vix_all, hold_var= vix_posoi, form_minlag= &minlag , 
	form_maxlag= &maxlag, seasonality_period= &periods ,hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);

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


*save on excel file: open a new sheet, rename it to "Usorts-Earning-announcements";

filename example1 dde "excel|Usorts-Earning-announcements!r&row1.c12:r&row2.c19";
data _null_;
	set out1wo;
	file example1;
	put cs_l--min_num_firm;
run;

%mend;


*quarterly;
%seas(1,12,3,1);
%seas(1,36,3,2);
