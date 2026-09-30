clc
clear all
close all

% plot 1
subplot(3,1,1)

varName='logMonthly_RV_cor';
Slopes = readtable(['D:\vixseas\Seasonality plot output\coef_lag_',varName,'.csv']);
plot(Slopes.MHorizon, Slopes.Est, 'r')
hold on

varName='logVIX_Prc';
Slopes = readtable(['D:\vixseas\Seasonality plot output\coef_lag_',varName,'.csv']);
plot(Slopes.MHorizon, Slopes.Est, 'b')
legend('ln(Monthly realized corridor variance)', 'ln(VIX price)')

xlabel('Lag')
ylabel('Coefficient on own lag')
xticks([3:3:Slopes.MHorizon(end)])
xticklabels([3:3:Slopes.MHorizon(end)])
title('Panel (a): ln(Monthly realized corridor variance) and ln(VIX price)')

ylim([0.3 0.9])

% plot 2
subplot(3,1,2)

varName='logCorridorVSR';
Slopes = readtable(['D:\vixseas\Seasonality plot output\coef_lag_',varName,'.csv']);
plot(Slopes.MHorizon, Slopes.Est, 'k')
hold on
plot(Slopes.MHorizon, Slopes.Est+1.96*Slopes.SE, 'k:')
plot(Slopes.MHorizon, Slopes.Est-1.96*Slopes.SE, 'k:')

xlabel('Lag')
ylabel('Coefficient on own lag')
xticks([3:3:Slopes.MHorizon(end)])
xticklabels([3:3:Slopes.MHorizon(end)])
title('Panel (b): ln(Gross corridor variance swap return)')

ylim([0 0.12])

% plot 3
subplot(3,1,3)

varName='VIX_Return_MFcor';
Slopes = readtable(['D:\vixseas\Seasonality plot output\coef_lag_',varName,'.csv']);
plot(Slopes.MHorizon, Slopes.Est, 'k')
hold on
plot(Slopes.MHorizon, Slopes.Est+1.96*Slopes.SE, 'k:')
plot(Slopes.MHorizon, Slopes.Est-1.96*Slopes.SE, 'k:')

xlabel('Lag')
ylabel('Coefficient on own lag')
xticks([3:3:Slopes.MHorizon(end)])
xticklabels([3:3:Slopes.MHorizon(end)])
title('Panel (c): Dynamic VIX return (Model-free corridor hedge)')

ylim([-0.02 0.05])


% print figure
orient portrait
set(gcf, 'PaperPosition', [0.25 .5 8 10])
print('D:\vixseas\Seasonality plot output\cs_regressions_with_individual_periods','-dpng')