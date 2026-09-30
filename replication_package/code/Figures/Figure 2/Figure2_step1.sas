
*--------------------------------------------------------------------;

%let root=D:\vixseas;

libname here "&root\Data Raw";

*include all sas macros in the folder;
%include "&root\Code\SAS functions\*.sas";

*--------------------------------------------------------------------;


*** Clear the work folder;
proc delete data=work._all_; run;

proc sql;
	create table simpson_return as
	select secid, exdate_trade, date, Static_VIX_Return, Dynamic_VIX_Return, VSR, log(1+VSR) as logGrossVSR,
		   VIX_Prc, Monthly_RV, log(VIX_Prc) as logVIX_Prc, log(Monthly_RV) as logMonthly_RV,
		   BS_VIX_Return,
		   (1+VSR_Corridor)*VIX_Prc as Monthly_RV_cor,
		   log(calculated Monthly_RV_cor) as logMonthly_RV_cor,
		   log(1+VSR_Corridor) as logCorridorVSR,
		   Dynamic_VIX_Return_Corridor as VIX_Return_MFcor
	from here.simpson_return
	where shrcd in (10,11);

	create table simpson_return_0_openinterest as
	select secid, exdate_trade, date, Static_VIX_Return, Dynamic_VIX_Return, VSR, log(1+VSR) as logGrossVSR,
		   VIX_Prc, Monthly_RV, log(VIX_Prc) as logVIX_Prc, log(Monthly_RV) as logMonthly_RV,
		   BS_VIX_Return,
		   (1+VSR_Corridor)*VIX_Prc as Monthly_RV_cor,
		   log(calculated Monthly_RV_cor) as logMonthly_RV_cor,
		   log(1+VSR_Corridor) as logCorridorVSR,
		   Dynamic_VIX_Return_Corridor as VIX_Return_MFcor		   
	from here.simpson_return_0_oi_bid
	where shrcd in (10,11);
quit;
proc sort data=simpson_return nodupkey; by secid exdate_trade; run; * 0 duplicate;
proc sort data=simpson_return_0_openinterest nodupkey; by secid exdate_trade; run; * 0 duplicate;

proc sql;
	create table firm_num as
	select exdate_trade, n(Static_VIX_Return) as firm_num
	from simpson_return
	group by exdate_trade;
quit;
proc univariate data=firm_num; run;

%macro ForSingleMonthReg;
proc sql;
	%do m= 1 %to 60;
	create table reg_m_&m as
	select &m as MHorizon, a.*, b.VIX_Prc as lag_VIX_Prc_a, b.Monthly_RV as lag_Monthly_RV_a, b.logVIX_Prc as lag_logVIX_Prc_a, b.logMonthly_RV as lag_logMonthly_RV_a, 
								b.logGrossVSR as lag_logGrossVSR_a, b.Static_VIX_Return as lag_Static_VIX_Return_a, b.Dynamic_VIX_Return as lag_Dynamic_VIX_Return_a,
								b.BS_VIX_Return as lag_BS_VIX_Return_a,
								b.Monthly_RV_cor as lag_Monthly_RV_cor_a,
								b.logMonthly_RV_cor as lag_logMonthly_RV_cor_a,
								b.logCorridorVSR as lag_logCorridorVSR_a,
								b.VIX_Return_MFcor as lag_VIX_Return_MFcor_a
	from simpson_return as a, simpson_return_0_openinterest as b
	where a.secid=b.secid and intnx('month',a.exdate_trade,0,'e')=intnx('month',b.exdate_trade,&m,'e');
	%end;
quit;
data reg_m_all; set reg_m_1-reg_m_60; run;
proc sort data=reg_m_all; by MHorizon date; run;
%mend;
%ForSingleMonthReg;

%macro runSingleMonthReg(var);
***
* run FamaMacBethCSR of one variable on its own in a previous single month and output the slope estimate and se for all lags to Matlab for plotting
***;

%FamaMacBethCSR(reg_m_all,&var,lag_&var._a,date,MHorizon);

proc transpose data=FMCoeff out=coef_lag_&var prefix=lag_&var._;
by MHorizon;
var lag_&var._a;
id _name_;
run;

proc sql;
	create table coef_lag_&var._1 as
	select MHorizon, lag_&var._1_Est as Est, lag_&var._1_Est/lag_&var._2_T as SE
	from coef_lag_&var;
quit;
proc export data=coef_lag_&var._1 outfile="&root\Seasonality plot output\coef_lag_&var..csv" dbms=csv REPLACE;
run;
%mend;
%runSingleMonthReg(logMonthly_RV);
%runSingleMonthReg(logGrossVSR);
%runSingleMonthReg(Static_VIX_Return);
%runSingleMonthReg(Dynamic_VIX_Return);
%runSingleMonthReg(BS_VIX_Return);

%runSingleMonthReg(logVIX_Prc);
%runSingleMonthReg(logMonthly_RV_cor);
%runSingleMonthReg(logCorridorVSR);
%runSingleMonthReg(VIX_Return_MFcor);

%runSingleMonthReg(Monthly_RV_cor);
