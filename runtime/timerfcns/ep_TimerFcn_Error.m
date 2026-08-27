function RUNTIME = ep_TimerFcn_Error(RUNTIME)
% ep_TimerFcn_Error(RUNTIME)
% 
% Default Error timer function
% 

% Copyright (C) 2016  Daniel Stolzberg, PhD
% updated for hardware abstraction 2024 DS

% RUNTIME = ep_TimerFcn_Stop(RUNTIME); % same as TimerFcn_Stop function
%
% RUNTIME.ERROR is an MException or a timer ErrorFcn event struct; granary
% accepts either and writes identifier, message and stack as one record.
% Level 0, not 1: the failure that ended the run must reach the log and the
% console even when the operator is running at the quietest verbosity.
vprintf(0,1,RUNTIME.ERROR);


try
    t = timerfindall;
    if ~isempty(t)
        stop(t);
        delete(t);
    end
catch me
    vprintf(0,1,me);
end

% rethrow leaves immediately and the session is over, so the record of what
% ended it is put on disk first.
granary.Logger.instance().flush();

rethrow(RUNTIME.ERROR)