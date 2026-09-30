clear all
close all
clc



NLAGS = 3;

fid_1 = readtable('D:/vixseas/Code/Figures/Figure 4/seas_1_12_3_.txt');
fid_2 = readtable('D:/vixseas/Code/Figures/Figure 4/seas_1_36_3_.txt');

for i=1:2

    fid_i = eval(['fid_' num2str(i)]);
    date= fid_i{:,1};
    T = length(date);
    maxlag=12;
    tt = 1:T;
    
   P1= fid_i{:,3};
   mean(P1, 'omitnan')
   
   P2= fid_i{:,4};
   mean(P2, 'omitnan')
   
   P3= fid_i{:,5};
   mean(P3, 'omitnan')
   
   P1_mean = P1*0 + NaN;
   P1_nwse = P1*0 + NaN;
   
  P2_mean = P2*0 + NaN;
   P2_nwse = P2*0 + NaN;

  P3_mean = P3*0 + NaN;
   P3_nwse = P3*0 + NaN;

   for t=60:length(P1)
      tstat = nwtstat(P1(t-59:t),NLAGS);

      P1_mean(t) = mean(P1(t-59:t));
      P1_nwse(t) = mean(P1(t-59:t)) / tstat;
   end
   
   for t=60:length(P2)
      tstat = nwtstat(P2(t-59:t),NLAGS);

      P2_mean(t) = mean(P2(t-59:t));
      P2_nwse(t) = mean(P2(t-59:t)) / tstat;
      end
   
   for t=60:length(P3)
      tstat = nwtstat(P3(t-59:t),NLAGS);

      P3_mean(t) = mean(P3(t-59:t));
      P3_nwse(t) = mean(P3(t-59:t)) / tstat;
   end
   
   
   subplot(2,1,i)
   ymplot([floor(date(tt(60:end))/100), P1_mean(60:end)], 1999:2:2021, 'b:')
   hold on
   plot(P2_mean(60:end), 'k')
   plot(P3_mean(60:end), 'r--')
   
   legend('All','Quarterly','Non-quarterly')

   hold off
end

subplot(2,1,1)
axis34(0,.30)
set(gca, 'YTick', 0:.03:.30)
title('Panel A: Lags 1 to 12; Five-year moving average of high minus low returns')

subplot(2,1,2)
axis34(0,.30)
set(gca, 'YTick', 0:.03:.30)
title('Panel B: Lags 1 to 36; Five-year moving average of high minus low returns')



portrait
print -dpng rolling5y_1yr_3yrs_merged.png
