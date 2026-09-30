*****************
Details:
*****************
Programming language: SAS, MATLAB, Stata
Additional software: Microsoft Excel
Note: Required SAS macros are in "SAS functions" folder.


*****************
Data:
*****************
Datasets needed:
- OptionMetrics
- CRSP
- IBES
- Compustat
- Fama-French risk-free rates

Main sample used to generate the tables and figures are:
- simpson_return.sas7bdat
- simpson_return_0_oi_bid.sas7bdat
* Run "Table1&2.sas" to generate "simpson_return.sas7bdat" and "simpson_return_0_oi_bid.sas7bdat"
* Any additional data required are noted in the instructions for each figure/table.


*****************
Figures:
*****************
Figure 1: 
- Step 1: Run "Figure1.m"

Figure 2: 
- Step 1: Run "Figure2_step1.sas"
- Step 2: Run "Figure2_plot.m"

Figure 3: 
- Step 1: Run "Table4_PanelA.sas" 
- Step 2: Run "Figure3.sas" 

Figure 4:
- Step 1: Run "Figure4.m"

Figure A.1: 
- Step 1: Run "makeplots.m"


*****************
Tables:
*****************
Table 1&2:
- Step1: Run "Table1&2.sas"

Table 3:
- Step 1: Run "Table3.sas"

Table 4:
- Step 1: Run "Table4_PanelA.sas"
- Step 2: Run "Table4_PanelB.sas"

Table 5:
- Step 1: Run "Table5_Seasonal.sas"
- Step 2: Run "Factors.sas"
- Step 3: Run "Factors_psigned.sas"
- Step 4: Run "Table5_Non_Seasonal.sas"

Table 6:
- Step 1: Run "Table6_all_to_non_annual.sas"
- Step 2: Run "Table6_quarterly_not_annual.sas"

Table 7:
- Step 1: Run "Table7_PanelAB.sas"
- Step 2: Run "Table7_PanelC.sas"

Table 8:
- Step 1: Run "Table8_1.sas"
- Step 2: Run "Table8_2.sas"
- Step 3: Run "Table8_3.sas"
- Step 4: Run "Table8_4.sas"

Table 9:
- Step 1: Additional Data: Get CRSP-Compustat link table from CRSP
- Step 2: Additional Data: Get Earnings dates from Compustat
- Step 2: Run "Table9_Earnings.sas"
- Step 3: Run "Table9_cycle.sas"

Table 10:
- Step 1: Additional Data: Use daily CRSP data to calculate Amihud
- Step 2: Additional Data: Use IBES data to calculate analyst coverage
- Step 3: Run "Table10_size.sas"
- Step 4: Run "Table10_amihud.sas"
- Step 5: Run "Table10_opbaspread.sas"
- Step 6: Run "Table10_ancoverage.sas"

Table 11:
- Step 1: Run "Table11.sas"

Table 12:
- Step 1: Run "Table12.sas"

Table 13:
- Step 1: Additional Data: Run "Table13_PrepareData.sas"
- Step 2: Additional Data: Get Fama-French daily data from WRDS
- Step 3: Run "Table13.sas"

Table 14:
- Step 1: Run "Table14.sas"

Table 15:
- Step 1: Run "Table15.sas"