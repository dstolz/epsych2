function RUNTIME = ep_TimerFcn_Error(RUNTIME)
% ep_TimerFcn_Error(RUNTIME)
% 
% Default Error timer function
% 

% Copyright (C) 2016  Daniel Stolzberg, PhD
% updated for hardware abstraction 2024 DS

% RUNTIME = ep_TimerFcn_Stop(RUNTIME); % same as TimerFcn_Stop function
vprintf(1,1,RUNTIME.ERROR);
rethrow(RUNTIME.ERROR)