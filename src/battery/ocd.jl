using Terv, Polynomials

export Grafite, NMC111, OCD

struct Grafite <: ActiveMaterial end
struct NMC111 <: ActiveMaterial end

function ocd(T,c, ::NMC111)
refT = 298.15
#T=300
#c=0.1
cmax = 1.0
theta= c./cmax

coeff1_refOCP = Polynomial([ -4.656   , 
    0        , 
+ 88.669 , 
0        , 
- 401.119, 
0        , 
+ 342.909, 
0        , 
- 462.471, 
0        , 
+ 433.434]);

coeff2_refOCP =Polynomial([ -1      , 
0       , 
+ 18.933, 
0       , 
- 79.532, 
0       , 
+ 37.311, 
0       , 
- 73.083, 
0       , 
+ 95.960]);


refOCP = coeff1_refOCP(theta)./ coeff2_refOCP(theta);    

coeff1_dUdT = Polynomial([0.199521039        , 
- 0.928373822      , 
+ 1.364550689000003, 
- 0.611544893999998]);

coeff2_dUdT = Polynomial([1                  , 
- 5.661479886999997, 
+ 11.47636191      ,  
- 9.82431213599998 , 
+ 3.048755063])

dUdT = -1e-3.*coeff1_dUdT(theta)./ coeff2_dUdT(theta);
vocd = refOCP + (T - refT) .* dUdT;
return vocd
end
##
function ocd(T,c, ::Grafite)
    cmax=1.0
    theta = c./cmax
    refT = 298.15
    refOCP = (0.7222 
        + 0.1387 .* theta 
        + 0.0290 .* theta.^0.5 
        - 0.0172 ./ theta  
        + 0.0019 ./ theta.^1.5 
        + 0.2808 .* exp(0.9 - 15.0*theta)  
        - 0.7984 .* exp(0.4465.*theta - 0.4108));
    coeff1 = Polynomial([0.005269056 ,
        + 3.299265709,
        - 91.79325798,
        + 1004.911008,
        - 5812.278127,
        + 19329.75490,
        - 37147.89470,
        + 38379.18127,
        - 16515.05308]); 
    coeff2= Polynomial([1, 
        - 48.09287227,
        + 1017.234804,
        - 10481.80419,
        + 59431.30000,
        - 195881.6488,
        + 374577.3152,
        - 385821.1607,
        + 165705.8597]);
        dUdT = 1e-3.*coeff1(theta)./ coeff2(theta);

        vocd = refOCP + (T - refT) .* dUdT;
        return vocd        
end
##
#grafite = Grafite()
#nmc111 = NMC111()
#T=300;
#c=0.1;
#a=OCD(T,c,nmc111)
