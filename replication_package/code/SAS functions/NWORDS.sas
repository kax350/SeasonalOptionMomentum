
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
