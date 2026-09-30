
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


%let row1= %sysfunc(sum(-3, (9* &rr.)));
%let row2= %sysfunc(sum(3, (9* &rr.)));




data CS1;
	set seas.CS_DVIX_MF_&minlag._&maxlag._&periods.;  
	if group= "_H_L";
run;


proc sql;
	create table CS2
	as select *, mean(ew_ret) as mean
	from CS1;
quit;

data CS3;
	set CS2;
	if mean < 0 then ew_ret_p= ew_ret * -1;
	else ew_ret_p= ew_ret;
run;

proc means data= CS3 mean std skew kurt; var ew_ret_p; output out= cs_mean mean=mean std=std kurt=kurt skew=skew;run;

*t;
*SR;
%GMM(indst= CS3, outset=CS4, depVar= ew_ret_p,IndepVars=,byVars=group,lags=3); 

data CS_t; set CS4; if _name_= "T"; keep a; run;
data CS_SR; set CS4; if _name_= "Est"; keep sharpe; run;

*MAXDD;
*we examine the maximum drawdown of each portfolio, defined as the largest fraction by which
the cumulative value of a factor portfolio falls below its prior maximum;

proc sort data= here.simpson_return_0_oi_bid out= ff_monthly  (keep= exdate_trade rf) nodupkey; by exdate_trade; run;

proc sql;
	create table CS5
	as select a.date_Var, a.ew_ret, a.ew_ret_p, b.rf
	from CS3 as a, ff_monthly as b
	where intnx("month",a.date_Var, 0,"e")=intnx("month",b.exdate_trade, 0,"e");
quit; 
data CS6;
	set CS5;
	rr= sum(ew_ret_p, 1, rf);
run;


proc sql;
	create table cs6s
	as select a.date_var, b.rr, a.date_var - b.date_var as dif
	from CS6 as a, CS6 as b
	where a.date_Var >= b.date_var;
quit;


proc sort data= cs6s; by date_var dif; run;
data CS6_cumpret;
	set cs6s;
	by date_var	;
	retain cumret;
	if first.date_var then cumret= 1;
	cumret= cumret * rr;
	if last.date_Var then output;
run;

proc sql;
	create table CS6_priormax
	as select distinct a.date_var, a.cumret, max(b.cumret) as priormax
	from CS6_cumpret as a, CS6_cumpret as b
	where a.date_var> b.date_Var
	group by a.date_var;
quit;
data CS6_priormax2;
	set CS6_priormax;
	val= (cumret / priormax) -1;
run;
proc sql;
	create table CS6_priormax3
	as select min(min (val) * -1,1) as a
	from CS6_priormax2;
quit; 

*prepare data for outputs;
data blank; v= .; run;
data out1;
	set CS_mean (keep= mean rename=(mean= a))
		CS_t  
		CS_mean (keep= std rename=(std= a))
		CS_sr (keep= sharpe rename=(sharpe= a))
		CS_mean (keep= skew rename=(skew= a))
		CS_mean (keep= kurt rename=(kurt= a))
		CS6_priormax3	
		;
run;


*save on excel file: open a new sheet, rename it to "Factor moments";
filename example1 dde "excel|Factor moments!r&row1.c4:r&row2.c4";
data _null_;
	set out1;
	file example1;
	put a;
run;




%mend;


%seas(1,12,3,1);
%seas(1,36,3,2);
