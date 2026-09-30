% graphically demonstrates the CBOE's integration rule

if exist('plot_triangle')==0
   plot_triangle = 0;
end

hold on


x = [.8, K(1)]; y = [pk(1), pk(ii(1))];

plot([x(1), x(1)], [0, y(1)], '-k'); plot([x(1), x(2)], [y(1), y(2)], '-k'); plot([x(2), x(2)], [0, y(2)], '-k')



x = [K(1), K(2)]; y = [pk(ii(1)), pk(ii(2))];

plot([x(1), x(1)], [0, y(1)], '-k'); plot([x(1), x(2)], [y(1), y(2)], '-k'); plot([x(2), x(2)], [0, y(2)], '-k')



x = [K(2), K(3)]; y = [ck(ii(2)), ck(ii(3))];

plot([x(1), x(1)], [0, y(1)], '-k'); plot([x(1), x(2)], [y(1), y(2)], '-k'); plot([x(2), x(2)], [0, y(2)], '-k')



x = [K(3), K(4)]; y = [ck(ii(3)), ck(ii(4))];

plot([x(1), x(1)], [0, y(1)], '-k'); plot([x(1), x(2)], [y(1), y(2)], '-k'); plot([x(2), x(2)], [0, y(2)], '-k')


x = [K(4), k(end)]; y = [ck(ii(4)), ck(end)];

plot([x(1), x(1)], [0, y(1)], '-k'); plot([x(1), x(2)], [y(1), y(2)], '-k'); plot([x(2), x(2)], [0, y(2)], '-k')



if plot_triangle 

   x = [K(2)+.001, 1]; y = [pk(ii(2)), ck(ii(2)), ck(find(k==1))];

   plot([x(1), x(1)], [y(1), y(2)], '-g', 'LineWidth', 2) 
   plot([x(1), x(2)], [y(2), y(3)], '-g', 'LineWidth', 2)
   plot([x(1), x(2)], [y(1), y(3)], '-g', 'LineWidth', 2)

end




hold off

