function results = checkHardware(self)
% results = checkHardware(self)
% Inventory the protocol's hardware interfaces and ask each one to check
% itself via hw.Interface.selfTest. Backends that implement the hook report
% far more usefully than any generic probe could; those that do not are
% reported as such rather than silently passing.
%
% Connecting is opt-in (self.IncludeHardwareConnect) because it changes device
% state; the non-invasive pass never issues a hardware command.
%
% Returns:
%	results	- Result struct array; see epsych.SelfTest.result.
%
% See also: epsych.SelfTest.run, hw.Interface.selfTest
arguments
    self
end

GROUP = "Hardware";
results = epsych.SelfTest.result();

if isempty(self.RunExpt) || ~isvalid(self.RunExpt)
    results = epsych.SelfTest.result("G0_NoSession", GROUP, "Hardware", "skip", ...
        'No RunExpt session is open.');
    return
end

CONFIG = self.RunExpt.CONFIG;
if isempty(CONFIG) || ~isfield(CONFIG,'PROTOCOL') || ~isa(CONFIG(1).PROTOCOL, 'epsych.Protocol')
    results = epsych.SelfTest.result("G0_NoConfig", GROUP, "Hardware", "skip", ...
        'No configuration is loaded.');
    return
end

% ExptDispatch hands RUNTIME the interfaces of subject 1's protocol, so those
% are the ones a run will actually use.
interfaces = CONFIG(1).PROTOCOL.Interfaces;

% --- G1: inventory ------------------------------------------------------
t = tic;
if isempty(interfaces)
    r = epsych.SelfTest.result("G1_Inventory", GROUP, "Interface inventory", "fail", ...
        'The protocol owns no hardware interfaces.', ...
        Remedy = "Add at least one interface to the protocol in ProtocolDesigner.");
else
    detail = arrayfun(@localInventoryLine, interfaces);
    r = epsych.SelfTest.result("G1_Inventory", GROUP, "Interface inventory", "info", ...
        sprintf('%d interface(s) configured.', numel(interfaces)), ...
        Detail = detail);
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

if isempty(interfaces)
    return
end

% --- G2: backend self-test, non-invasive -------------------------------
t = tic;
r = localRunBackendSelfTests(interfaces, false, GROUP, "G2");
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- G3: live connect + invasive backend self-test ---------------------
t = tic;
if ~self.IncludeHardwareConnect
    r = epsych.SelfTest.result("G3_Connect", GROUP, "Live hardware connect", "skip", ...
        'Not enabled; connecting changes device state.', ...
        Remedy = "Tick 'Connect hardware interfaces' to run this check.");
elseif self.RunExpt.STATE >= PRGMSTATE.RUNNING
    r = epsych.SelfTest.result("G3_Connect", GROUP, "Live hardware connect", "skip", ...
        'A session is running; hardware must not be reconnected mid-run.');
else
    r = localConnectTest(interfaces, GROUP);
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- G4: Intan path hygiene --------------------------------------------
% RunExpt pushes these onto the interface at run time, so a bad value is
% invisible to the backend's own check until it is too late. Read from the
% session rather than the preferences: a project applies its own paths when its
% subjects are added, and those are what the run will use.
t = tic;
intanRoot = strtrim(char(self.RunExpt.PATHS.IntanRootDir));
intanSet  = strtrim(char(self.RunExpt.PATHS.IntanSettingsFile));
problems  = strings(1,0);
detail    = strings(1,0);

if isempty(intanRoot)
    detail(end+1) = "Recording root: unset; the Data Save Path will be used.";
else
    detail(end+1) = "Recording root: " + string(intanRoot);
    if any(isspace(intanRoot))
        problems(end+1) = "Intan recording path contains spaces, which RHX commands cannot express.";
    end
end

if isempty(intanSet)
    detail(end+1) = "Settings file: unset; no settings will be loaded.";
else
    detail(end+1) = "Settings file: " + string(intanSet);
    if any(isspace(intanSet))
        problems(end+1) = "Intan settings file path contains spaces, which RHX commands cannot express.";
    elseif ~isfile(intanSet)
        problems(end+1) = "Intan settings file does not exist: " + string(intanSet);
    end
end

if isempty(problems)
    r = epsych.SelfTest.result("G4_IntanPrefs", GROUP, "Intan recording paths", "pass", ...
        'The Intan recording paths in force for this session are usable.', ...
        Detail = detail);
else
    r = epsych.SelfTest.result("G4_IntanPrefs", GROUP, "Intan recording paths", "fail", ...
        sprintf('%d problem(s) with the Intan recording paths.', numel(problems)), ...
        Detail = [problems detail], ...
        Remedy = "Fix them on the project (Subjects & Projects > Edit Project > Session Defaults); RHX rejects paths containing spaces.");
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

end

% -----------------------------------------------------------------------
function results = localRunBackendSelfTests(interfaces, invasive, group, idPrefix)
% Ask each interface to check itself, translating hw.Interface.selfTest
% results into engine results. An interface that returns nothing has not
% implemented the hook, which is reported rather than assumed to be fine.
results = epsych.SelfTest.result();

for k = 1:numel(interfaces)
    p = interfaces(k);
    typeName = string(p.Type);
    id = sprintf("%s_%s_%d", idPrefix, matlab.lang.makeValidName(typeName), k);

    try
        backend = p.selfTest(Invasive = invasive);
    catch ME
        vprintf(0, 1, ME);
        results(end+1) = epsych.SelfTest.result(id, group, typeName + ": self-test", "fail", ...
            sprintf('The backend self-test raised an error: %s', ME.message), ...
            Detail = string(ME.identifier), ...
            Remedy = "This is a defect in " + string(class(p)) + ".selfTest; it must report failures, not throw.");
        continue
    end

    if isempty(backend)
        results(end+1) = epsych.SelfTest.result(id, group, typeName + ": self-test", "info", ...
            sprintf('%s provides no self-test; only the inventory above applies.', class(p)), ...
            Remedy = "Implement a selfTest override on " + string(class(p)) + " to check this backend properly.");
        continue
    end

    for j = 1:numel(backend)
        b = backend(j);
        results(end+1) = epsych.SelfTest.result( ...
            sprintf("%s_%d", id, j), group, ...
            typeName + ": " + string(b.name), ...
            string(b.status), string(b.summary), ...
            Detail = b.detail, ...
            Remedy = string(b.remedy), ...
            Mutating = invasive);
    end
end
end

% -----------------------------------------------------------------------
function r = localConnectTest(interfaces, group)
% Connect every interface, assert it reports connected (the same assertion
% epsych.Runtime makes when it takes ownership), run the invasive backend
% self-test, then restore the connection state we found.
wasConnected = arrayfun(@(p) p.IsConnected, interfaces);

failures = strings(1,0);
detail   = strings(1,0);

for k = 1:numel(interfaces)
    p = interfaces(k);
    typeName = string(p.Type);

    if wasConnected(k)
        detail(end+1) = typeName + ": already connected";
        continue
    end

    tk = tic;
    try
        p.connect();
    catch ME
        failures(end+1) = sprintf("%s: connect() threw - %s", typeName, ME.message);
        continue
    end
    elapsed = toc(tk);

    if p.IsConnected
        detail(end+1) = sprintf("%s: connected in %.0f ms", typeName, 1000*elapsed);
    else
        failures(end+1) = sprintf("%s: connect() returned but IsConnected is still false", typeName);
    end
end

if isempty(failures)
    r = epsych.SelfTest.result("G3_Connect", group, "Live hardware connect", "pass", ...
        sprintf('All %d interface(s) connected.', numel(interfaces)), ...
        Detail = detail, Mutating = true);
else
    r = epsych.SelfTest.result("G3_Connect", group, "Live hardware connect", "fail", ...
        sprintf('%d of %d interface(s) failed to connect; a run would abort here.', ...
        numel(failures), numel(interfaces)), ...
        Detail = [failures detail], ...
        Remedy = "Power on the hardware and check cabling, then re-run. See the interface's own results for specifics.", ...
        Mutating = true);
end

% Invasive backend checks, now that the connections are up.
r = [r localRunBackendSelfTests(interfaces, true, group, "G3")];

% Restore: leave connected only what was connected when we arrived.
for k = 1:numel(interfaces)
    if wasConnected(k), continue, end
    try
        interfaces(k).disconnect();
    catch ME
        vprintf(0, 1, ME);
    end
end
end

% -----------------------------------------------------------------------
function s = localInventoryLine(p)
% One inventory line per interface. Every field is read defensively: the
% IsConnected and mode getters of several backends query the device, and an
% inventory must survive absent hardware rather than abort the group.
s = string(p.Type) + " (" + string(class(p)) + ")";

try
    if p.IsConnected
        s = s + ": connected";
    else
        s = s + ": not connected";
    end
catch
    s = s + ": connection state unavailable";
end

try
    nParams = numel(p.all_parameters(includeInvisible=true, includeTriggers=true));
    s = s + sprintf(", %d module(s), %d parameter(s)", numel(p.Module), nParams);
catch
    s = s + ", parameter list unavailable";
end

try
    m = p.mode;
    if ~isempty(m)
        s = s + ", mode " + string(m);
    end
catch
    % A backend that cannot report its mode offline is not itself a finding.
end
end
