% script to create Figure A1

clear all
close all

subplot(3,2,1)

baseplot

plot_triangle = 1;
cboe

%text(1.0666, 0.0182, 'Call Price / K^2')
%text(0.9374, 0.0216, 'Put Price / K^2', 'HorizontalAlignment', 'right')

axis34(0,.1)
title('Panel A: CBOE')
xlabel('Strike Price (K)')
set(gca,'YTick',[0,.02,.04,.06,.08,.10])
set(gca,'YTickLabels',{'0','.02','.04','.06','.08','.10'})
set(gca,'XTick',[.8,.9,1,1.1,1.2])
set(gca,'YTickLabels',{'0.8','0.9','1','1.1','1.2'})



clear all

subplot(3,2,2)

baseplot
bowtie

axis34(0,.1)
title('Panel B: Simpson''s')
xlabel('Strike Price (K)')
set(gca,'YTick',[0,.02,.04,.06,.08,.10])
set(gca,'YTickLabels',{'0','.02','.04','.06','.08','.10'})
set(gca,'XTick',[.8,.9,1,1.1,1.2])
set(gca,'YTickLabels',{'0.8','0.9','1','1.1','1.2'})



portrait

print -dpng integrals.png
