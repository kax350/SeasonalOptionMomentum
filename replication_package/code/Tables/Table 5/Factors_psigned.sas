
*--------------------------------------------------------------------;

%let root=D:\vixseas;

libname here "&root\Data Raw";
libname data "&root\Data Out";

*include all sas macros in the folder;
%include "&root\Code\SAS functions\*.sas";

*--------------------------------------------------------------------;


proc delete data= work._all_; run;
dm 'odsresults; clear';



data factors;
	set data.factors_mf_0_bid;
run;
proc means data= factors; run;
proc sql;
	create table factors2
	as select *, mean(ew_atmiv_termspread) as m_ew_atmiv_termspread, mean(ew_idiovol) as m_ew_idiovol,
				mean(ew_iv_hv) as m_ew_iv_hv, mean(ew_mcap) as m_ew_mcap,
				mean(ew_slope) as m_ew_slope, mean(spx_vix) as m_spx_vix,
				mean(ew_vix) as m_ew_vix, mean(ew_mom) as m_ew_mom
	from factors;
quit;

data factors3;
	set factors2;
	if m_ew_atmiv_termspread < 0 then p_ew_atmiv_termspread= ew_atmiv_termspread * -1; else p_ew_atmiv_termspread= ew_atmiv_termspread;
	if m_ew_idiovol <0 then p_ew_idiovol= ew_idiovol * -1; else p_ew_idiovol= ew_idiovol;
	if m_ew_iv_hv <0 then p_ew_iv_hv= ew_iv_hv * -1; else p_ew_iv_hv= ew_iv_hv;
	if m_ew_mcap <0 then p_ew_mcap= ew_mcap * -1; else p_ew_mcap= ew_mcap;
	if m_ew_slope <0 then p_ew_slope= ew_slope * -1; else p_ew_slope= ew_slope;
	if m_ew_mom <0 then p_ew_mom= ew_mom * -1; else p_ew_mom= ew_mom;
	if m_ew_vix <0 then p_ew_vix= ew_vix * -1; else p_ew_vix= ew_vix;
	if m_spx_vix <0 then p_spx_vix= spx_vix * -1; else p_spx_vix= spx_vix;
	keep date_var p_: group; 
run;

proc means data= factors3; run;

data data.factors_psigned_mf_0_bid;
	set factors3;
run;
