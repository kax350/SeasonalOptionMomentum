**********************************************************************************************
* Macro: FamaMacBeth regression estimation and output a dataset "FMCoeff" 
  containing regression coeffs and their t-stats based on NW std err
  also average CS R2 is stored in dataset (_AvgCS_R2);
**********************************************************************************************;
%macro FamaMacBethCSR(indst,depVar,IndepVars,tvar,bygroupvar,NWlags);

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
data FMCoeff;
	set _null_;
run;
data FMCoeff_T;
	set _null_;
run;
data para;
	set _null_;
run;

data tt;
	set &indst;
	%do i=1 %to &xn; if missing(&&var&i)=0; %end;
	if missing(&depVar)=0;
run;
%if &bygroupvar= %then %do;
    data tt;
        set tt;
    	xbyvar = 1;
    run;
    %let bygroupvar = xbyvar;
%end;
proc sort data=tt; by &bygroupvar &tvar; run;

proc reg data=tt outest=para noprint RSQUARE;
model  &depVar = %do i=1 %to &xn; &&var&i %end; ;
by &bygroupvar &tvar;
run;
* compute average R2;
proc means data=para noprint;
var _RSQ_;
by &bygroupvar;
output out=_AvgCS_R2(drop=_type_ _freq_) mean=_AvgCS_R2;
run;

proc model data=para(where=(_type_="PARMS")) noprint ;
	  by &bygroupvar;
	  endogenous intercept %do i=1 %to &xn; &&var&i %end;;
      parms int 0 %do i=1 %to &xn; coef_&&var&i 0 %end; ;    

	  * The moment conditions ;
	  eq.h1 = int - intercept;
	  %do i=1 %to &xn; 
	  eq.h%eval(1+&i) = coef_&&var&i - &&var&i;
      %end;

	  fit h1-h%eval(&xn+1) / gmm kernel=(bart,%eval(&NWlags+1),0) vardef=n outest=gmmEst1 COVOUT;
      instruments / intonly;
quit;

data FMCoeff;
	set gmmEst1(keep=&bygroupvar _name_ _nused_ int %do i=1 %to &xn; coef_&&var&i %end; where=(_name_=''));
	_name_="1_Est";
run;
data FMCoeff_T(keep=&bygroupvar _name_ _nused_ int %do i=1 %to &xn; coef_&&var&i %end;);
	length _name_ $32;
	merge FMCoeff 
		 gmmEst1(keep=&bygroupvar _name_ int where=(_name_="int") rename=(int=intVar))
		 %do i=1 %to &xn;
		 gmmEst1(keep=&bygroupvar _name_ coef_&&var&i where=(_name_="coef_&&var&i") rename=(coef_&&var&i=coef_&&var&i..Var))
		 %end;
		 ;
	by &bygroupvar;
	_name_="2_T";
	_nused_=.;
	int=int/intVar**(1/2);
	%do i=1 %to &xn;
	coef_&&var&i=coef_&&var&i/coef_&&var&i..Var**(1/2);
	%end;
run;
data FMCoeff;
	set FMCoeff FMCoeff_T;
	rename %do i=1 %to &xn; coef_&&var&i=&&var&i %end;;
run;
proc sort data=FMCoeff;
by &bygroupvar _name_;
run;

* attach average CS R2 to FMCoeff;
data FMCoeff_R2; 
	set _AvgCS_R2;
	_name_='1_Est';
	rename _AvgCS_R2=R2;
run;
data FMCoeff;
	merge FMCoeff FMCoeff_R2;
	by &bygroupvar _name_;
run;

proc print data=FMCoeff; run;

* average CS R2 is also stored in dataset (_AvgCS_R2);
proc print data=_AvgCS_R2; run;
%mend;
