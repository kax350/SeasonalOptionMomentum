
*--------------------------------------------------------------------;

%let root=D:\vixseas;

libname here "&root\Data Raw";
libname data "&root\Data Out";

*include all sas macros in the folder;
%include "&root\Code\SAS functions\*.sas";

*--------------------------------------------------------------------;


proc delete data= work._all_; run;



proc sql;
	create table data1
	as select a.secid, a.exdate_trade as date_var, a.shrcd, a.dynamic_vix_return_corridor - a.rf as vix_all, b.dynamic_vix_return_corridor - b.rf as vix_posoi, a.rf as rfret, 
			 a.date as beg_date, b.atmiv_termspread, b.slope, b.iv_hv, b.idiovol, b.mkt_cap
	from here.simpson_return_0_oi_bid as a left join here.simpson_return as b
	on a.secid = b.secid and a.exdate_trade= b.exdate_trade;
quit;


data data2;
	set data1;
	mcap= mkt_cap;
run;

proc sort data= data2; by secid date_var; run;

%form_hold_period_2third (input=data2, output=mom, date=date_var, id=secid,
	form_var= vix_all, hold_var= vix_posoi, form_minlag= 2 , 
	form_maxlag=  12, hold_period=1, form_ret_type= AVG , hold_ret_type= AVG);
proc sort data= mom; by secid date_var; run;

data data5;
	merge data2 mom (rename= (fvar= mom));
	by secid date_var;
	drop hvar;
run;




%macro factors(input, output, date, id, factor_vars, ret_var, port_weight, ngroups);

	data s1;
		set &input ;
	run;

%do k=1 %to %nwords(&factor_vars);
        %let var=%scan(&factor_vars,&k,%str(' '));

	%HL_CS (input=s1, output=s3_&var. , date=date_var, id=&id, sortvar= &var , depvar=&ret_var, port_weight=&port_weight, ngroups=&ngroups);
	
	data s4_&var. (rename=(ew_ret= ew_&var. vw_ret= vw_&var.));
		set s3_&var.;
		if group= "_H_L";
		drop num_firm;
	run;
	 
%end;

data &output;
	merge s4_: ;
	by date_var;
run;


	proc datasets library= work;
		delete s: ; 
	run; quit;

%mend;


%factors(input=data5, output=data6, date=date_var, id=secid, factor_vars=slope mcap idiovol atmiv_termspread IV_HV mom
	, ret_var=vix_posoi, port_weight=mcap, ngroups=5);



*zerodelta_spx;
data data1_spx;
	set here.index_simpson_return;
run;

proc sql;
	create table data7
	as select a.*, (b.dynamic_vix_return  - b.rf) * -1 as spx_vix, b.exdate_trade
	from data6 as a, data1_spx as b
	where a.date_var=  b.exdate_trade;
quit;


*short all equity straddles;
proc sql;
	create table ew_vix
	as select date_var, mean(vix_posoi) * -1 as ew_vix
	from data2
	group by date_var;
quit;
proc sql;
	create table data8
	as select a.*, b.ew_vix  as ew_vix
	from data7 as a, ew_vix as b
	where a.date_var= b.date_var;
quit;


data data.factors_mf_0_bid;
	set data8;
run;



