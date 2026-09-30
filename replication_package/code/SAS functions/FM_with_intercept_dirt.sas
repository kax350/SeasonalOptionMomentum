	
/* FM macro */
 %MACRO NWORDS (INVAR);
%local N W;
 
/* %let invar = %sysfunc(compbl(&invar)); */
 
%let N = 0;
%let W = 1;
 
%do %while (%nrquote(%scan(&invar,&W,%str( ))) ^= %str());
  %let N = %eval(&N+1);
  %let W = %eval(&W+1);
%end;
 
&N
 
%MEND NWORDS;


 %MACRO FM_dirty (INSET=,OUTSET=,DATEVAR=,DEPVAR=, INDVARS=,LAG=);
      proc sort data=&inset out=_temp;
        by &datevar;
      run;


	
	proc reg data= _temp  outest= _results rsquare ADJRSQ noprint;
		by &datevar;
		model &depvar=&indvars; 
	;
	quit;
	run;

    /*create a dummy dataset for appending the results of FM regressions*/
      data &outset; set _null_;
        format parameter $32. estimate best8. stderr d8. tvalue 7.2 probt pvalue6.4
         df best12. stderr_uncorr best12. tvalue_uncorr 7.2  probt_uncorr pvalue6.4;
         label stderr='Corrected standard error of FM coefficient';
         label tvalue='Corrected t-stat of FM coefficient';
         label probt='Corrected p-value of FM coefficient';
         label stderr_uncorr='Uncorrected standard error of FM coefficient';
         label tvalue_uncorr='Uncorrected t-stat of FM coefficient';
         label probt_uncorr='Uncorrected p-value of FM coefficient';
         label df='Degrees of Freedom';
       run;
      %do k=1 %to %nwords(&indvars);
        %let var=%scan(&indvars,&k,%str(' '));
 
      /*1. Compute Fama-MacBeth coefficients as time-series means*/
       ods listing close;
        proc means data=_results n std t probt;
          var &var;
          ods output summary=_uncorr;
        run;
 
        /*2. Perform Newey-West adjustment using Bart kernel in PROC MODEL*/
        proc model data=_results;
          instruments const;
          &var=const;
          fit &var/gmm kernel=(bart,%eval(&lag+1),0);
          ods output parameterestimates=_params;
        quit;
        ods listing;
 
      /*3. put the results together*/
        data _params (drop=&var._n);
          merge _params
                _uncorr (rename=(&var._stddev=stderr_uncorr
                                 &var._t=tvalue_uncorr
                                 &var._probt=probt_uncorr)
                         );
                 stderr_uncorr=stderr_uncorr/&var._n**0.5;
          parameter="&var";
          drop esttype;
         run;
 
         proc append base=&outset data=_params force; run;
  %end;
 

	*add intercept;
   %let var=intercept;
 
      /*1. Compute Fama-MacBeth coefficients as time-series means*/
       ods listing close;
        proc means data=_results n std t probt;
          var &var;
          ods output summary=_uncorr;
        run;
 
        /*2. Perform Newey-West adjustment using Bart kernel in PROC MODEL*/
        proc model data=_results;
          instruments const;
          &var=const;
          fit &var/gmm kernel=(bart,%eval(&lag+1),0);
          ods output parameterestimates=_params;
        quit;
        ods listing;
 
      /*3. put the results together*/
        data _params (drop=&var._n);
          merge _params
                _uncorr (rename=(&var._stddev=stderr_uncorr
                                 &var._t=tvalue_uncorr
                                 &var._probt=probt_uncorr)
                         );
                 stderr_uncorr=stderr_uncorr/&var._n**0.5;
          parameter="&var";
          drop esttype;
         run;
 
         proc append base=&outset data=_params force; run;


	*add r-sq to the table ;
ods listing close;
        proc means data=_results mean;
          *var _adjrsq_;
			var _rsq_;
          ods output summary=_rsq ;
        run;
	data &outset; merge &outset _rsq (rename=(_rsq__mean= rsq)); run;

		*add adjusted r-sq to the table ;
ods listing close;
        proc means data=_results mean;
          var _adjrsq_;
          ods output summary=_adjrsq ;
        run;
	data &outset; merge &outset _adjrsq (rename=(_adjrsq__mean= adjrsq)); run;


    *house cleaning; 
   /*  proc sql; drop table _temp, _params, _results, _uncorr, _rsq, _adjrsq ;quit; */
%MEND;
