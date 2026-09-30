% script to plot Black-Scholes prices as a function of strike price

%clear all
%close all

if exist('show_curves')==0
   show_curves = 1;
end
if exist('show_dots')==0
   show_dots = 1;
end


Delta = .1;

K0 = 1 - .5*Delta;
K1 = 1 + .5*Delta;

minK = 1 - 1.5*Delta;
maxK = 1 + 1.5*Delta;

mink = 1 - 2*Delta;
maxk = 1 + 2*Delta;

K  = round((minK:Delta:maxK)*100)/100;

k  = round((mink:.01:maxk)*100)/100;

stock    = 1;
pvstrike = k;
sqrttau  = 1;
vol      = .1;
rf       = 0;

[c, p] = bsp(stock, pvstrike, sqrttau, vol, rf);

ii = find(ismember(k, K));

ck = c./k.^2;
pk = p./k.^2;

if show_curves==1
   plot(k, ck, ':k', 'LineWidth', 1.5)
   hold on
   plot(k, pk, ':k', 'LineWidth', 1.5)
end
if show_dots==1
   plot(K, ck(ii), 'ok', 'LineWidth', 1.5)
   hold on
   plot(K, pk(ii), 'ok', 'LineWidth', 1.5)
end


axis34(0,.1)

hold off

set(gcf, 'PaperPosition', [0 0 4 3])


