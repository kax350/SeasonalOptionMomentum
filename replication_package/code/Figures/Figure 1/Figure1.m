clear all
close all

maxy = [.75,.5,.75,.2];
tick = [.25,.1,.25,.05];

xlabels = {'2^{-2}','2^{-3}','2^{-4}','2^{-5}','2^{-6}'};

for i=1:4

    inrange = ['B', num2str(i*6+4), ':H', num2str(i*6+8)];

    data    = xlsread('VIXCalc.xlsx', 'Table', inrange);

    err     = data(1:4,3:7)' / 1000000;
    num     = data(5,3:7)';
    pars    = data(1:3,1);
   
    subplot(2,2,i)

    plot(err(:,1), 'k:')
    hold on
    plot(err(:,3), 'k--')
    hold off

    axis([.75,5.25,10^(-5),1])
    ax = axis;

    set(gca, 'XTick', 1:5)
    set(gca, 'XTickLabels', xlabels)
    set(gca, 'YScale', 'log')

    if i==1

       text(3.9589, 0.0173, 'CBOE', 'HorizontalAlignment', 'left')
       text(4.4883, 0.0001, 'Simpson''s', 'HorizontalAlignment', 'right')
       text(3, .25, '# of options with price > .0001', 'HorizontalAlignment', 'center')
    end
       
    for j=1:5
       text(j, .5, num2str(num(j)), 'HorizontalAlignment', 'center')
    end

    xlabel('Distance between strikes')
    ylabel('| Implied / Actual - 1|')

    if i==1
       title('Panel A: K_0 \approx F - \Delta, volatility = 10%')
    end
    if i==2
       title('Panel B: K_0 \approx F, volatility = 10%')
    end
    if i==3
       title('Panel C: K_0 \approx F - \Delta/2, volatility = 10%')
    end
    if i==4
       title('Panel D: K_0 \approx F - \Delta, volatility = 20%')
    end

end

orient landscape
set(gcf, 'PaperPosition', [0.5 .25 10 8])

print -dpng calcvix.png
