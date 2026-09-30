

%macro HL_CS (input, output, date, id, sortvar, depvar, port_weight, ngroups);

	proc sort data= &input;
		by &date;
	run;

	*H-L portfolio spread ;
	proc rank data=&input (where=(missing(&sortvar)=0)) out=_s1  ties=low groups=&ngroups;
    	by &date;
    	var &sortvar;
    	ranks &sortvar._r;
	run;
	data _s2;
		set _s1;
		&sortvar._r = &sortvar._r +1;
		if &sortvar._r ne . ;
	run;

/*
	*alternative way ;
	proc univariate data=&input noprint;
   		var &sortvar;
   		by &date;
   		output out= _s1
          n=nfirms
          pctlpts=10 to 90 by 10
          pctlpre=P;
	run; quit;

	proc sql;
   		create table _s2 as
   		select a.*,
        	  case when   a.&sortvar ne . and     a.&sortvar < b.P20 then 1
              when b.P20<=a.&sortvar<b.P40 then 2
              when b.P40<=a.&sortvar<b.P60 then 3
              when b.P60<=a.&sortvar<b.P80 then 4
              when b.P80<=a.&sortvar and a.&sortvar ne . then 5
              end as &sortvar._r
	 	from &input as a, _s1 as b
		where a.&date=b.&date;
	quit;
*/

	proc sql;
		create table _s3
		as select &date, &sortvar._r, mean(&depvar) as ew_ret,
			sum(&depvar * &port_weight) / sum(&port_weight) as vw_ret,
			count(&depvar) as num_firm
		from _s2 
		group by &date, &sortvar._r;
	quit;

	proc sort data= _s3; by &date; run;
	proc transpose data= _s3 out= _s4;
		by &date;
		id &sortvar._r;
		var ew_ret vw_ret num_firm;
	run;

	data _s5 (rename= (_name_= type));
		set _s4;
		if compress(_name_)= "num_firm" then _H_L= mean(_&ngroups. , _1);
		else _H_L= _&ngroups. - _1;
	run;

	proc sort data= _s5; by &date; run;
	proc transpose data= _s5 out= _s6;
		by &date;
		id type;
	run;

	data &output (rename= (_name_ = group));
		set _s6;
	run;

	proc datasets library= work;
		delete _: ; 
	run; quit;

%mend;
