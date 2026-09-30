**********************************************************************************************
* Macro: GMM estimation of regression model and output a dataset "RegCoeff" 
  containing regression coeffs and their t-stats with NWlags;
* Input dataset "indst" needs to be sorted correctly already by "byVars" and by "time-series variable" (if applicable)
  to ensure correct calculation of NW std err correction;
**********************************************************************************************;

%macro GMM(indst, outset, depVar,IndepVars,byVars,lags); 

	proc sort data= &indst; by &byvars; run;

	*sharpe ratio;
	proc sql;
		create table _sharpe
		as select &byvars, mean(&depvar) / std(&depvar) as sharpe
		from &indst
		group by &byvars;
	quit;

	*min and mean of number of firms in each portfolio;
	proc means data= &indst noprint;
		by &byvars;
		var num_firm;
		output out= _num_firm mean= nfirm_mean min= nfirm_min;
	run; quit;	


	%if (%scan(&IndepVars,1)= ) %then %do;
	*case when IndepVars is empty (i.e., only intercept and no regressor);

	data gmmEst1;
		set _null_;
	run;
	data RegCoeff;
		set _null_;
	run;
	data RegCoeff_T;
		set _null_;
	run;

	proc model data=&indst noprint plots=none;
 		by &byVars;
 		instruments / intonly;
 		&depVar=a;
 		fit &depVar / gmm kernel=(bart,%eval(&lags+1),0) vardef=n outest=gmmEst1 COVOUT; 
	run;
	quit;

	data RegCoeff;
		set gmmEst1(keep=&byVars _name_ _nused_ a where=(_name_=''));
		_name_="Est";
	run;
	data RegCoeff_T(keep=&byVars _name_ _nused_ a );
		length _name_ $32;
		merge RegCoeff 
		gmmEst1(keep=&byVars _name_ a where=(_name_="a") rename=(a=aVar)) ;
		by &byVars;
		_name_="T";
		_nused_=.;
		a=a/aVar**(1/2);
	run;
	data RegCoeff;
		set RegCoeff RegCoeff_T;
	run;
	%end;
	%else %do;
	*case when IndepVars is not empty (i.e., intercept and regressor);

	%local xn i;

	%let xn=1;
	%do %until ( %scan(&IndepVars,&xn)= );
	%local var&xn;
    %let var&xn = %scan(&IndepVars,&xn);
    %put &&var&xn;
    %let xn=%EVAL(&xn + 1);
	%end;
	%let xn=%eval(&xn-1);
	%put &xn;

	data gmmEst1;
		set _null_;
	run;
	data RegCoeff;
		set _null_;
	run;
	data RegCoeff_T;
		set _null_;
	run;

	proc model data=&indst noprint plots=none;
		 by &byVars;
         endo &depVar;
         exog &IndepVars; 
		 instruments _exog_;
		 parms a %do i=1 %to &xn; coef_&&var&i %end;;
         &depVar= a %do i=1 %to &xn; + coef_&&var&i*&&var&i %end;;
         fit &depVar / gmm kernel=(bart,%eval(&lags+1),0) vardef=n outest=gmmEst1 COVOUT;
    run;
	quit; 
	data RegCoeff;
		set gmmEst1(keep=&byVars _name_ _nused_ a %do i=1 %to &xn; coef_&&var&i %end; where=(_name_=''));
		_name_="Est";
	run;
	data RegCoeff_T(keep=&byVars _name_ _nused_ a %do i=1 %to &xn; coef_&&var&i %end;);
		length _name_ $32;
		merge RegCoeff 
		 gmmEst1(keep=&byVars _name_ a where=(_name_="a") rename=(a=aVar))
		 %do i=1 %to &xn;
		 gmmEst1(keep=&byVars _name_ coef_&&var&i where=(_name_="coef_&&var&i") rename=(coef_&&var&i=coef_&&var&i..Var))
		 %end;
		 ;
		by &byVars;
		_name_="T";
		_nused_=.;
		a=a/aVar**(1/2);
		%do i=1 %to &xn;
		coef_&&var&i=coef_&&var&i/coef_&&var&i..Var**(1/2);
		%end;
	run;
	data RegCoeff;
		set RegCoeff RegCoeff_T;	
		rename %do i=1 %to &xn; coef_&&var&i=&&var&i %end;	;
	run;
	%end;

	*report estimation results;
	proc sort data=RegCoeff;
		by &byVars _name_;
	run;
	proc print data=RegCoeff; run;

*also generate a dataset storing R2;
	proc reg data=&indst outest=R2_tp(keep=&byVars _RSQ_ rename=(_RSQ_=R2)) RSQUARE noprint;
		model &depVar = &IndepVars;
		by &byVars;
	quit;
	data t1;
		length _name_ $10;
		set R2_tp;
		_name_="Est";
	run;
	data t2;
		length _name_ $10;
		set R2_tp;
		_name_="T";
		R2=.;
	run;
	data R2_tp_reform; set t1 t2; run;
	proc sort data=R2_tp_reform; by  &byVars _name_; run;

	proc sort data= regcoeff_t; by &byVars ; run;
	proc sort data= _num_firm; by &byVars ; run;

	data _sharpe_nw;
		merge  regcoeff_t _num_firm;
		by &byVars ;
		*sharpe_nw= a/sqrt(_freq_);
		sharpe_nw= (a/sqrt(_freq_)) * sqrt(12);
		keep &byVars sharpe_nw;
	run;

	data &outset;
		merge regcoeff R2_tp_reform _num_firm _sharpe _sharpe_nw;
		by &byVars;
		if compress(_name_) = "T" then do;
		nfirm_mean = .;
		nfirm_min= .;
		sharpe= .;
		sharpe_nw= . ; 
		drop _type_ _freq_;
		end;
	run;
	proc sql;
		drop table _num_firm, _sharpe, t1, t2, regcoeff, regcoeff_t, r2_tp, r2_tp_reform, gmmest1, _sharpe_nw; 
	quit;
%mend;
*********************************************************************************************************;
