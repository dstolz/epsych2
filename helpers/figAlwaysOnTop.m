function figAlwaysOnTop(figh,state)
% figAlwaysOnTop(figh,state)
%
% Maintain figure (figure handle = figh) on top of all other windows if
% state = true.
%
% No errors or warnings are thrown if for some reason this function is
% unable to keep figh on top.
% 
% Added support for `uifigure`; fall back on java DS 2025
%
% Daniel.Stolzberg 2014

return

% narginchk(2,2);
assert(ishandle(figh),'The first input (figh) must be a valid figure handle');
assert(islogical(state)||isscalar(state),'The second input (state) must be true (1) or false (0)');


drawnow nocallbacks

state = ~state;

try
    if state
        figh.WindowStyle = 'alwaysontop';
    else
        figh.WindowStyle = 'normal';
    end

catch

    try %#ok<TRYNC>
        warning('off','MATLAB:HandleGraphics:ObsoletedProperty:JavaFrame');
        J = get(figh,'JavaFrame');
        if verLessThan('matlab','8.1')
            J.fHG1Client.getWindow.setAlwaysOnTop(state);
        else
            J.fHG2Client.getWindow.setAlwaysOnTop(state);
        end
        warning('on','MATLAB:HandleGraphics:ObsoletedProperty:JavaFrame');
    end
end