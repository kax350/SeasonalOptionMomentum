function [callprice, putprice, calldelta, putdelta, gamma, vega, calltheta, puttheta, calltheta_part1, calltheta_part2] = bsp(stock, pvstrike, sqrttau, vol, rf)
%
% this program computes the BS call price more quickly than the default Matlab program
%
% [callprice, putprice, calldelta, putdelta, gamma, vega, calltheta, puttheta, calltheta_part1, calltheta_part2] = bsp(stock, pvstrike, sqrttau, vol, rf)
%
% stock is the stock price
% pvstrike is the present value of the strike price
% sqrttau is the square root of option maturity
% vol is volatility

sdt = sqrttau .* vol;
d1  = log(stock ./ pvstrike)./sdt + .5*sdt;
ND1 = normcdf(d1);
ND2 = normcdf(d1 - sdt);
nd1 = normpdf(d1);

callprice = stock .* ND1 - pvstrike .* ND2;

if nargout<2; return; end

putprice = callprice + pvstrike - stock;

if nargout<3; return; end

calldelta = ND1;

if nargout<4; return; end

putdelta = ND1 - 1;

if nargout<5; return; end

gamma = nd1 ./ (stock .* sdt);

if nargout<6; return; end

vega = stock .* nd1 .* sqrttau;

if nargout<7; return; end

if nargin<5; error('rf is needed if you want to calculate theta'); end

calltheta_part1 = -stock .* nd1 .* vol ./ (2 * sqrttau);

calltheta_part2 = - rf.*pvstrike.*ND2;

calltheta = calltheta_part1 + calltheta_part2;

if nargout<8; return; end

puttheta = calltheta_part1 + rf.*pvstrike.*normcdf(-d1 + sdt);
