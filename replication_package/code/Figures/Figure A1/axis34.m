function ax34=axis34(a3,a4)

% utility to change the y axis range without changing the x axis range  
  
if nargin==0
   ax = axis;
   ax34 = [ax(3), ax(4)];
   return
end

if nargin==1
  a4 = a3(2);
  a3 = a3(1);
end

ax = axis;

axis([ax(1), ax(2), a3, a4]);
