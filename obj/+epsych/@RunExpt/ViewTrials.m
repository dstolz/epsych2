function ViewTrials(self)
% obj.ViewTrials
% Display a preview of compiled trials for the selected subject.
% Supports both epsych.Protocol objects and legacy struct-based protocols.
idx = self.H.subject_list.Selection(1);
if isempty(idx), return, end

pfn = char(self.CONFIG(idx).protocol_fn);
if isempty(pfn) || ~isfile(pfn)
    uialert(self.H.figure1, 'Protocol file not found.', 'EPsych', 'Icon', 'warning');
    return
end

warning('off', 'MATLAB:dispatcher:UnresolvedFunctionHandle');
try
    protocol = epsych.Protocol.load(pfn);
catch ME
    warning('on', 'MATLAB:dispatcher:UnresolvedFunctionHandle');
    vprintf(0, 1, ME);
    return
end
warning('on', 'MATLAB:dispatcher:UnresolvedFunctionHandle');

% Preview what the subject will run: its parameter defaults applied to a fresh
% copy, never to the session's own protocol object.
defaultsNote = '';
if isfield(self.CONFIG, 'ROSTER') && ~isempty(self.CONFIG(idx).ROSTER)
    D = epsych.ParameterDefaults.lookup(self.CONFIG(idx).ROSTER);
    if ~isempty(D)
        [~, rep] = epsych.ParameterDefaults.apply(protocol, D);
        defaultsNote = sprintf(', with %d subject default(s)', numel(rep.Applied));
        if ~isempty(rep.Skipped)
            defaultsNote = sprintf('%s (%d skipped)', defaultsNote, numel(rep.Skipped));
        end
    end
end

protocol.compile();
C = protocol.COMPILED;

if C.ntrials == 0
    uialert(self.H.figure1, 'Protocol compiled no trials. Check parameter definitions.', ...
        'EPsych', 'Icon', 'warning');
    return
end

TRUNC = 2000;
trials = C.trials;
if size(trials, 1) > TRUNC
    trials = trials(1:TRUNC, :);
end

% Normalize cell values for uitable display
for r = 1:size(trials, 1)
    for c = 1:size(trials, 2)
        v = trials{r, c};
        if isstring(v)
            trials{r, c} = char(v);
        elseif ~ischar(v) && ~isnumeric(v) && ~islogical(v)
            trials{r, c} = mat2str(v);
        end
    end
end

columnNames = {C.parameters.Name};
fig = uifigure('Name', sprintf('Compiled Trials — %s', pfn), ...
    'Position', [200 100 900 520]);
uilabel(fig, ...
    'Text', sprintf('Showing %d of %d compiled trials%s', size(trials, 1), C.ntrials, defaultsNote), ...
    'Position', [20 486 860 25], ...
    'FontWeight', 'bold');
uitable(fig, ...
    'Position', [20 20 860 460], ...
    'ColumnName', columnNames, ...
    'Data', trials, ...
    'ColumnEditable', false(1, length(columnNames)));
end
