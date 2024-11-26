function RUNTIME = ep_TimerFcn_Stop(RUNTIME,AX)
% RUNTIME = ep_TimerFcn_Stop(RUNTIME,SYN)
% RUNTIME = ep_TimerFcn_Stop(RUNTIME,RP)
% 
% Default Stop timer function.
% 
% Daniel.Stolzberg@gmail.com

% Copyright (C) 2016  Daniel Stolzberg, PhD

% not doing anything with CONFIG


vprintf(2,'Setting mode to Idle')
RUNTIME.HW.set_mode('Idle');