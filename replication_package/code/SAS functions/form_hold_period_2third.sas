
*specify holding period and formation period;
%macro form_hold_period_2third (input, output, date, id, form_var, hold_var, form_minlag, 
	form_maxlag, hold_period, form_ret_type, hold_ret_type);
	
	%if &date= ymd %then %do;
	data _s1;
		set &input ;
		date_var=input(put(&date,best8.),yymmdd8.); 
		format date_var date9.;
	run;
	%end;
	%if &date ne ymd %then %do;
	data _s1;
		set &input ;
		date_var= &date;
		format date_var date9.;
	run;
	%end;

	* forming period ;

	%if &form_ret_type= CUM %then %do;
	proc sql;
		create table _s2
		as select a.&id. , a.date_var ,b.&form_var. as var_lag, b.date_var as date_lag,
			intck("month", b.date_var, a.date_var) as num_lag, b.rfret
		from _s1 as a , _s1 as b
		where a.&id. = b.&id. and &form_minlag. <= intck("month", b.date_var, a.date_var) <= &form_maxlag. ;
	quit;
		proc sql;
			create table _s3
			as select &id, date_var , (exp(sum(log(var_lag + rfret +1))) - 1 ) as fvar
			from _s2
			group by &id , date_var
			having n(var_lag) >= ((&form_maxlag. - &form_minlag. + 1) * 2/3);
		quit;
	%end;


	%if &form_ret_type= AVG %then %do;
	proc sql;
		create table _s2
		as select a.&id. , a.date_var ,b.&form_var. as var_lag, b.date_var as date_lag,
			intck("month", b.date_var, a.date_var) as num_lag
		from _s1 as a , _s1 as b
		where a.&id. = b.&id. and &form_minlag. <= intck("month", b.date_var, a.date_var) <= &form_maxlag. ;
	quit;
		proc sql;
			create table _s3
			as select &id, date_var , mean(var_lag) as fvar
			from _s2
			group by &id , date_var
			having n(var_lag) >= ((&form_maxlag. - &form_minlag. + 1) * 2/3);
		quit;
	%end;
	




	*holding period ;
	%if &hold_ret_type= CUM %then %do;
	proc sql;
		create table _s4
		as select a.&id. , a.date_var ,  b.&hold_var. as var_lead, b.date_var as date_lead,
			intck("month", a.date_var, b.date_var) + 1 as num_months, b.rfret
		from _s1 as a , _s1 as b
		where a.&id. = b.&id. and 0 <= intck("month", a.date_var, b.date_var) <= &hold_period. -1 ;
	quit;
		proc sql;
			create table _s5
			as select &id, date_var , (exp(sum(log(var_lead + rfret + 1))) - 1) as hvar
			from _s4
			group by &id , date_var
			having n(var_lead) = &hold_period ;
		quit;
	%end;

	%if &hold_ret_type= AVG %then %do;
	proc sql;
		create table _s4
		as select a.&id. , a.date_var ,  b.&hold_var. as var_lead, b.date_var as date_lead,
			intck("month", a.date_var, b.date_var) + 1 as num_months
		from _s1 as a , _s1 as b
		where a.&id. = b.&id. and 0 <= intck("month", a.date_var, b.date_var) <= &hold_period. -1 ;
	quit;
		proc sql;
			create table _s5
			as select &id, date_var , mean(var_lead) as hvar
			from _s4
			group by &id , date_var
			having n(var_lead) = &hold_period ;
		quit;
	%end;

	%if &hold_ret_type= JEGADEESH %then %do;
	proc sql;
		create table _s4
		as select a.&id. , a.date_var ,  b.&hold_var. as var_lead, b.date_var as date_lead,
			intck("month", a.date_var, b.date_var) + 1 as num_months, b.rfret
		from _s1 as a , _s1 as b
		where a.&id. = b.&id. and 0 <= intck("month", a.date_var, b.date_var) <= &hold_period. -1 ;
	quit;
		proc sort data= _s4; by &id date_var; run;
		proc transpose data= _s4 out= _s5;
			by &id date_var;
			var var_lead;
		run;
		proc sort data= _s5 nodupkey; by  &id date_var; run;
	%end;

	proc sql;
		create table _s6
		as select *
		from _s1 as a, _s3 as b	
		where  a.&id. = b.&id. and a.date_var = b.date_var ;
	quit;

	proc sql;
		create table &output
		as select *
		from _s6 as a left join _s5 as b
		on a.&id. = b.&id. and a.date_var = b.date_var ;
	quit;

	proc datasets library= work;
		delete _: ; 
	run; quit;

%mend;
