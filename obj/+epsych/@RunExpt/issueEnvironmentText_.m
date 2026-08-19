function txt = issueEnvironmentText_(self)
% txt = issueEnvironmentText_(self)
% Build the Environment block of a GitHub bug report.
%
% Two halves: what EPsych is (version, commits, worktree, host, MATLAB), which
% comes straight from EPsychInfo, and what this session is (state, config,
% subjects, interfaces, callbacks), which is the half a version string cannot
% give and the half most likely to explain the report.
%
% Every value is fetched inside its own try: several backends' IsConnected
% getters talk to the device, and a rig whose hardware just failed is exactly
% when this runs.
%
% See also: epsych.RunExpt.issueReportFields, EPsychInfo

E = EPsychInfo;
rows = strings(0,2);

rows = localRow(rows, 'EPsych', sprintf('v%s (data format %s)', E.Version, E.DataVersion));
rows = localRow(rows, 'Commit', localTry(@() sprintf('%s  (%s)', ...
    self.formatVersionChecksum(E.chksum), self.formatVersionTimestamp(E.commitTimestamp))));
rows = localRow(rows, 'Latest tag', localTry(@() char(string(E.latestTag))));
rows = localRow(rows, 'stimgen commit', localTry(@() self.formatVersionChecksum(E.stimgenChksum)));

% Shown only when this checkout is a worktree, because in the ordinary case an
% empty row invites a "why is this blank?" round trip on the issue.
wt = localTry(@() char(string(E.worktree)));
if ~isempty(wt) && ~strcmp(wt,'(unavailable)')
    rows = localRow(rows, 'Worktree', wt);
end

d = localTry(@() E.diagnostics);
if isstruct(d)
    rows = localRow(rows, 'MATLAB', sprintf('%s (%s)', d.matlabVersion, d.matlabRelease));
    rows = localRow(rows, 'Platform', d.platform);
    rows = localRow(rows, 'Host', d.hostname);
    rows = localRow(rows, 'Memory', sprintf('%.1f GB total, %.1f GB available', ...
        d.physicalMemoryGB, d.availableMemoryGB));
    rows = localRow(rows, 'Toolboxes', strjoin(string(d.toolboxes), ', '));
else
    rows = localRow(rows, 'MATLAB', sprintf('%s (%s)', version, version('-release')));
    rows = localRow(rows, 'Platform', computer);
end

rows = localRow(rows, 'Session state', localTry(@() char(string(self.STATE))));
rows = localRow(rows, 'Config file', localTry(@() char(self.CurrentConfigFile)));
rows = localRow(rows, 'Subjects', localTry(@() localSubjects(self)));
rows = localRow(rows, 'Protocol', localTry(@() localProtocol(self)));
rows = localRow(rows, 'Interfaces', localTry(@() localInterfaces(self)));
rows = localRow(rows, 'Callbacks', localTry(@() localFuncs(self)));

% Left-aligned key column so the block stays readable inside the issue's code
% fence, where GitHub renders it in a monospaced font.
w = max(strlength(rows(:,1)));
txt = char(join(pad(rows(:,1), w) + " : " + rows(:,2), newline));
end

% -----------------------------------------------------------------------
function rows = localRow(rows, label, value)
% Append one label/value row, normalizing whatever the getter produced.
value = strtrim(string(value));
if isempty(value) || ismissing(value) || strlength(value) == 0
    value = "(none)";
end
rows(end+1,:) = [string(label) value];
end

% -----------------------------------------------------------------------
function v = localTry(fcn)
% Evaluate one report line, reporting failure in place of the value.
try
    v = fcn();
catch ME
    vprintf(2,'issueEnvironmentText_: %s', ME.message);
    v = '(unavailable)';
end
end

% -----------------------------------------------------------------------
function s = localSubjects(self)
% Count only real entries: an unconfigured CONFIG still holds one empty slot.
n = sum(arrayfun(@(c) ~isempty(c.SUBJECT), self.CONFIG));
s = sprintf('%d configured', n);
end

% -----------------------------------------------------------------------
function s = localProtocol(self)
% Subject 1's protocol file, which is the one ExptDispatch hands to RUNTIME.
% Named rather than pathed: the folders above it are usually a subject name.
if isempty(self.CONFIG(1).protocol_fn)
    s = '';
    return
end
[~,name,ext] = fileparts(char(string(self.CONFIG(1).protocol_fn)));
s = [name ext];
end

% -----------------------------------------------------------------------
function s = localInterfaces(self)
% One entry per interface: class, then whether it is currently connected.
% Tested rather than reached through: with no config loaded PROTOCOL is [], and
% "(none)" is the honest answer where the try would report "(unavailable)".
if isempty(self.CONFIG(1).PROTOCOL)
    s = '';
    return
end

ifs = self.CONFIG(1).PROTOCOL.Interfaces;
if isempty(ifs)
    s = '';
    return
end

parts = strings(1,numel(ifs));
for i = 1:numel(ifs)
    parts(i) = string(class(ifs(i)));
    try
        if ifs(i).IsConnected
            parts(i) = parts(i) + " (connected)";
        else
            parts(i) = parts(i) + " (not connected)";
        end
    catch
        parts(i) = parts(i) + " (state unreadable)";
    end
end
s = strjoin(parts, ', ');
end

% -----------------------------------------------------------------------
function s = localFuncs(self)
% Every FUNCS field, whatever a paradigm has put there. Enumerated rather than
% named one by one so a field added later still reaches the issue.
f = fieldnames(self.FUNCS);
if isempty(f)
    s = '';
    return
end

parts = strings(1,numel(f));
for i = 1:numel(f)
    v = self.FUNCS.(f{i});
    if isnumeric(v) && isscalar(v)
        v = num2str(v);
    elseif isa(v,'function_handle')
        v = func2str(v);
    elseif ~(ischar(v) || isstring(v))
        v = sprintf('<%s>', class(v));
    end
    parts(i) = string(f{i}) + "=" + string(v);
end
s = strjoin(parts, ', ');
end
