function results = checkProtocol(self)
% results = checkProtocol(self)
% Validate and compile each subject's protocol, then check the things the
% runtime will demand of it: the required trigger parameters, and a write-
% parameter map that can be turned into struct fields.
%
% Compilation is always performed on an isolated copy so a self-test never
% mutates the protocol the session is about to run.
%
% Returns:
%	results	- Result struct array; see epsych.SelfTest.result.
%
% See also: epsych.SelfTest.run, epsych.Protocol.validate,
%   epsych.Runtime.resolveTriggerParameters
arguments
    self
end

GROUP = "Protocol";
results = epsych.SelfTest.result();

if isempty(self.RunExpt) || ~isvalid(self.RunExpt)
    results = epsych.SelfTest.result("E0_NoSession", GROUP, "Protocol", "skip", ...
        'No RunExpt session is open.');
    return
end

CONFIG = self.RunExpt.CONFIG;
nSubjects = numel(CONFIG);
if nSubjects == 0 || ~isfield(CONFIG,'PROTOCOL') || isempty(CONFIG(1).PROTOCOL)
    results = epsych.SelfTest.result("E0_NoConfig", GROUP, "Protocol", "skip", ...
        'No configuration is loaded.');
    return
end

% --- E1: validation report ---------------------------------------------
t = tic;
errors   = strings(1,0);
warnings = strings(1,0);
checked  = 0;

for i = 1:nSubjects
    P = CONFIG(i).PROTOCOL;
    nm = localSubjectName(CONFIG(i), i);
    if ~isa(P, 'epsych.Protocol') || ~isvalid(P)
        errors(end+1) = nm + ": CONFIG entry holds no valid epsych.Protocol";
        continue
    end
    checked = checked + 1;

    report = P.validate();
    for k = 1:numel(report)
        line = sprintf("%s [%s] %s", nm, string(report(k).field), string(report(k).message));
        if report(k).severity == 2
            errors(end+1) = line;
        elseif report(k).severity == 1
            warnings(end+1) = line;
        end
    end
end

if ~isempty(errors)
    r = epsych.SelfTest.result("E1_Validate", GROUP, "Protocol validation", "fail", ...
        sprintf('%d validation error(s) across %d protocol(s).', numel(errors), nSubjects), ...
        Detail = [errors warnings], ...
        Remedy = "Open the protocol in ProtocolDesigner and resolve the reported fields; a run will refuse to start.");
elseif ~isempty(warnings)
    r = epsych.SelfTest.result("E1_Validate", GROUP, "Protocol validation", "warn", ...
        sprintf('%d validation warning(s) across %d protocol(s).', numel(warnings), checked), ...
        Detail = warnings, ...
        Remedy = "Review in ProtocolDesigner; a run will start but may not behave as intended.");
else
    r = epsych.SelfTest.result("E1_Validate", GROUP, "Protocol validation", "pass", ...
        sprintf('All %d protocol(s) validate cleanly.', checked));
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- E2: version drift vs the file on disk -----------------------------
t = tic;
drift = strings(1,0);
matched = 0;
for i = 1:nSubjects
    P = CONFIG(i).PROTOCOL;
    pfn = string(CONFIG(i).protocol_fn);
    if ~isa(P,'epsych.Protocol') || strlength(pfn) == 0 || ~isfile(pfn), continue, end

    [onDisk, loadErr] = localLoadProtocol(pfn);
    if ~isempty(loadErr), continue, end

    inMemory = string(P.meta.protocolVersion);
    fileVer  = string(onDisk.meta.protocolVersion);
    if inMemory ~= fileVer
        drift(end+1) = sprintf("%s: session has %s, file has %s", ...
            localSubjectName(CONFIG(i), i), inMemory, fileVer);
    else
        matched = matched + 1;
    end
end

if isempty(drift)
    r = epsych.SelfTest.result("E2_Version", GROUP, "Protocol version", "pass", ...
        sprintf('%d protocol(s) match the version saved on disk.', matched));
else
    r = epsych.SelfTest.result("E2_Version", GROUP, "Protocol version", "warn", ...
        sprintf('%d protocol(s) are out of date relative to their file.', numel(drift)), ...
        Detail = drift, ...
        Remedy = "Right-click the subject and choose 'Update to Latest Version' to pick up the saved changes.");
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- E3: compile an isolated copy --------------------------------------
t = tic;
compiled = cell(1, nSubjects);   % per-subject COMPILED struct, or []
failures = strings(1,0);
detail   = strings(1,0);

for i = 1:nSubjects
    nm = localSubjectName(CONFIG(i), i);
    [copyP, copyErr] = localProtocolCopy(CONFIG(i));
    if ~isempty(copyErr)
        failures(end+1) = nm + ": " + copyErr;
        continue
    end

    try
        copyP.compile();
    catch ME
        failures(end+1) = sprintf("%s: compile failed - %s", nm, ME.message);
        continue
    end

    C = copyP.COMPILED;
    compiled{i} = C;

    if C.ntrials == 0
        failures(end+1) = nm + ": compiled 0 trials";
        continue
    end

    dur = NaN;
    try
        dur = copyP.estimateDuration();
    catch ME
        vprintf(2, 'estimateDuration failed for %s: %s', nm, ME.message);
    end

    detail(end+1) = sprintf("%s: %d trials, %d write parameter(s), est. %s", ...
        nm, C.ntrials, numel(C.writeparams), localDuration(dur));
end

if isempty(failures)
    r = epsych.SelfTest.result("E3_Compile", GROUP, "Protocol compilation", "pass", ...
        sprintf('All %d protocol(s) compile with trials.', nSubjects), ...
        Detail = detail);
else
    r = epsych.SelfTest.result("E3_Compile", GROUP, "Protocol compilation", "fail", ...
        sprintf('%d of %d protocol(s) failed to produce trials.', numel(failures), nSubjects), ...
        Detail = [failures detail], ...
        Remedy = "Open the protocol in ProtocolDesigner and confirm every parameter has at least one value.");
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- E4: required trigger pre-flight ---------------------------------------
% The runtime resolves x_<Trigger>_<BoxID> for every subject against the
% interfaces of CONFIG(1)'s protocol, and errors inside the timer StartFcn if
% one is missing. Checking here turns a mid-session crash into a pre-flight
% failure.
t = tic;
interfaces = CONFIG(1).PROTOCOL.Interfaces;
paramNames = localAllParameterNames(interfaces);
anyConnected = ~isempty(interfaces) && any(arrayfun(@(p) p.IsConnected, interfaces));

if isempty(paramNames) && ~anyConnected
    r = epsych.SelfTest.result("E4_CoreTriggers", GROUP, "required trigger parameters", "skip", ...
        'No parameters are available offline; this hardware discovers them at connect.', ...
        Detail = "Interfaces: " + strjoin(arrayfun(@(p) string(p.Type), interfaces), ", "), ...
        Remedy = "Enable 'Connect hardware interfaces' and re-run to verify the triggers.");
else
    missing = strings(1,0);
    found   = strings(1,0);
    for i = 1:nSubjects
        S = CONFIG(i).SUBJECT;
        if ~isa(S,'epsych.Subject'), continue, end
        for trig = epsych.Runtime.REQUIRED_TRIGGERS
            wanted = sprintf('x_%s_%d', trig, S.BoxID);
            if any(strcmp(paramNames, wanted))
                found(end+1) = string(wanted);
            else
                missing(end+1) = sprintf("%s (box %d): %s", string(S.Name), S.BoxID, wanted);
            end
        end
    end

    if isempty(missing)
        r = epsych.SelfTest.result("E4_CoreTriggers", GROUP, "required trigger parameters", "pass", ...
            sprintf('All %d required trigger(s) are present.', numel(found)), ...
            Detail = found);
    else
        r = epsych.SelfTest.result("E4_CoreTriggers", GROUP, "required trigger parameters", "fail", ...
            sprintf('%d required trigger parameter(s) are missing; the run will abort at start.', numel(missing)), ...
            Detail = missing, ...
            Remedy = "Add the missing x_<Trigger>_<BoxID> parameters to the protocol's interface. " + ...
                     "Every subject's box needs NewTrial, ResetTrig, and TrialComplete.");
    end
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

% --- E5: write-parameter map -------------------------------------------
% ep_TimerFcn_Start turns each writeparams entry into a struct field name, so
% a name that is not a valid identifier, or a duplicate, corrupts the map.
t = tic;
problems = strings(1,0);
totalParams = 0;
for i = 1:nSubjects
    if isempty(compiled{i}), continue, end
    wp = compiled{i}.writeparams;
    nm = localSubjectName(CONFIG(i), i);
    totalParams = totalParams + numel(wp);

    for k = 1:numel(wp)
        name = char(string(wp{k}));
        if ~isvarname(name)
            problems(end+1) = sprintf("%s: '%s' is not a valid struct field name", nm, name);
        end
    end

    [uniqueNames, ~, idx] = unique(wp, 'stable');
    if numel(uniqueNames) ~= numel(wp)
        counts = accumarray(idx(:), 1);
        dupes = string(uniqueNames(counts > 1));
        problems(end+1) = sprintf("%s: duplicate write parameter(s) %s", nm, strjoin(dupes, ", "));
    end
end

if totalParams == 0
    r = epsych.SelfTest.result("E5_WriteParams", GROUP, "Write-parameter map", "skip", ...
        'No compiled write parameters to check.');
elseif isempty(problems)
    r = epsych.SelfTest.result("E5_WriteParams", GROUP, "Write-parameter map", "pass", ...
        sprintf('%d write parameter(s) map cleanly to struct fields.', totalParams));
else
    r = epsych.SelfTest.result("E5_WriteParams", GROUP, "Write-parameter map", "fail", ...
        sprintf('%d problem(s) in the write-parameter map.', numel(problems)), ...
        Detail = problems, ...
        Remedy = "Rename the offending parameters in ProtocolDesigner to unique, valid MATLAB identifiers.");
end
results = [results epsych.SelfTest.withTime(r, toc(t))];

end

% -----------------------------------------------------------------------
function nm = localSubjectName(cfg, idx)
% Best available label for one CONFIG entry.
nm = "subject " + idx;
if isfield(cfg,'SUBJECT') && isa(cfg.SUBJECT, 'epsych.Subject') && strlength(string(cfg.SUBJECT.Name)) > 0
    nm = string(cfg.SUBJECT.Name);
end
end

% -----------------------------------------------------------------------
function [P, errMsg] = localLoadProtocol(pfn)
% Load a protocol from disk, suppressing the unresolved-handle warning the
% rest of the codebase silences around the same call.
P = [];
errMsg = '';
warning('off','MATLAB:dispatcher:UnresolvedFunctionHandle');
try
    P = epsych.Protocol.load(pfn);
catch ME
    errMsg = ME.message;
end
warning('on','MATLAB:dispatcher:UnresolvedFunctionHandle');
end

% -----------------------------------------------------------------------
function [P, errMsg] = localProtocolCopy(cfg)
% Return an isolated copy of a CONFIG entry's protocol: reloaded from its
% file when one exists, otherwise round-tripped through toStruct/fromStruct.
% Compiling the live object would mutate the protocol the session is about to
% run, which a diagnostic must never do.
P = [];
errMsg = '';

pfn = string(cfg.protocol_fn);
if strlength(pfn) > 0 && isfile(pfn)
    [P, errMsg] = localLoadProtocol(pfn);
    return
end

live = cfg.PROTOCOL;
if ~isa(live,'epsych.Protocol') || ~isvalid(live)
    errMsg = 'no valid protocol object';
    return
end

try
    P = epsych.Protocol();
    P.fromStruct(live.toStruct());
catch ME
    P = [];
    errMsg = ME.message;
end
end

% -----------------------------------------------------------------------
function names = localAllParameterNames(interfaces)
% Every parameter name exposed by an interface array, including triggers and
% invisible parameters, in both short and Module.Param qualified form.
names = {};
for k = 1:numel(interfaces)
    P = interfaces(k).all_parameters(includeInvisible=true, includeTriggers=true);
    for j = 1:numel(P)
        names{end+1} = P(j).Name;
        names{end+1} = [P(j).Module.Name '.' P(j).Name];
    end
end
end

% -----------------------------------------------------------------------
function s = localDuration(seconds)
% Format an estimated duration as h:mm:ss, or "unknown".
if isempty(seconds) || ~isnumeric(seconds) || ~isscalar(seconds) || ~isfinite(seconds)
    s = "unknown";
    return
end
s = string(duration(0, 0, seconds, Format='hh:mm:ss'));
end
