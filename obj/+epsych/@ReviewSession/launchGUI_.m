function launchGUI_(obj, guiName)
% launchGUI_(obj, guiName)
% Resolve and open the behavior GUI against the review's runtime.
%
% Same call the live session makes -- feval(name, RUNTIME), one positional
% argument, from epsych.RunExpt.PsychTimerStart -- so a GUI needs to do nothing
% special to be reviewable.
%
% Resolution order, most specific first:
%   1. what the caller asked for;
%   2. what an open epsych.RunExpt is configured with, since the operator
%      reviewing a session is usually set up to run that paradigm;
%   3. what the rig's preference says;
%   4. ep_GenericGUI, which builds itself from the parameters and therefore
%      works for any protocol.
%
% Parameters:
%   obj     - epsych.ReviewSession.
%   guiName - Function or class name, or '' to resolve one.
%
% See also: obj/+epsych/@RunExpt/PsychTimerStart.m, gui.BehaviorGUI

arguments
    obj
    guiName (1,:) char = ''
end

name = localResolveName(guiName);
if isempty(name)
    vprintf(0, 'epsych.ReviewSession: no behavior GUI available; the session is loaded but nothing is shown')
    return
end

obj.BehaviorGUIName = name;
vprintf(1, 'epsych.ReviewSession: opening "%s" for %s', name, obj.describe())

before = findall(groot, 'Type', 'figure');

% A gui.BehaviorGUI subclass returns its object, which is what lets the review
% own its teardown. A function-style GUI takes no output argument at all, and
% asking for one is an error rather than an empty -- so try it, then fall back
% and adopt whatever figure appeared.
try
    obj.GUI = feval(name, obj.RUNTIME);
catch ME
    if localIsTooManyOutputs(ME)
        feval(name, obj.RUNTIME);
        obj.GUI = [];
    else
        % A GUI that throws leaves the review usable rather than failing the
        % open: the data is loaded and can still be seeked programmatically.
        vprintf(0, 1, ME)
        vprintf(0, 1, ['epsych.ReviewSession: "%s" failed to open. The session is loaded; ' ...
            'try Protocol="...eprot" if this paradigm needs parameters the file does not carry.'], name)
        obj.GUI = [];
    end
end

drawnow

% Figures the GUI opened but did not hand back are this review's to close --
% otherwise a function-style GUI leaks its window when the review is deleted.
opened = setdiff(findall(groot, 'Type', 'figure'), before);
if isobject(obj.GUI) && isvalid(obj.GUI) && isprop(obj.GUI, 'h_figure')
    opened = setdiff(opened, obj.GUI.h_figure);
end
obj.OwnedFigures_ = opened;

localAnchor(obj, opened);
localMarkReviewing(obj);

end




function localAnchor(obj, opened)
% localAnchor(obj, opened)
%
% Give the windows a reference back to the review, so the review lives exactly
% as long as they do.
%
% Without this a review opened the ordinary way -- epsych.ReviewSession(file),
% no output argument -- is deleted the moment the constructor returns, taking
% its own windows with it: `clear obj` drops the last reference to a handle
% object. It survived by accident when the transport was open, because the
% transport figure's UserData holds the transport and the transport holds the
% review; with Transport=false the window closed before it could be looked at,
% and CLOSING the transport killed the behavior GUI with it.
%
% appdata rather than UserData: the behavior GUI's figure already stores the
% gui.BehaviorGUI object in UserData, and the pop-out machinery reads it.
% Deleting the window releases this reference, so nothing has to be unwound by
% hand and the review cannot outlive everything it owns.

anchors = opened;
try
    if isobject(obj.GUI) && isvalid(obj.GUI) && isprop(obj.GUI, 'h_figure')
        anchors = [anchors, obj.GUI.h_figure];
    end
catch
end

anchors = anchors(isgraphics(anchors));
for f = anchors(:).'
    try
        setappdata(f, 'epsych_ReviewSession', obj);
    catch ME
        vprintf(3, 'epsych.ReviewSession: could not anchor to a window (%s)', ME.message)
    end
end

if isempty(anchors)
    vprintf(2, ['epsych.ReviewSession: no window to anchor to; keep the returned ' ...
        'object in a variable or the review is discarded when it goes out of scope'])
end

end




function name = localResolveName(requested)
% name = localResolveName(requested)
%
% The first candidate that actually exists on the path. which() rather than
% exist(), because a class in a package directory reports differently from a
% loose function and which() answers for both.

candidates = {requested};

try
    rx = epsych.SelfTest.findActiveRunExpt();
    if ~isempty(rx) && isfield(rx.FUNCS, 'BehaviorGUI')
        g = rx.FUNCS.BehaviorGUI;
        if isa(g, 'function_handle'), g = func2str(g); end
        candidates{end+1} = char(string(g));
    end
catch ME
    vprintf(3, 'epsych.ReviewSession: no open session to take a behavior GUI from (%s)', ME.message)
end

% No preference fallback here: the behavior GUI is owned by the subject's
% roster membership, and the retired ep_RunExpt_FUNCS floor is never written.
candidates{end+1} = 'ep_GenericGUI';

name = '';
for c = candidates
    n = strtrim(char(string(c{1})));
    if isempty(n), continue; end
    if ~isempty(which(n))
        name = n;
        return
    end
    vprintf(2, 'epsych.ReviewSession: "%s" is not on the path', n)
end

end




function tf = localIsTooManyOutputs(ME)
% tf = localIsTooManyOutputs(ME)
%
% Whether the GUI simply does not return anything, as opposed to having failed.
% Both identifiers occur: the first for a function declared with no outputs,
% the second for one whose only output is conditionally cleared.

tf = any(strcmp(ME.identifier, { ...
    'MATLAB:TooManyOutputs', ...
    'MATLAB:maxlhs', ...
    'MATLAB:unassignedOutputInDebug'}));

end




function localMarkReviewing(obj)
% localMarkReviewing(obj)
%
% Say in the window title that this is a review of a file rather than a live
% session, and which file. Without it a populated behavior GUI is
% indistinguishable from a running one -- and on a degraded file the missing
% controls would look like a bug rather than a property of the file.

try
    if ~isobject(obj.GUI) || ~isvalid(obj.GUI) || ~isprop(obj.GUI, 'h_figure')
        return
    end
    f = obj.GUI.h_figure;
    if ~isgraphics(f), return; end
    f.Name = sprintf('[REVIEW] %s — %s', f.Name, obj.describe());
catch ME
    vprintf(3, 'epsych.ReviewSession: could not retitle the window (%s)', ME.message)
end

end
