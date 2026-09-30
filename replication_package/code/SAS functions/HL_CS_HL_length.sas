

%macro HL_CS_length (input, output, date, id, sortvar, depvar, port_weight, ngroups, HL_length);

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

	%if  &HL_length = 1 %then %do;
	data _s5 (rename= (_name_= type));
		set _s4;
		if compress(_name_)= "num_firm" then do;
			_H_L= mean(_&ngroups. , _1);
			_H= _&ngroups;
			_L= _1;
		end;
		else do;
			_H_L= _&ngroups. - _1;
			_H= _&ngroups;
			_L= _1;
		end;
	run;
	%end;

	%if  &HL_length = 2 %then %do;
	%let n1= %eval(%sysfunc(sum(&ngroups. , -1)));
	data _s5 (rename= (_name_= type));
		set _s4;	
		if compress(_name_)= "num_firm" then do;
			_H_L= mean(_&ngroups. ,_&n1. , _1, _2);
			_H= mean(_&ngroups. ,_&n1.);
			_L= mean(_1,_2);
		end;
		else do;
			_H_L= mean(_&ngroups. , _&n1.) - mean(_1 , _2);
			_H= mean(_&ngroups. , _&n1.) ;
			_L= mean(_1 , _2);
		end;
	run;
	%end;

	%if  &HL_length = 3 %then %do;
	%let n1= %eval(%sysfunc(sum(&ngroups. , -1)));
	%let n2= %eval(%sysfunc(sum(&ngroups. , -2)));
	data _s5 (rename= (_name_= type));
		set _s4;	
		if compress(_name_)= "num_firm" then do;
			_H_L= mean(_&ngroups. ,_&n1. ,_&n2., _1, _2, _3);
			_H= mean(_&ngroups. ,_&n1. ,_&n2.);
			_L=mean(_1,_2,_3);
		end;
		else do;
			_H_L= mean(_&ngroups. , _&n1. , _&n2.) - mean(_1 , _2 , _3);
			_H=mean(_&ngroups. , _&n1. , _&n2.);
			_L=mean(_1 , _2 , _3);
		end;
	run;
	%end;

	%if  &HL_length = 4 %then %do;
	%let n1= %eval(%sysfunc(sum(&ngroups. , -1)));
	%let n2= %eval(%sysfunc(sum(&ngroups. , -2)));
	%let n3= %eval(%sysfunc(sum(&ngroups. , -3)));
	data _s5 (rename= (_name_= type));
		set _s4;	
		if compress(_name_)= "num_firm" then do;
			_H_L= mean(_&ngroups. ,_&n1. ,_&n2., _&n3., _1, _2, _3, _4);
			_H=mean(_&ngroups. ,_&n1. ,_&n2., _&n3.);
			_L=mean(_1,_2,_3,_4);
		end;
		else do;
			_H_L= mean(_&ngroups. , _&n1. , _&n2. , _&n3.) - mean(_1 , _2 , _3 , _4);
			_H=mean(_&ngroups. , _&n1. , _&n2. , _&n3.) ;
			_L=mean(_1 , _2 , _3 , _4);
		end;
	run;
	%end;

	
	%if  &HL_length = 6 %then %do;
	%let n1= %eval(%sysfunc(sum(&ngroups. , -1)));
	%let n2= %eval(%sysfunc(sum(&ngroups. , -2)));
	%let n3= %eval(%sysfunc(sum(&ngroups. , -3)));
	%let n4= %eval(%sysfunc(sum(&ngroups. , -4)));
	%let n5= %eval(%sysfunc(sum(&ngroups. , -5)));
	data _s5 (rename= (_name_= type));
		set _s4;	
		if compress(_name_)= "num_firm" then do;
			_H_L= mean(_&ngroups. ,_&n1. ,_&n2., _&n3., _&n4. ,_&n5., _1, _2, _3, _4, _5, _6);
			_H=mean(_&ngroups. ,_&n1. ,_&n2., _&n3., _&n4. ,_&n5.);
			_L=mean(_1,_2,_3,_4, _5, _6);
		end;
		else do;
			_H_L= mean(_&ngroups. , _&n1. , _&n2. , _&n3., _&n4. ,_&n5.) - mean(_1 , _2 , _3 , _4, _5, _6);
			_H=mean(_&ngroups. , _&n1. , _&n2. , _&n3., _&n4. ,_&n5.) ;
			_L=mean(_1 , _2 , _3 , _4, _5, _6);
		end;
	run;
	%end;


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
