tic()           % timer
clc
clear
close all

%% preliminaries
ACC_Colors
warning('off','all')
warning
n = 40;             % dimension of L96 system
sqn = sqrt(n);
Ne_Sq = 40;         % ensemble size
spinup_time = 100;  % for getting onto attractor
exp_time = 10;      % dimensionless time units of DA experiment
long_time = 1000;   % long simulation for creating initial ensemble
dt = 0.01;          % model time step
jump = 10;          % number of model time steps between observations
k = 2;              % observe every kth state variable
F = 8*ones(n,1);    % free parameter on L96 RHS (F = 8 leads to chaotic solutions)
r1 = 5.4;           % SqEnKF localization radius
r2 = [2:0.5:8];     % 4DVar localization radius
alpha1 = 0.08;      % SqEnKF inflation parameter
alpha2 = [0.0:0.02:0.36];     % 4DVar inflation parameter
ObsVar = 1;         % measurement/observation variance
sigma = sqrt(ObsVar);
r_size = size(r2,2);
alpha_size = size(alpha2,2);
beta = 0.5;
color1 = 21;
color2 = 11;
spinup_iter = floor(spinup_time/dt);    % number of spinup model time steps
exp_iter = floor(exp_time/dt);          % number of experiment model time steps
q = floor(exp_iter/jump);               % number of observed time steps
q_split = ceil((4/5)*q);                % run EnKF until 4/5 of the way, then do 4DVar
ObsTimes = jump:jump:(exp_iter+jump);   % vector of times when observation occurs
sw = floor((5/6)*exp_iter);
%%

%% setup & utilities
[L1,L2] = L96_get_matrices(n);          % makes matrices for matrix-vector execution of L96
[H,m] = L96_get_H(n,k);                 % creates observation operator
mdim = size(H,1);                       % number of observed state variables
L96fun = @(x)((L1*x).*(L2*x) - x + F);  % Lorenz '96 dynamical system
gradient_fun = @(x)L96_gradient(x,L1,L2,n);     % Lorenz '96 gradient
x_start = unifrnd(-1,1,n,1);            % random initial condition
L_SqEnKF = ACC_Localize(n,r1);          % SqEnKF localization matrix for covariance
%%


%% spinup for initial conditions
% Run a long simulation to get from initial condition 
% onto L96 attractor. Don't save anything except final time step.
% We use a fourth order Adams-Bashforth linear multistep method.
% This requires a fourth order Runge-Kutta method to get started.
% (The 'auto' in the function names refers to the L96 ODE being autonomous)
%%
[X,FEvals] = ODE_RK4_auto_start(L96fun,x_start,dt);

for ll=1:spinup_iter
    [X,FEvals] = ODE_AB4_auto(X,FEvals,L96fun,dt);
end
%%

%% Make ensemble
EnsembleSqEnKF = L96_make_ensemble(L96fun,Ne_Sq,dt,long_time,n);
spread = sqrt(trace(cov(EnsembleSqEnKF'))/n);
%%

%% experiment + observations + DA
% Run for exp_time, and observe every kth variable at every jump_th 
% model time step. Perform DA with each set of observations.
%%

[EnsembleSqEnKF,EnFEvalSqEnKF] = ODE_RK4_auto_start_Ens(L96fun,EnsembleSqEnKF,dt);
TimeSeries4DVar = zeros(n,exp_iter);         % array for storing full 4DVar
spreadVec4DVar = spread.*ones(1,exp_iter);   
ErrorVec4DVar = zeros(1,exp_iter);
Time_Series_True = [X,zeros(n,exp_iter-1)];    % array for storing full true state
total_steps = 0;
error_min = 10;
opt_r = 0;
opt_alpha = 0;

%% from start to first observartions

num_steps = ObsTimes(1);
for ll=2:num_steps
    [Time_Series_True(:,ll),FEvals] = ODE_AB4_auto(Time_Series_True(:,ll-1),FEvals,L96fun,dt);
end

Obs = H*Time_Series_True(:,num_steps) + normrnd(0,sigma,mdim,1);

%% SqEnKF
for jj=2:num_steps
    for mm=1:Ne_Sq
        [EnsembleSqEnKF(:,mm),EnFEvalSqEnKF(:,:,mm)] = ...
            ODE_AB4_auto(EnsembleSqEnKF(:,mm),EnFEvalSqEnKF(:,:,mm),L96fun,dt);
    end
    TimeSeries4DVar(:,jj) = mean(EnsembleSqEnKF,2);
end
[EnsembleSqEnKF,mu_a,spread] = DA_SqEnKF(EnsembleSqEnKF,H,Obs,ObsVar,L_SqEnKF,alpha1);
TimeSeries4DVar(:,num_steps) = mu_a;
%%

%%

%% loop for EnKF spinup

for kk=2:q_split
    num_steps = ObsTimes(kk)-ObsTimes(kk-1);
    
    for ll=(ObsTimes(kk-1)+1):ObsTimes(kk)
        [Time_Series_True(:,ll),FEvals] = ODE_AB4_auto(Time_Series_True(:,ll-1),FEvals,L96fun,dt);
    end
    
    Obs = H*Time_Series_True(:,ObsTimes(kk)) + normrnd(0,sigma,mdim,1);
    
    %% SqEnKF
    for jj=1:4
        EnsembleSqEnKF = ODE_RK4_auto(EnsembleSqEnKF,L96fun,dt);
        EnFEvalSqEnKF(:,jj,:) = L96fun(EnsembleSqEnKF);
        TimeSeries4DVar(:,ObsTimes(kk-1)+jj) = mean(EnsembleSqEnKF,2);
    end
    
    for jj=5:num_steps
        for mm=1:Ne_Sq
            [EnsembleSqEnKF(:,mm),EnFEvalSqEnKF(:,:,mm)] = ...
                ODE_AB4_auto(EnsembleSqEnKF(:,mm),EnFEvalSqEnKF(:,:,mm),L96fun,dt);
        end
        TimeSeries4DVar(:,ObsTimes(kk-1)+jj) = mean(EnsembleSqEnKF,2);
    end
    [EnsembleSqEnKF,mu_a,spread,P_a] = DA_SqEnKF(EnsembleSqEnKF,H,Obs,ObsVar,L_SqEnKF,alpha1);
    TimeSeries4DVar(:,ObsTimes(kk)) = mu_a;
    spreadVec4DVar(ObsTimes(kk-1):(ObsTimes(kk)-1)) = spread.*ones(num_steps,1);
    %%
end

X_star_t_4DVar = mu_a;
Cov4DVar = (1+alpha1)*L_SqEnKF.*P_a;

error_list_4DVar = zeros(r_size,alpha_size);

for ii=1:r_size
    L_4DVar = ACC_Localize(n,r2(ii));         % 4DVar localization matrix for covariance
    for nn=1:alpha_size
        tic() 
        for kk=q_split+1:q
            num_steps = ObsTimes(kk)-ObsTimes(kk-1);
            
            for ll=(ObsTimes(kk-1)+1):ObsTimes(kk)
                [Time_Series_True(:,ll),FEvals] = ODE_AB4_auto(Time_Series_True(:,ll-1),FEvals,L96fun,dt);
            end
            
            Obs = H*Time_Series_True(:,ObsTimes(kk)) + normrnd(0,sigma,mdim,1);
            
            %% 4DVar
            [X_star_t_4DVar,X_star,Time_Series,~,Cov4DVar] = DA_4DVar(X_star_t_4DVar,L96fun,...
                gradient_fun,Cov4DVar,H,X_star_t_4DVar,dt,num_steps,Obs,ObsVar,n);
            TimeSeries4DVar(:,ObsTimes(kk-1):(ObsTimes(kk)-1)) = Time_Series(:,1:(num_steps));
            Cov4DVar = beta*(1+alpha2(nn))*L_4DVar.*Cov4DVar + (1-beta)*P_a;
%             Cov4DVar = (1+alpha2(nn))*L_4DVar.*Cov4DVar;
%             Cov4DVar = 0.5*(Cov4DVar + Cov4DVar');
            spread = sqrt(trace(Cov4DVar)/n);
            spreadVec4DVar(ObsTimes(kk-1):(ObsTimes(kk)-1)) = spread.*ones(num_steps,1);
            %%
        end
        %%
        
        TimeSeries4DVar(:,end) = X_star_t_4DVar;
        spreadVec4DVar(:,end) = spread;
        ErrorEn4DVar = TimeSeries4DVar - Time_Series_True;
        
        ErrorVec4DVar = vecnorm(ErrorEn4DVar,2)./sqn;
        
        if (ii==1)&&(nn==1)
            error_SqEnKF = mean(ErrorVec4DVar(ObsTimes(30):ObsTimes(q_split-1)));
            fprintf('SqEnKF RMSE for r=%g, alpha=%g is %g\n',r1,alpha1,error_SqEnKF)
        end
        
        err = mean(ErrorVec4DVar(ObsTimes(q_split):end));
        error_list_4DVar(ii,nn) = err;
        time = toc();
        fprintf('Average RMSE for r=%g, alpha=%g: %g, time = %g\n',r2(ii),alpha2(nn),...
            err,time)
        if err<error_min
            error_min = err;
            opt_r = r2(ii);
            opt_alpha = alpha2(nn);
        end
    end
end

fprintf('Minimum RMSE for r=%g, alpha=%g is %g\n',opt_r,opt_alpha,error_min)

save error_list_4DVar
%%

