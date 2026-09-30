
*--------------------------------------------------------------------;

%let root=D:\vixseas;

libname seas "&root\seas";

*include all sas macros in the folder;
%include "&root\Code\SAS functions\*.sas";

*--------------------------------------------------------------------;




proc delete data= work._all_; run;
dm 'odsresults; clear';


********************************************** 3,6,9,12;

data CS1;
	set seas.CS_DVIX_MF_1_12_3;  
	if group= "_H_L";
run;


* factor adjustment;
data CS2;
	set CS1;
	if month(date_var) = 1 then m1= 1; else m1=0;
	if month(date_var) = 2 then m2= 1; else m2=0;
	if month(date_var) = 3 then m3= 1; else m3=0;
	if month(date_var) = 4 then m4= 1; else m4=0;
	if month(date_var) = 5 then m5= 1; else m5=0;
	if month(date_var) = 6 then m6= 1; else m6=0;
	if month(date_var) = 7 then m7= 1; else m7=0;
	if month(date_var) = 8 then m8= 1; else m8=0;
	if month(date_var) = 9 then m9= 1; else m9=0;
	if month(date_var) = 10 then m10= 1; else m10=0;
	if month(date_var) = 11 then m11= 1; else m11=0;
	if month(date_var) = 12 then m12= 1; else m12=0;
run;


%GMM_noint(indst= CS2, outset=CS3_all, 
	depVar= ew_ret,IndepVars= m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12 ,byVars=group,lags=3); 

proc transpose data= cs3_all out=cs3_all1; var m1--m12; id _name_; run; 
data plot3; set cs3_all1; se= est/t; HB= est + 1.96 *se; LB= est - 1.96 *se; m=input(compress(_name_,"m"),8.); run;



proc sort data= plot3; by m; run;

data plot3;
	set plot3;
	if m=1 then month= "Jan.";
   if m=2 then month= "Feb.";
   if m=3 then month= "Mar.";
   if m=4 then month= "Apr.";
   if m=5 then month= "May.";
   if m=6 then month= "Jun.";
   if m=7 then month= "Jul.";
   if m=8 then month= "Aug.";
   if m=9 then month= "Sep.";
   if m=10 then month= "Oct.";
   if m=11 then month= "Nov.";
   if m=12 then month= "Dec.";
run;

* plot;
goptions reset=goptions;
data plot4;
   set plot3;
   drop HB LB Est;
   Dow=HB; output;
   Dow=LB; output;
   Dow=Est; output;
run;

* Define symbol characteristics ;
symbol1 interpol=hiloctj
        cv=vibg
        ci=black
        width=2;

axis1 order= ("Jan." "Feb." "Mar." "Apr." "May." "Jun." "Jul." "Aug." "Sep." "Oct."  "Nov." "Dec.")
      offset=(1,1)
      label=none value=(h=2)
      width=1 ;

axis2 color=black
      label=("")
	  order = (-.1 to .3 by .05) value=(h=2)
      offset=(1,1);

proc gplot data=plot4;
   plot dow*month / vref=0 haxis= axis1 vaxis= axis2 ;
run;
quit;








********************************************** 3,6,9,..,36;

data CS1;
	set seas.CS_DVIX_MF_1_36_3;  
	if group= "_H_L";
run;


* factor adjustment;
data CS2;
	set CS1;
	if month(date_var) = 1 then m1= 1; else m1=0;
	if month(date_var) = 2 then m2= 1; else m2=0;
	if month(date_var) = 3 then m3= 1; else m3=0;
	if month(date_var) = 4 then m4= 1; else m4=0;
	if month(date_var) = 5 then m5= 1; else m5=0;
	if month(date_var) = 6 then m6= 1; else m6=0;
	if month(date_var) = 7 then m7= 1; else m7=0;
	if month(date_var) = 8 then m8= 1; else m8=0;
	if month(date_var) = 9 then m9= 1; else m9=0;
	if month(date_var) = 10 then m10= 1; else m10=0;
	if month(date_var) = 11 then m11= 1; else m11=0;
	if month(date_var) = 12 then m12= 1; else m12=0;
run;


%GMM_noint(indst= CS2, outset=CS3_all, 
	depVar= ew_ret,IndepVars= m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12 ,byVars=group,lags=3); 

proc transpose data= cs3_all out=cs3_all1; var m1--m12; id _name_; run; 
data plot7; set cs3_all1; se= est/t; HB= est + 1.96 *se; LB= est - 1.96 *se; m=input(compress(_name_,"m"),8.); run;



proc sort data= plot7; by m; run;

data plot7;
	set plot7;
	if m=1 then month= "Jan.";
   if m=2 then month= "Feb.";
   if m=3 then month= "Mar.";
   if m=4 then month= "Apr.";
   if m=5 then month= "May.";
   if m=6 then month= "Jun.";
   if m=7 then month= "Jul.";
   if m=8 then month= "Aug.";
   if m=9 then month= "Sep.";
   if m=10 then month= "Oct.";
   if m=11 then month= "Nov.";
   if m=12 then month= "Dec.";
run;

data plot8;
   set plot7;
   drop HB LB Est;
   Dow=HB; output;
   Dow=LB; output;
   Dow=Est; output;
run;

* Define symbol characteristics ;
symbol1 interpol=hiloctj
        cv=vibg
        ci=black
        width=2;

axis1 order= ("Jan." "Feb." "Mar." "Apr." "May." "Jun." "Jul." "Aug." "Sep." "Oct."  "Nov." "Dec.")
      offset=(1,1)
      label=none value=(h=2)
      width=1;

axis2 color=black
      label=("")
	  order = (-.1 to .3 by .05) value=(h=2)
      offset=(1,1);

proc gplot data=plot8;
   plot dow*month / vref=0 haxis= axis1 vaxis= axis2;
run;
quit;


