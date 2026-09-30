

*--------------------------------------------------------------------;

%let root=D:\vixseas;

libname here "&root\Data Raw";

*--------------------------------------------------------------------;


data VIX_ret; set here.analyst_rv; run;
data VIX_ret_0_oi_bid; set here.analyst_rv_0_oi_bid; run;


/*************************************************
****************Seasonality: 12 months ***********
**************************************************/
proc sql;
  create table VIX_ret_lag as
  select a.*, b.date as date_lag, b.month_index as month_past, 
         b.VSR_corridor_analyst as VSR_corridor_analyst_lag, b.VSR_corridor_Noanalyst as VSR_corridor_Noanalyst_lag,
         b.VSR_Corridor_analyst_Low as VSR_Corridor_analyst_Low_lag, b.VSR_Corridor_analyst_High as VSR_Corridor_analyst_High_lag
	from VIX_ret a left join VIX_ret_0_oi_bid b
	  on a.secid=b.secid and a.month_index-12<=b.month_index<a.month_index; quit;
data VIX_ret_lag; retain secid date date_lag; set VIX_ret_lag;  run;
proc sort data=VIX_ret_lag nodupkey; by secid date date_lag; run;

/* Seasonal lags */
data VIX_ret_lag_season; set VIX_ret_lag; month_lag=month_index-month_past; if mod(month_lag,3)=0; run;
proc means data=VIX_ret_lag_season NOPRINT nway; class secid date;
var VSR_corridor_analyst_lag VSR_corridor_Noanalyst_lag VSR_Corridor_analyst_Low_lag VSR_Corridor_analyst_High_lag;
output out=season_12  mean=season_analyst_12 season_Noanalyst_12 season_analyst_Low_12 season_analyst_High_12; run;
data season_12; set season_12; if _freq_>=12/3*2/3; run;
proc sql;
  create table VIX_ret as
 select a.*, b.season_analyst_12, b.season_Noanalyst_12,b.season_analyst_Low_12,b.season_analyst_High_12
	from VIX_ret a left join season_12 b
	  on a.secid=b.secid and a.date=b.date; quit;

/* Non-seasonal lags */
data VIX_ret_lag_nonseason; set VIX_ret_lag; month_lag=month_index-month_past; if mod(month_lag,3) ne 0; run;
proc means data=VIX_ret_lag_nonseason NOPRINT nway;
class secid date; var VSR_corridor_analyst_lag VSR_corridor_Noanalyst_lag VSR_Corridor_analyst_Low_lag VSR_Corridor_analyst_High_lag;
output out=nonseason_12  mean=nonseason_analyst_12 nonseason_Noanalyst_12 nonseason_analyst_Low_12 nonseason_analyst_High_12; run;
data nonseason_12;  set nonseason_12; if _freq_>=12*2/3* 2/3; run;
proc sql;
  create table VIX_ret as
 select a.*, b.nonseason_analyst_12, b.nonseason_Noanalyst_12,b.nonseason_analyst_Low_12,b.nonseason_analyst_High_12
	from VIX_ret a left join nonseason_12 b
	  on a.secid=b.secid and a.date=b.date; quit;
proc sort data=VIX_ret nodupkey; by secid date; run;


/*************************************************
****************Seasonality: 36 months*************
**************************************************/
proc sql;
  create table VIX_ret_lag as
  select a.*, b.date as date_lag, b.month_index as month_past, 
         b.VSR_corridor_analyst as VSR_corridor_analyst_lag, b.VSR_corridor_Noanalyst as VSR_corridor_Noanalyst_lag,
         b.VSR_Corridor_analyst_Low as VSR_Corridor_analyst_Low_lag, b.VSR_Corridor_analyst_High as VSR_Corridor_analyst_High_lag
	from VIX_ret a left join VIX_ret_0_oi_bid b
	  on a.secid=b.secid and a.month_index-36<=b.month_index<a.month_index; quit;
data VIX_ret_lag; retain secid date date_lag; set VIX_ret_lag;  run;
proc sort data=VIX_ret_lag nodupkey; by secid date date_lag; run;

/* Seasonal lags */
data VIX_ret_lag_season; set VIX_ret_lag; month_lag=month_index-month_past; if mod(month_lag,3)=0; run;
proc means data=VIX_ret_lag_season NOPRINT nway;
class secid date; var VSR_corridor_analyst_lag VSR_corridor_Noanalyst_lag VSR_Corridor_analyst_Low_lag VSR_Corridor_analyst_High_lag;
output out=season_36  mean= season_analyst_36 season_Noanalyst_36 season_analyst_Low_36 season_analyst_High_36; run;
data season_36; set season_36; if _freq_>=36/3*2/3; run;
proc sql;
  create table VIX_ret as
 select a.*, b.season_analyst_36, b.season_Noanalyst_36,b.season_analyst_Low_36,b.season_analyst_High_36
	from VIX_ret a left join season_36 b
	  on a.secid=b.secid and a.date=b.date; quit;

/* Non-seasonal lags */
data VIX_ret_lag_nonseason; set VIX_ret_lag; month_lag=month_index-month_past; if mod(month_lag,3) ne 0; run;
proc means data=VIX_ret_lag_nonseason NOPRINT nway;
class secid date; var VSR_corridor_analyst_lag VSR_corridor_Noanalyst_lag VSR_Corridor_analyst_Low_lag VSR_Corridor_analyst_High_lag;
output out=nonseason_36 mean=nonseason_analyst_36 nonseason_Noanalyst_36 nonseason_analyst_Low_36 nonseason_analyst_High_36; run;
data nonseason_36; set nonseason_36;if _freq_>=36*2/3*2/3; run;
proc sql;
  create table VIX_ret as
 select a.*, b.nonseason_analyst_36, b.nonseason_Noanalyst_36,b.nonseason_analyst_Low_36,b.nonseason_analyst_High_36
	from VIX_ret a left join nonseason_36 b
	  on a.secid=b.secid and a.date=b.date; quit;
proc sort data=VIX_ret nodupkey; by secid date; run;


/*************************************************
********** Output to STATA to generate Table 15 **
**************************************************/
PROC EXPORT DATA=VIX_ret outfile='yourpath\predict_vixret_analyst.csv' dbms=csv replace;run;


/*Copy paste the code below to STATA to generate Table 15:
 
import delimited YourPath\predict_vixret_analyst.csv, clear 

sort secid  month_index
tsset secid month_index

eststo clear
eststo model1: quietly asreg dynamic_vix_return_corridor season_analyst_low_12 nonseason_analyst_low_12, fmb newey(3)
eststo model2: quietly asreg dynamic_vix_return_corridor season_analyst_high_12 nonseason_analyst_high_12, fmb newey(3)
eststo model3: quietly asreg dynamic_vix_return_corridor season_noanalyst_12 nonseason_noanalyst_12, fmb newey(3)
eststo model4: quietly asreg dynamic_vix_return_corridor season_analyst_low_12 nonseason_analyst_low_12  season_analyst_high_12 nonseason_analyst_high_12  season_noanalyst_12 nonseason_noanalyst_12, fmb newey(3)
eststo model5: quietly asreg dynamic_vix_return_corridor season_analyst_low_12 nonseason_analyst_low_12  season_analyst_high_12 nonseason_analyst_high_12  season_noanalyst_12 nonseason_noanalyst_12 flag_earning, fmb newey(3)
esttab model1 model2 model3 model4 model5 using Table15_PanelA.tex,  b(3) nostar r2(3)   replace

eststo clear
eststo model1: quietly asreg dynamic_vix_return_corridor season_analyst_low_36 nonseason_analyst_low_36, fmb newey(3)
eststo model2: quietly asreg dynamic_vix_return_corridor season_analyst_high_36 nonseason_analyst_high_36, fmb newey(3)
eststo model3: quietly asreg dynamic_vix_return_corridor season_noanalyst_36 nonseason_noanalyst_36, fmb newey(3)
eststo model4: quietly asreg dynamic_vix_return_corridor season_analyst_low_36 nonseason_analyst_low_36  season_analyst_high_36 nonseason_analyst_high_36  season_noanalyst_36 nonseason_noanalyst_36, fmb newey(3)
eststo model5: quietly asreg dynamic_vix_return_corridor season_analyst_low_36 nonseason_analyst_low_36  season_analyst_high_36 nonseason_analyst_high_36  season_noanalyst_36 nonseason_noanalyst_36 flag_earning, fmb newey(3)
esttab  model1 model2 model3 model4 model5 using Table15_PanelB.tex,  b(3) nostar r2(3)   replace
*/ 


