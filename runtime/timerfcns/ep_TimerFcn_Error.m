function RUNTIME = ep_TimerFcn_Error(RUNTIME, AX)
% ep_TimerFcn_Error(RUNTIME, RP)
% ep_TimerFcn_Error(RUNTIME, SYN)
% 
% Default Error timer function
% 

% Copyright (C) 2016  Daniel Stolzberg, PhD



RUNTIME = ep_TimerFcn_Stop(RUNTIME,AX); % same as TimerFcn_Stop function
vprintf(1,1,RUNTIME.ERROR);
rethrow(RUNTIME.ERROR)