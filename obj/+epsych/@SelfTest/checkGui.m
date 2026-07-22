function results = checkGui(self)
% results = checkGui(self)
% Check the wiring the session window depends on: the handle struct, the tag
% conventions UpdateGUIstate drives control state from, the .ecfg
% serialization round trip, the event broadcaster, and optionally the state
% machine and the box GUI.
%
% Returns:
%	results	- Result struct array; see epsych.SelfTest.result.
%
% See also: epsych.SelfTest.run, epsych.RunExpt.UpdateGUIstate,
%   epsych.RunExpt.SaveConfig, epsych.RunExpt.LoadConfig
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
    "always_on_top"];
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

% --- I4: config serialization round trip --------------------------------
% SaveConfig flattens Protocol and Subject objects to structs and LoadConfig
% rebuilds them. This is the most fragile path in the class and nothing else
% exercises it.
t = tic;
r = localConfigRoundTrip(rx, GROUP);
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- I5: event broadcaster ----------------------------------------------
t = tic;
r = localEventTest(GROUP);
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- I6: box GUI launch -------------------------------------------------
t = tic;
boxFig = string(rx.FUNCS.BoxFig);
if ~self.IncludeBoxFig
    r = epsych.SelfTest.result("I6_BoxFig", GROUP, "Box GUI launch", "skip", ...
        'Not enabled; launching the box GUI replaces any open instance.', ...
        Remedy = "Tick 'Launch the Box GUI' to run this check.");
elseif isRunning
    r = epsych.SelfTest.result("I6_BoxFig", GROUP, "Box GUI launch", "skip", ...
        'A session is running; launching a second box GUI would close the live one.');
elseif strlength(strtrim(boxFig)) == 0
    r = epsych.SelfTest.result("I6_BoxFig", GROUP, "Box GUI launch", "skip", ...
        'No box GUI is configured.');
else
    r = localBoxFigTest(rx, boxFig, GROUP);
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
function r = localConfigRoundTrip(rx, group)
% Serialize CONFIG the way SaveConfig does, rehydrate it the way LoadConfig
% does, and compare. Writes to a temporary file which is always removed.
CONFIG = rx.CONFIG;
if isempty(CONFIG) || ~isfield(CONFIG,'SUBJECT') || ~isa(CONFIG(1).SUBJECT,'epsych.Subject')
    r = epsych.SelfTest.result("I4_ConfigRoundTrip", group, "Config round trip", "skip", ...
        'No configuration is loaded.');
    return
end

ffn = fullfile(tempdir, sprintf('epsych_selftest_%s.ecfg', ...
    char(datetime('now', Format='yyMMddHHmmssSSS'))));
cleanupFile = onCleanup(@() localDeleteFile(ffn));

problems = strings(1,0);
detail   = strings(1,0);

try
    % --- serialize (mirrors SaveConfig)
    config = CONFIG;
    for i = 1:numel(config)
        if isa(config(i).PROTOCOL, 'epsych.Protocol') && isvalid(config(i).PROTOCOL)
            config(i).PROTOCOL = config(i).PROTOCOL.toStruct();
        end
        if isa(config(i).SUBJECT, 'epsych.Subject')
            config(i).SUBJECT = config(i).SUBJECT.toStruct();
        end
    end
    funcs = rx.FUNCS;
    save(ffn, 'config', 'funcs', '-mat');

    % --- rehydrate (mirrors LoadConfig)
    warning('off','MATLAB:dispatcher:UnresolvedFunctionHandle');
    S = load(ffn, '-mat');
    warning('on','MATLAB:dispatcher:UnresolvedFunctionHandle');

    restored = S.config;
    for i = 1:numel(restored)
        ps = restored(i).PROTOCOL;
        if isstruct(ps) && isfield(ps, 'formatVersion')
            P = epsych.Protocol();
            P.fromStruct(ps);
            restored(i).PROTOCOL = P;
        end
        ss = restored(i).SUBJECT;
        if isstruct(ss) && isfield(ss, 'Name')
            restored(i).SUBJECT = epsych.DefaultSubject(ss);
        end
    end

    % --- compare
    if numel(restored) ~= numel(CONFIG)
        problems(end+1) = sprintf("Subject count changed: %d -> %d", numel(CONFIG), numel(restored));
    end

    for i = 1:min(numel(restored), numel(CONFIG))
        problems = [problems localCompareSubject(CONFIG(i).SUBJECT, restored(i).SUBJECT, i)];
        problems = [problems localCompareProtocol(CONFIG(i).PROTOCOL, restored(i).PROTOCOL, i)];
        detail(end+1) = sprintf("Subject %d (%s): compared", i, string(CONFIG(i).SUBJECT.Name));
    end
catch ME
    problems(end+1) = "Round trip threw: " + string(ME.message);
end

if isempty(problems)
    r = epsych.SelfTest.result("I4_ConfigRoundTrip", group, "Config round trip", "pass", ...
        sprintf('%d subject(s) and their protocols survive save/load unchanged.', numel(CONFIG)), ...
        Detail = detail);
else
    r = epsych.SelfTest.result("I4_ConfigRoundTrip", group, "Config round trip", "fail", ...
        sprintf('%d difference(s) after a save/load round trip.', numel(problems)), ...
        Detail = [problems detail], ...
        Remedy = "Saving this configuration would lose or alter data. Do not rely on the .ecfg until this is fixed.");
end
end

% -----------------------------------------------------------------------
function problems = localCompareSubject(before, after, idx)
% Compare all six persisted Subject fields.
problems = strings(1,0);
if ~isa(after, 'epsych.Subject')
    problems(end+1) = sprintf("Subject %d did not rehydrate into an epsych.Subject.", idx);
    return
end

for f = ["BoxID","Name","Sex","Species","Weight","Notes"]
    a = before.(f);
    b = after.(f);
    if isnumeric(a) && isnumeric(b)
        same = isequaln(a, b);
    else
        same = isequal(string(a), string(b));
    end
    if ~same
        problems(end+1) = sprintf("Subject %d field %s changed: '%s' -> '%s'", ...
            idx, f, string(a), string(b));
    end
end
end

% -----------------------------------------------------------------------
function problems = localCompareProtocol(before, after, idx)
% Compare interface and parameter structure across the round trip.
problems = strings(1,0);
if ~isa(before, 'epsych.Protocol')
    return
end
if ~isa(after, 'epsych.Protocol')
    problems(end+1) = sprintf("Protocol %d did not rehydrate into an epsych.Protocol.", idx);
    return
end

if numel(before.Interfaces) ~= numel(after.Interfaces)
    problems(end+1) = sprintf("Protocol %d interface count changed: %d -> %d", ...
        idx, numel(before.Interfaces), numel(after.Interfaces));
    return
end

for k = 1:numel(before.Interfaces)
    nBefore = localParamNames(before.Interfaces(k));
    nAfter  = localParamNames(after.Interfaces(k));

    lost = setdiff(nBefore, nAfter);
    if ~isempty(lost)
        problems(end+1) = sprintf("Protocol %d interface %s lost parameter(s): %s", ...
            idx, string(before.Interfaces(k).Type), strjoin(string(lost), ", "));
    end
end

if ~isequal(before.Options, after.Options)
    problems(end+1) = sprintf("Protocol %d Options changed across the round trip.", idx);
end
end

% -----------------------------------------------------------------------
function names = localParamNames(iface)
% Sorted parameter names on one interface, tolerating an empty module list.
names = {};
P = iface.all_parameters(includeInvisible=true, includeTriggers=true);
if ~isempty(P)
    names = sort({P.Name});
end
end

% -----------------------------------------------------------------------
function r = localEventTest(group)
% Verify the event broadcaster GUIs and analysis objects subscribe to. A
% throwaway Helper is used so no live listener is disturbed.
fired = struct('NewData', false, 'NewTrial', false, 'ModeChange', false);

try
    H = epsych.Helper;
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
function r = localBoxFigTest(rx, boxFig, group)
% Launch the configured box GUI against a synthetic Runtime and close it.
% This is what PsychTimerStart does once the real runtime exists.
before = findall(groot, 'Type', 'figure');
created = [];
cleanupFigures = onCleanup(@() localDeleteFigures(created));

% The box GUI discovers its controls from RUNTIME.Interfaces. Only already-
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
    rt.HELPER = epsych.Helper;
    rt.dfltDataPath = rx.dfltDataPath;
    if hasInterfaces
        rt.Interfaces = attached;
    end

    feval(char(boxFig), rt);
    drawnow;
catch ME
    created = setdiff(findall(groot, 'Type', 'figure'), before);

    % Without hardware attached, a throw may just mean the GUI needs
    % parameters it cannot see yet -- report it, but do not call it a failure.
    if hasInterfaces
        status = "fail";
        remedy = "The run would start without a box GUI. Fix the function or clear it in Customize > Functions.";
    else
        status = "warn";
        remedy = "Re-run with 'Connect hardware interfaces' enabled to tell a real defect from a missing-hardware error.";
    end

    r = epsych.SelfTest.result("I6_BoxFig", group, "Box GUI launch", status, ...
        sprintf('"%s" raised an error: %s', boxFig, ME.message), ...
        Detail = [context, string(ME.identifier)], ...
        Remedy = remedy, ...
        Mutating = true);
    return
end

created = setdiff(findall(groot, 'Type', 'figure'), before);

if isempty(created)
    r = epsych.SelfTest.result("I6_BoxFig", group, "Box GUI launch", "warn", ...
        sprintf('"%s" ran without error but opened no window.', boxFig), ...
        Remedy = "Confirm this is intended; the operator will see no box GUI during a run.", ...
        Mutating = true);
else
    r = epsych.SelfTest.result("I6_BoxFig", group, "Box GUI launch", "pass", ...
        sprintf('"%s" opened %d window(s), which were closed again.', boxFig, numel(created)), ...
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

% -----------------------------------------------------------------------
function localDeleteFile(ffn)
% Remove a temporary file if it was created.
if isfile(ffn)
    delete(ffn);
end
end
