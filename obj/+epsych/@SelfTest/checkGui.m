function results = checkGui(self)
% results = checkGui(self)
% Check the wiring the session window depends on: the handle struct, the tag
% conventions UpdateGUIstate drives control state from, the event
% broadcaster, and optionally the state machine and the behavior GUI.
%
% Returns:
%	results	- Result struct array; see epsych.SelfTest.result.
%
% See also: epsych.SelfTest.run, epsych.RunExpt.UpdateGUIstate
arguments
    self
end

GROUP = "Gui";
results = epsych.SelfTest.result();

if isempty(self.RunExpt) || ~isvalid(self.RunExpt)
    results = epsych.SelfTest.result("I0_NoSession", GROUP, "GUI wiring", "skip", ...
        'No RunExpt session is open.');
    return
end

rx = self.RunExpt;
isRunning = rx.STATE >= PRGMSTATE.RUNNING;

% --- I1: handle inventory ----------------------------------------------
% UpdateGUIstate and the command callbacks index these by name; a rename in
% buildUI turns into an undefined-field error at the worst moment.
t = tic;
requiredGraphics = [ ...
    "figure1", "subject_list", "ctrl_run", "ctrl_preview", "ctrl_pauseall", "ctrl_halt", ...
    "save_data", "view_trials", "edit_protocol", "add_subject", "setup_remove_subject", ...
    "modeIndicator", "mnu_assign_runtime", "setup_record_video", "video_liveview_banner", ...
    "always_on_top", "statusBar"];
requiredOther = ["figureBaseName", "figureDefaultColor"];

missing = strings(1,0);
dead    = strings(1,0);
for nm = requiredGraphics
    if ~isfield(rx.H, nm)
        missing(end+1) = nm;
    elseif ~localIsLive(rx.H.(nm))
        dead(end+1) = nm;
    end
end
for nm = requiredOther
    if ~isfield(rx.H, nm)
        missing(end+1) = nm;
    end
end

if isempty(missing) && isempty(dead)
    r = epsych.SelfTest.result("I1_Handles", GROUP, "Window handles", "pass", ...
        sprintf('All %d expected handles are present and live.', ...
        numel(requiredGraphics) + numel(requiredOther)));
else
    detail = strings(1,0);
    if ~isempty(missing), detail(end+1) = "Missing: " + strjoin(missing, ", "); end
    if ~isempty(dead),    detail(end+1) = "Deleted: " + strjoin(dead, ", "); end
    r = epsych.SelfTest.result("I1_Handles", GROUP, "Window handles", "fail", ...
        sprintf('%d expected handle(s) are missing or deleted.', numel(missing) + numel(dead)), ...
        Detail = detail, ...
        Remedy = "The window is out of sync with buildUI. Close and reopen the session window.");
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- I2: tag conventions ------------------------------------------------
% UpdateGUIstate and onCommand select controls by tag prefix, so a retagged
% control silently stops being enabled or disabled with the session state.
t = tic;
ctrlTagged  = findobj(rx.H.figure1, '-regexp', 'tag', '^ctrl');
setupTagged = findobj(rx.H.figure1, '-regexp', 'tag', '^setup');

if isempty(ctrlTagged) || isempty(setupTagged)
    r = epsych.SelfTest.result("I2_Tags", GROUP, "Control tag conventions", "fail", ...
        sprintf('Found %d ctrl* and %d setup* tagged objects; both must be non-empty.', ...
        numel(ctrlTagged), numel(setupTagged)), ...
        Remedy = "Controls without these tag prefixes are never enabled or disabled by state changes.");
else
    r = epsych.SelfTest.result("I2_Tags", GROUP, "Control tag conventions", "pass", ...
        sprintf('%d ctrl* and %d setup* tagged objects are state-managed.', ...
        numel(ctrlTagged), numel(setupTagged)));
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- I3: state machine cycle -------------------------------------------
t = tic;
if ~self.IncludeGuiStateCycle
    r = epsych.SelfTest.result("I3_StateCycle", GROUP, "State machine", "skip", ...
        'Not enabled; this check briefly changes the session window.', ...
        Remedy = "Tick 'Cycle the live GUI state' to run this check.");
elseif isRunning
    r = epsych.SelfTest.result("I3_StateCycle", GROUP, "State machine", "skip", ...
        'A session is running; the state must not be driven from outside the run.');
else
    r = localStateCycle(rx, GROUP);
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- I5: event broadcaster ----------------------------------------------
t = tic;
r = localEventTest(GROUP);
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- I6: behavior GUI launch -------------------------------------------------
t = tic;
behaviorGUI = string(rx.FUNCS.BehaviorGUI);
if ~self.IncludeBehaviorGUI
    r = epsych.SelfTest.result("I6_BehaviorGUI", GROUP, "Behavior GUI launch", "skip", ...
        'Not enabled; launching the behavior GUI replaces any open instance.', ...
        Remedy = "Tick 'Launch the Behavior GUI' to run this check.");
elseif isRunning
    r = epsych.SelfTest.result("I6_BehaviorGUI", GROUP, "Behavior GUI launch", "skip", ...
        'A session is running; launching a second behavior GUI would close the live one.');
elseif strlength(strtrim(behaviorGUI)) == 0
    r = epsych.SelfTest.result("I6_BehaviorGUI", GROUP, "Behavior GUI launch", "skip", ...
        'No behavior GUI is configured.');
else
    r = localBehaviorGUITest(rx, behaviorGUI, GROUP);
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

end

% -----------------------------------------------------------------------
function tf = localIsLive(h)
% True when h is a live graphics handle or a live object (the mode indicator
% is a plain class instance, not a graphics handle).
tf = false;
if isempty(h), return, end
if isobject(h) && ~isgraphics(h)
    tf = isvalid(h);
    return
end
tf = all(isgraphics(h));
end

% -----------------------------------------------------------------------
function r = localStateCycle(rx, group)
% Drive STATE through each non-running state and assert the control-enable
% contract UpdateGUIstate implements, then restore the original state.
originalState = rx.STATE;
problems = strings(1,0);
detail   = strings(1,0);

% CONFIGLOADED is deliberately absent: UpdateGUIstate promotes it to READY
% and re-enters, so it cannot be observed as a resting state.
expectations = { ...
    PRGMSTATE.READY, {'ctrl_run','on'; 'ctrl_preview','on'; 'ctrl_halt','off'}; ...
    PRGMSTATE.STOP,  {'ctrl_run','on'; 'ctrl_preview','on'; 'save_data','on'}; ...
    PRGMSTATE.ERROR, {'ctrl_run','on'; 'ctrl_preview','on'; 'save_data','on'}; ...
    PRGMSTATE.NOCONFIG, {'ctrl_run','off'; 'ctrl_preview','off'; 'save_data','off'}};

try
    for i = 1:size(expectations, 1)
        state = expectations{i,1};
        rules = expectations{i,2};

        rx.STATE = state;
        rx.UpdateGUIstate;

        for k = 1:size(rules, 1)
            handleName = rules{k,1};
            expected   = rules{k,2};
            actual = char(rx.H.(handleName).Enable);
            if ~strcmpi(actual, expected)
                problems(end+1) = sprintf("%s: %s should be '%s' but is '%s'", ...
                    string(state), handleName, expected, actual);
            end
        end
        detail(end+1) = sprintf("%s: %d control(s) checked", string(state), size(rules,1));
    end
catch ME
    problems(end+1) = "UpdateGUIstate threw: " + string(ME.message);
end

% Always put the window back the way we found it.
rx.STATE = originalState;
try
    rx.UpdateGUIstate;
catch ME
    vprintf(0, 1, ME);
end

if isempty(problems)
    r = epsych.SelfTest.result("I3_StateCycle", group, "State machine", "pass", ...
        sprintf('Control states matched expectations in %d program state(s).', size(expectations,1)), ...
        Detail = detail, Mutating = true);
else
    r = epsych.SelfTest.result("I3_StateCycle", group, "State machine", "fail", ...
        sprintf('%d control(s) did not match the expected enable state.', numel(problems)), ...
        Detail = [problems detail], ...
        Remedy = "UpdateGUIstate and buildUI have diverged; controls will be enabled at the wrong times.", ...
        Mutating = true);
end
end

% -----------------------------------------------------------------------
function r = localEventTest(group)
% Verify the event broadcaster GUIs and analysis objects subscribe to. A
% throwaway EventHub is used so no live listener is disturbed.
fired = struct('NewData', false, 'NewTrial', false, 'ModeChange', false);

try
    H = epsych.EventHub;
    listeners = [ ...
        addlistener(H, 'NewData',    @(~,~) localSetFired('NewData')), ...
        addlistener(H, 'NewTrial',   @(~,~) localSetFired('NewTrial')), ...
        addlistener(H, 'ModeChange', @(~,~) localSetFired('ModeChange'))];
    cleanupListeners = onCleanup(@() delete(listeners));

    H.notify('NewTrial');
    H.notify('NewData');
    H.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Preview));
catch ME
    r = epsych.SelfTest.result("I5_Events", group, "Event broadcaster", "fail", ...
        sprintf('The event system raised an error: %s', ME.message), ...
        Remedy = "GUIs and online analysis subscribe to these events; none would update during a run.");
    return
end

names = string(fieldnames(fired))';
missed = names(~cellfun(@(n) fired.(n), cellstr(names)));

if isempty(missed)
    r = epsych.SelfTest.result("I5_Events", group, "Event broadcaster", "pass", ...
        'NewData, NewTrial, and ModeChange all reached their listeners.');
else
    r = epsych.SelfTest.result("I5_Events", group, "Event broadcaster", "fail", ...
        sprintf('%d event(s) did not reach a listener: %s', numel(missed), strjoin(missed, ", ")), ...
        Remedy = "Online plots and psychophysics objects would never update during a run.");
end

% -------------------------------------------------------------------
    function localSetFired(name)
        fired.(name) = true;
    end
end

% -----------------------------------------------------------------------
function r = localBehaviorGUITest(rx, behaviorGUI, group)
% Launch the configured behavior GUI against a synthetic Runtime and close it.
% This is what PsychTimerStart does once the real runtime exists.
before = findall(groot, 'Type', 'figure');
created = [];
cleanupFigures = onCleanup(@() localDeleteFigures(created));

% The behavior GUI discovers its controls from RUNTIME.Interfaces. Only already-
% connected interfaces are attached: the Runtime setter connects whatever it
% is given, and this check must not bring hardware up as a side effect.
attached = hw.Interface.empty(1,0);
if ~isempty(rx.CONFIG) && isfield(rx.CONFIG,'PROTOCOL') && isa(rx.CONFIG(1).PROTOCOL, 'epsych.Protocol')
    ifs = rx.CONFIG(1).PROTOCOL.Interfaces;
    if ~isempty(ifs)
        attached = ifs(arrayfun(@(p) localSafeIsConnected(p), ifs));
    end
end
hasInterfaces = ~isempty(attached);

if hasInterfaces
    context = sprintf("Launched with %d already-connected interface(s).", numel(attached));
else
    context = "Launched with no interfaces: none were connected, and connecting is out of scope here.";
end

try
    rt = epsych.Runtime;
    rt.isTest = true;
    rt.EVENTS = epsych.EventHub;
    rt.DefaultDataPath = rx.DefaultDataPath;
    if hasInterfaces
        rt.Interfaces = attached;
    end

    feval(char(behaviorGUI), rt);
    drawnow;
catch ME
    created = setdiff(findall(groot, 'Type', 'figure'), before);

    % Without hardware attached, a throw may just mean the GUI needs
    % parameters it cannot see yet -- report it, but do not call it a failure.
    if hasInterfaces
        status = "fail";
        remedy = "The run would start without a behavior GUI. Fix the function on the project (Subjects & Projects > Edit Project > Session Defaults), or choose (none) there.";
    else
        status = "warn";
        remedy = "Re-run with 'Connect hardware interfaces' enabled to tell a real defect from a missing-hardware error.";
    end

    r = epsych.SelfTest.result("I6_BehaviorGUI", group, "Behavior GUI launch", status, ...
        sprintf('"%s" raised an error: %s', behaviorGUI, ME.message), ...
        Detail = [context, string(ME.identifier)], ...
        Remedy = remedy, ...
        Mutating = true);
    return
end

created = setdiff(findall(groot, 'Type', 'figure'), before);

if isempty(created)
    r = epsych.SelfTest.result("I6_BehaviorGUI", group, "Behavior GUI launch", "warn", ...
        sprintf('"%s" ran without error but opened no window.', behaviorGUI), ...
        Remedy = "Confirm this is intended; the operator will see no behavior GUI during a run.", ...
        Mutating = true);
else
    r = epsych.SelfTest.result("I6_BehaviorGUI", group, "Behavior GUI launch", "pass", ...
        sprintf('"%s" opened %d window(s), which were closed again.', behaviorGUI, numel(created)), ...
        Detail = arrayfun(@(f) string(f.Name), created), ...
        Mutating = true);
end
end

% -----------------------------------------------------------------------
function tf = localSafeIsConnected(p)
% IsConnected queries the device on some backends; absent hardware must read
% as "not connected" rather than abort the check.
try
    tf = logical(p.IsConnected);
catch
    tf = false;
end
end

% -----------------------------------------------------------------------
function localDeleteFigures(figs)
% Close figures created by a check.
for i = 1:numel(figs)
    if isgraphics(figs(i))
        ud = figs(i).UserData;
        figs(i).CloseRequestFcn = '';
        delete(figs(i));
        if isobject(ud) && isvalid(ud)
            delete(ud);
        end
    end
end
end

