
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
	as select a.secid, a.exdate_trade as date_var, a.shrcd, 
		a.dynamic_vix_return_corridor - a.rf as vix_all, b.dynamic_vix_return_corridor - b.rf as vix_posoi, 
		a.mkt_cap, b.vix_ba_percent
		, (b.dynamic_vix_ret_corridor_bid_203 * -1)+ b.rf as seller_ret_algo , b.dynamic_vix_ret_corridor_ask_203 - b.rf as buyer_ret_algo
		, (b.dynamic_vix_ret_corridor_bid_516 * -1)+ b.rf as seller_ret_adjusted , b.dynamic_vix_ret_corridor_ask_516 - b.rf as buyer_ret_adjusted
		, (b.dynamic_vix_ret_corridor_bid_758 * -1)+ b.rf as seller_ret_effective , b.dynamic_vix_ret_corridor_ask_758 - b.rf as buyer_ret_effective
		, (b.dynamic_vix_ret_corridor_bid * -1)+ b.rf as seller_ret_quoted , b.dynamic_vix_ret_corridor_ask - b.rf as buyer_ret_quoted
		, (b.dynamic_vix_return_corridor * -1)+ b.rf as seller_ret , b.dynamic_vix_return_corridor - b.rf as buyer_ret

	from here.simpson_return_0_oi_bid as a left join here.transaction_cost as b
	on a.secid = b.secid and a.exdate_trade= b.exdate_trade;
quit;

data data2;
	set data1;
	mcap= mkt_cap;
run;


%form_hold_period_seas_2third (input=data2, output=data3, date=date_var, id=secid,
	form_var= vix_all, hold_var= vix_posoi, form_minlag= &minlag , 
	form_maxlag= &maxlag, seasonality_period= &periods ,hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);


%macro do_it(buyvar, sellvar, r);

%let row1= %sysfunc(sum(0, (2* &r.), (12* &rr.)));
%let row2= %sysfunc(sum(1, (2* &r.), (12* &rr.)));


********************************* main sample; 
data data4;
	set data3;
run;

*CS;
%HL_CS_length (input=data4, output=CS1a, date=date_var, id=secid, sortvar=fvar,
		depvar=&sellvar , port_weight=mcap, ngroups=5, HL_length=1);

%GMM(indst= CS1a, outset=CS2a, depVar= ew_ret,IndepVars=,byVars=group,lags=3); 


%HL_CS_length (input=data4, output=CS1b, date=date_var, id=secid, sortvar=fvar,
		depvar=&buyvar , port_weight=mcap, ngroups=5, HL_length=1);

%GMM(indst= CS1b, outset=CS2b, depVar= ew_ret,IndepVars=,byVars=group,lags=3); 

* buy Q5 / write Q1;
data CS1a_1; set CS1a; if group="_L"; run;
data CS1b_1; set CS1b; if group="_H"; run;
proc sql; create table CS1ab as select a.date_var, "WQ1_BQ5" as group, 1 as num_firm, a.ew_ret + b.ew_ret as ew_ret from CS1a_1 as a, CS1b_1 as b where a.date_var= b.date_var; quit;

%GMM(indst= CS1ab, outset=CS2ab, depVar= ew_ret,IndepVars=,byVars=group,lags=3); 

*prepare data for outputs;
data blank; v= .; run;
data out1;
	merge CS2a (where= (group="_L") keep= a group rename=(a= CSa_L)) 
			CS2a (where= (group="_H") keep= a group rename=(a= CSa_H))
			CS2b (where= (group="_L") keep= a group rename=(a= CSb_L)) 
			CS2b (where= (group="_H") keep= a group rename=(a= CSb_H))
			CS2ab (where= (group="WQ1_BQ5") keep= a group rename=(a= CSab_HL))
			;
			drop group;
run;

*save on excel file: open a new sheet, rename it to "TC";
filename example1 dde "excel|TC!r&row1.c6:r&row2.c6";
data _null_;
	set out1;
	file example1;
	put CSab_HL;
run;



*************************************** Decile;
data data4;
	set data3;
run;

*CS;
%HL_CS_length (input=data4, output=CS1a, date=date_var, id=secid, sortvar=fvar,
		depvar=&sellvar , port_weight=mcap, ngroups=10, HL_length=1);

%GMM(indst= CS1a, outset=CS2a, depVar= ew_ret,IndepVars=,byVars=group,lags=3); 


%HL_CS_length (input=data4, output=CS1b, date=date_var, id=secid, sortvar=fvar,
		depvar=&buyvar , port_weight=mcap, ngroups=10, HL_length=1);

%GMM(indst= CS1b, outset=CS2b, depVar= ew_ret,IndepVars=,byVars=group,lags=3); 

* buy Q10 / write Q1;
data CS1a_1; set CS1a; if group="_L"; run;
data CS1b_1; set CS1b; if group="_H"; run;
proc sql; create table CS1ab as select a.date_var, "WQ1_BQ5" as group, 1 as num_firm, a.ew_ret + b.ew_ret as ew_ret from CS1a_1 as a, CS1b_1 as b where a.date_var= b.date_var; quit;

%GMM(indst= CS1ab, outset=CS2ab, depVar= ew_ret,IndepVars=,byVars=group,lags=3); 

*prepare data for outputs;
data blank; v= .; run;
data out1;
	merge CS2a (where= (group="_L") keep= a group rename=(a= CSa_L)) 
			CS2a (where= (group="_H") keep= a group rename=(a= CSa_H))
			CS2b (where= (group="_L") keep= a group rename=(a= CSb_L)) 
			CS2b (where= (group="_H") keep= a group rename=(a= CSb_H))
			CS2ab (where= (group="WQ1_BQ5") keep= a group rename=(a= CSab_HL))
			;
			drop group;
run;

*save on excel file: open a new sheet, rename it to "TC";
filename example1 dde "excel|TC!r&row1.c7:r&row2.c7";
data _null_;
	set out1;
	file example1;
	put CSab_HL;
run;

*************************************decile with low cost : 1st method;

data data4;
	set data3;
run;

*******buyside;
*CS;
proc sort data= data4;
	by date_var;
run;
proc rank data=data4 (where=(missing(fvar)=0)) out=_s1  ties=low groups=10;
    by date_var;
   	var fvar ;
    ranks fvar_r;
run;
data _s2;
	set _s1;
	fvar_r = fvar_r +1;
	if fvar_r ne . ;
run;

proc sort data= _s2; by date_var; run;
proc rank data=_s2 (where=(missing(VIX_BA_percent)=0)) out=_s3  ties=low groups=2;
    by date_var;
   	var VIX_BA_percent ;
    ranks op_baspread_ratio_r;
run;

proc sql;
	create table CS1a
	as select distinct date_var, fvar_r as group, mean(&sellvar) as ew_ret, n(&sellvar) as num_firm
	from _s3
	where  VIX_BA_percent < 0.25
	group by date_var,fvar_r;
quit;

%GMM(indst= CS1a, outset=CS2a, depVar= ew_ret,IndepVars=,byVars=group,lags=3); 

*buy side;
proc sql;
	create table CS1b
	as select distinct date_var, fvar_r as group, mean(&buyvar) as ew_ret, n(&buyvar) as num_firm
	from _s3
	where  VIX_BA_percent < 0.25 
	group by date_var,fvar_r;
quit;

%GMM(indst= CS1b, outset=CS2b, depVar= ew_ret,IndepVars=,byVars=group,lags=3); 

* buy Q5 / write Q1;
data CS1a_1; set CS1a; if group=1; run;
data CS1b_1; set CS1b; if group=10; run;
proc sql; create table CS1ab as select a.date_var, 11 as group, 1 as num_firm, a.ew_ret + b.ew_ret as ew_ret from CS1a_1 as a, CS1b_1 as b where a.date_var= b.date_var; quit;

%GMM(indst= CS1ab, outset=CS2ab, depVar= ew_ret,IndepVars=,byVars=group,lags=3); 

*prepare data for outputs;
data blank; v= .; run;
data out1;
	merge CS2a (where= (group=1) keep= a group rename=(a= CSa_L)) 
			CS2a (where= (group=10) keep= a group rename=(a= CSa_H))
			CS2b (where= (group=1) keep= a group rename=(a= CSb_L)) 
			CS2b (where= (group=10) keep= a group rename=(a= CSb_H))
			CS2ab (where= (group=11) keep= a group rename=(a= CSab_HL))
			;
			drop group;
run;


*save on excel file: open a new sheet, rename it to "TC";
filename example1 dde "excel|TC!r&row1.c8:r&row2.c8";
data _null_;
	set out1;
	file example1;
	put CSab_HL;
run;


%mend;

%do_it(buyer_ret, seller_ret, 1);
%do_it(buyer_ret_algo, seller_ret_algo, 2);
%do_it(buyer_ret_adjusted, seller_ret_adjusted, 3);
%do_it(buyer_ret_effective, seller_ret_effective, 4);
%do_it(buyer_ret_quoted, seller_ret_quoted, 5);

%mend;


*quarterly;
%seas(1,12,3,1);
%seas(1,36,3,2);
