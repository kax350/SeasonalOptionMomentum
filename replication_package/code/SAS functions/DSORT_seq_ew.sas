

%macro DSORT_seq_ew (input, output, date, id, sortvar1, sortvar2, depvar, port_weight, ngroups1, ngroups2);

	proc sort data= &input;
		by &date;
	run;

	*H-L portfolio spread ;
	proc rank data=&input (where=(missing(&sortvar1)=0)) out=_s1  ties=low groups=&ngroups1;
    	by &date;
    	var &sortvar1;
    	ranks &sortvar1._r;
	run;
	data _s2;
		set _s1;
		&sortvar1._r = &sortvar1._r +1;
		if &sortvar1._r ne . ;
	run;

	*whithin each group sort the second variable ;
		proc sort data= _s2;	by &date &sortvar1._r; run;
		proc rank data=_s2 (where=(missing(&sortvar2)=0)) out=_s3  ties=low groups=&ngroups2;
    	by &date &sortvar1._r;
    	var &sortvar2;
    	ranks &sortvar2._r;
	run;
	data _s4;
		set _s3;
		&sortvar2._r = &sortvar2._r +1;
		if &sortvar2._r ne . ;
		group= cats("G_", &sortvar1._r, &sortvar2._r);
	run;


	proc sql;
		create table _s5
		as select &date, &sortvar1._r, &sortvar2._r, mean(&depvar) as ew_ret,
			sum(&depvar * &port_weight) / sum(&port_weight) as vw_ret,
			count(&depvar) as num_firm
		from _s4 
		group by &date, &sortvar1._r, &sortvar2._r;
	quit;

	proc sort data= _s5; by &date &sortvar1._r; run;
	proc transpose data= _s5 out= _s6;
		by &date &sortvar1._r;
		id &sortvar2._r;
		var ew_ret vw_ret num_firm;
	run;

	data _s7 (rename= (_name_= type));
		set _s6;
		if compress(_name_)= "num_firm" then _H_L= mean(_&ngroups2. , _1);
		else _H_L= _&ngroups2. - _1;
	run;



	proc sort data= _s7 (where= (type="ew_ret")) out= _s8; by &date; run;
	proc transpose data= _s8 out= _s9;
		by &date ;
		id &sortvar1._r;
	run;

	data _s10 (rename= (_name_= type));
		set _s9;
		if compress(_name_)= "num_firm" then _H_L= mean(_&ngroups1. , _1);
		else _H_L= _&ngroups1. - _1;
	run;

	proc sort data= _s10; by &date; run;
	proc transpose data= _s10 out= _s11;
		by &date;
		id type;
	run;

	data _s12 (rename= (_name_ = group));
		set _s11;
	run;

	proc sort data= _s7 (where= (type="num_firm")) 
		out= _nfirm1 (keep=&date &sortvar1._r type _H_L rename= _H_L= num_firm);  by &date; run;
	
	proc sql;
		create table &output
		as select a.*, b.num_firm
		from _s12 as a left join _nfirm1 as b
		on a.&date = b.&date and input(compress(a.group, "_"),8.) = b.&sortvar1._r;
	quit;

	proc datasets library= work;
		delete _: ; 
	run; quit;

%mend;
