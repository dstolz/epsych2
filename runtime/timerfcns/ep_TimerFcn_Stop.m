function RUNTIME = ep_TimerFcn_Stop(RUNTIME,AX)
% RUNTIME = ep_TimerFcn_Stop(RUNTIME,SYN)
% RUNTIME = ep_TimerFcn_Stop(RUNTIME,RP)
% 
% Default Stop timer function.
% 
% Daniel.Stolzberg@gmail.com

% Copyright (C) 2016  Daniel Stolzberg, PhD

% not doing anything with CONFIG


if RUNTIME.usingSynapse
    if AX.getMode > 0, AX.setMode(0); end
else
    for i = 1:length(AX)
        AX(i).Halt;
        delete(AX(i));
    end
    h = findobj('Type','figure','-and','Name','RPfig');
    close(h);
end





