% adds an illustration of Simpson's integral

hold on

ii = find((k>=K0).*(k<=K1))

plot(k(ii), pk(ii), '-g', 'LineWidth', 1.5)
plot(k(ii), ck(ii), '-g', 'LineWidth', 1.5)
plot(k(ii(1))*[1,1], [pk(ii(1)), ck(ii(1))], '-g', 'LineWidth', 1.5)
plot(k(ii(end))*[1,1], [pk(ii(end)), ck(ii(end))], '-g', 'LineWidth', 1.5)


hold off



