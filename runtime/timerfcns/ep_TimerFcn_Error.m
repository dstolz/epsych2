function RUNTIME = ep_TimerFcn_Error(RUNTIME)
% ep_TimerFcn_Error(RUNTIME)
% 
% Default Error timer function
% 

% Copyright (C) 2016  Daniel Stolzberg, PhD
% updated for hardware abstraction 2024 DS

% RUNTIME = ep_TimerFcn_Stop(RUNTIME); % same as TimerFcn_Stop function
vprintf(1,1,RUNTIME.ERROR);


try
    t = timerfindall;
    if ~isempty(t)
        stop(t);
        delete(t);
    end
catch me
    vprintf(0,1,me);
end

rethrow(RUNTIME.ERROR)