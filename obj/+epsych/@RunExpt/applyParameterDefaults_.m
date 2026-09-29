function changed = applyParameterDefaults_(self)
% changed = applyParameterDefaults_(self)
% Put each roster subject's parameter defaults onto its protocol, at the start
% of a Run or Preview.
%
% Every CONFIG entry that came from the roster reads its membership's CURRENT
% defaults (epsych.ParameterDefaults.lookup), puts back whatever the previous
% run replaced, and applies them. The roster file is opened once per Run however
% many subjects share it. A default that no longer fits the protocol is skipped
% and said so -- in the log, the status bar, and the subject's session notes --
% rather than stopping the run: the protocol is the thing that changed, and the
% operator needs to hear about it, not to be locked out by it.
%
% What was applied is written into the subject's session notes, so the data
% file records which values came from the subject rather than the protocol.
% (The session snapshot already holds the resulting values; the note is what
% says where they came from.)
%
% Returns:
%   changed - (1,numel(CONFIG)) logical: true where a protocol's parameters were
%             modified, so ExptDispatch recompiles it.
%
% See also: epsych.ParameterDefaults.applyToConfigEntry, epsych.RunExpt.ExptDispatch
arguments
    self
end

n = numel(self.CONFIG);
changed = false(1, n);
if n == 0 || ~isfield(self.CONFIG, 'ROSTER'), return, end

rosters = containers.Map('KeyType', 'char', 'ValueType', 'any');
statusBits = {};

for i = 1:n
    C = self.CONFIG(i);
    link = C.ROSTER;
    if isempty(link) || ~isstruct(link), continue, end

    % One read of each roster file per Run, shared by its subjects.
    R = [];
    if isfield(link, 'File') && ~isempty(link.File)
        key = lower(strrep(link.File, '/', filesep));
        if ~rosters.isKey(key)
            rosters(key) = epsych.SubjectRoster(link.File);
        end
        R = rosters(key);
    end

    name = '';
    if ~isempty(C.SUBJECT), name = C.SUBJECT.Name; end

    try
        [C, report] = epsych.ParameterDefaults.applyToConfigEntry(C, Roster = R);
    catch ME
        % A failure here leaves the protocol as the file defines it, which is a
        % run the operator can still judge; it must not abort the session.
        vprintf(0, 1, ME);
        vprintf(0, 1, 'Parameter defaults for subject "%s" could not be applied; running the protocol as it stands.', name);
        statusBits{end+1} = sprintf('%s: defaults not applied (see log)', name);
        continue
    end
    self.CONFIG(i) = C;
    changed(i) = report.Changed;

    if ~isempty(report.Message)
        vprintf(0, 1, report.Message);
    end

    if ~isempty(report.Applied)
        vprintf(0, 'Subject "%s" parameter defaults: %s', name, ...
            strjoin({report.Applied.Text}, '; '));
        statusBits{end+1} = sprintf('%s: %d default(s)', name, numel(report.Applied));
    end
    for k = 1:numel(report.Skipped)
        vprintf(0, 1, 'Subject "%s": parameter default skipped -- %s', name, ...
            report.Skipped(k).Reason);
    end
    if ~isempty(report.Skipped)
        statusBits{end+1} = sprintf('%s: %d default(s) skipped (see log)', ...
            name, numel(report.Skipped));
    end

    localNote(self.RUNTIME, i, report);
end

if ~isempty(statusBits)
    self.setStatus(sprintf('Parameter defaults applied -- %s.', strjoin(statusBits, '; ')));
end
end

% -----------------------------------------------------------------------
function localNote(RUNTIME, i, report)
% Record in the subject's notes which values came from its defaults. Stamped
% trial 0, before anything ran. Never throws: the record of a default must not
% be able to stop the run it describes.
parts = {};
if ~isempty(report.Applied)
    parts{end+1} = sprintf('Subject parameter defaults applied: %s.', ...
        strjoin({report.Applied.Text}, '; '));
end
if ~isempty(report.Skipped)
    parts{end+1} = sprintf('Skipped: %s.', strjoin({report.Skipped.Reason}, '; '));
end
if ~isempty(report.Message)
    parts{end+1} = report.Message;
end
if isempty(parts), return, end

try
    if ~isempty(RUNTIME.NOTES) && isvalid(RUNTIME.NOTES)
        RUNTIME.NOTES.add(strjoin(parts, ' '), Subject = i, Trial = 0);
    end
catch ME
    vprintf(2, 'Could not note the parameter defaults for subject %d: %s', i, ME.message)
end
end
