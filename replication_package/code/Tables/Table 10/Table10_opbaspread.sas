
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

%let row1= %sysfunc(sum(-4, (10* &rr.)));
%let row2= %sysfunc(sum(3, (10* &rr.)));



proc sql;
	create table data1
	as select a.secid, a.exdate_trade as date_var, a.shrcd, a.dynamic_vix_return_corridor - a.rf as vix_all, b.dynamic_vix_return_corridor - b.rf as vix_posoi, a.rf as rfret,
		a.mkt_cap, a.permno, b.vix_ba_percent
	from here.simpson_return_0_oi_bid as a left join here.simpson_return as b
	on a.secid = b.secid and a.exdate_trade= b.exdate_trade;
quit;

data data2;
	set data1;
	mcap= mkt_cap;
	op_baspread= vix_ba_percent;
run;


*calculate baspread as the average of last 6 and 12 months;
proc sql;
	create table baspread3
	as select a.secid, a.date_var, mean(b.op_baspread) as op_baspread_6
	from data2 as a, data2 as b
	where a.secid= b.secid and 0 <= intck("month", b.date_var, a.date_var) <= 5
	group by a.secid , a.date_var;
quit;

proc sql;
	create table baspread4
	as select a.secid, a.date_var,  mean(b.op_baspread) as op_baspread_12
	from data2 as a, data2 as b
	where a.secid= b.secid and 0 <= intck("month", b.date_var, a.date_var) <= 11
	group by a.secid , a.date_var;
quit;

proc sql;
	create table baspread5
	as select a.*, b.op_baspread_6 
	from data2 as a left join baspread3 as b
	on a.secid = b.secid and a.date_var= b.date_var;
quit;

proc sql;
	create table baspread6
	as select a.*, b.op_baspread_12 
	from baspread5 as a left join baspread4 as b
	on a.secid = b.secid and a.date_var= b.date_var;
quit;

proc sql;
	create table data3
	as select a.* , b.op_baspread, b.op_baspread_6 , b.op_baspread_12
	from data2 as a left join baspread6 as b
	on a.secid = b.secid and a.date_var= b.date_var;
quit;


* we first sort sample based on characterestics ;

%form_hold_period_seas_2third (input=data3, output=data4, date=date_var, id=secid,
	form_var= vix_all, hold_var= vix_posoi, form_minlag= &minlag , 
	form_maxlag= &maxlag, seasonality_period= &periods ,hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);


*CS - 3*5;
%DSORT_seq_ew (input=data4, output=CS1, date=date_var, id=secid, sortvar1= op_baspread_12, sortvar2=fvar,
		depvar=hvar, port_weight=mcap, ngroups1=3, ngroups2=5);
data CS2;
	set CS1; 
	_L= mean(_1,_2);
	_H= mean(_4,_5);
	_45_12= _H - _L;
run;


%GMM(indst= CS1, outset=CS2_1, depVar= _1,IndepVars=,byVars=group,lags=3); 
%GMM(indst= CS1, outset=CS2_2, depVar= _2,IndepVars=,byVars=group,lags=3); 
%GMM(indst= CS1, outset=CS2_3, depVar= _3,IndepVars=,byVars=group,lags=3); 
%GMM(indst= CS1, outset=CS2_4, depVar= _4,IndepVars=,byVars=group,lags=3); 
%GMM(indst= CS1, outset=CS2_5, depVar= _5,IndepVars=,byVars=group,lags=3);
%GMM(indst= CS1, outset=CS2_6, depVar= _h_L,IndepVars=,byVars=group,lags=3);

%GMM(indst= CS2, outset=CS2_7, depVar= _L,IndepVars=,byVars=group,lags=3);
%GMM(indst= CS2, outset=CS2_8, depVar= _h,IndepVars=,byVars=group,lags=3); 
%GMM(indst= CS2, outset=CS2_9, depVar= _45_12,IndepVars=,byVars=group,lags=3); 


*prepare data for outputs;
data blank; v= .; run;
data out1;
	merge CS2_1 ( keep= a group rename=(a= CS_L)) 
		CS2_2 ( keep= a group rename=(a= CS_2))
		CS2_3 (keep= a group rename=(a= CS_3))
		CS2_4 ( keep= a group rename=(a= CS_4))
		CS2_5 (keep= a group rename=(a= CS_H))
		CS2_6 ( keep= a group rename=(a= CS_H_L))
		CS2_9 ( keep= a group rename=(a= CS_HH_LL));

			drop group;
run;


*save on excel file: open a new sheet, rename it to "Option baspread";
filename example1 dde "excel|Option baspread!r&row1.c3:r&row2.c9";
data _null_;
	set out1;
	file example1;
	put cs_l--cs_hh_ll;
run;


*CS - 3 *3;
%DSORT_seq_ew (input=data4, output=CS1, date=date_var, id=secid, sortvar1= op_baspread_12, sortvar2=fvar,
		depvar=hvar, port_weight=mcap, ngroups1=3, ngroups2=3);

%GMM(indst= CS1, outset=CS2_1, depVar= _1,IndepVars=,byVars=group,lags=3); 
%GMM(indst= CS1, outset=CS2_2, depVar= _2,IndepVars=,byVars=group,lags=3); 
%GMM(indst= CS1, outset=CS2_3, depVar= _3,IndepVars=,byVars=group,lags=3); 

%GMM(indst= CS1, outset=CS2_6, depVar= _h_L,IndepVars=,byVars=group,lags=3); 


*prepare data for outputs;
data blank; v= .; run;
data out1;
	merge CS2_1 ( keep= a group rename=(a= CS_L)) 
		CS2_2 ( keep= a group rename=(a= CS_2))
		CS2_3 (keep= a group rename=(a= CS_3))

		CS2_6 ( keep= a group rename=(a= CS_H_L));
			drop group;
run;


*save on excel file: open a new sheet, rename it to "Option baspread";
filename example1 dde "excel|Option baspread!r&row1.c12:r&row2.c15";
data _null_;
	set out1;
	file example1;
	put cs_l--cs_h_l;
run;



%mend;

%seas(1,12,3,1);
%seas(1,36,3,2);
