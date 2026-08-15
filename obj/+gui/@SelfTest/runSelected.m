function runSelected(self, groupIds)
% runSelected(self, groupIds)
% Run the named check groups and refresh the table, detail pane, and footer.
%
% Parameters:
%	self		- gui.SelfTest instance.
%	groupIds	- Group ids to run; see epsych.SelfTest.catalog.
%
% See also: gui.SelfTest, epsych.SelfTest.run
arguments
    self
    groupIds (1,:) string
end

if isempty(groupIds)
    return
end

% Refuse the mutating groups outright while a session is running rather than
% letting each check discover it and report a skip: reconnecting hardware or
% driving STATE mid-run is not something to leave to a per-check guard.
rx = self.Engine.RunExpt;
if ~isempty(rx) && isvalid(rx) && rx.STATE >= PRGMSTATE.RUNNING
    if self.Engine.IncludeHardwareConnect || self.Engine.IncludeBehaviorGUI || self.Engine.IncludeGuiStateCycle
        uialert(self.H.figure, ...
            ['A session is running. Checks that connect hardware, launch the behavior GUI, ' ...
             'or change the window state cannot run now and will be reported as skipped.'], ...
            'Self-Test', 'Icon', 'warning');
    end
end

controls = [self.H.btnRunAll self.H.btnRunSelected self.H.btnCopy self.H.btnSave];
set(controls, 'Enable', 'off');
restoreControls = onCleanup(@() set(controls, 'Enable', 'on'));

dlg = uiprogressdlg(self.H.figure, ...
    'Title', 'EPsych Self-Test', ...
    'Message', sprintf('Running %d check group(s)...', numel(groupIds)), ...
    'Indeterminate', 'on');
closeDialog = onCleanup(@() localCloseDialog(dlg));

runStart = tic;
try
    self.Results = self.Engine.run(groupIds);
catch ME
    vprintf(0, 1, ME);
    uialert(self.H.figure, sprintf('The self-test could not complete:\n\n%s', ME.message), ...
        'Self-Test', 'Icon', 'error');
    return
end
elapsed = toc(runStart);

% --- populate the table
n = numel(self.Results);
data = cell(n, 5);
for i = 1:n
    r = self.Results(i);
    data{i,1} = char(r.group);
    data{i,2} = char(r.name);
    data{i,3} = upper(char(r.status));
    data{i,4} = char(r.summary);
    data{i,5} = sprintf('%.3f', r.seconds);
end
self.H.table.Data = data;

% --- colour the rows by status
removeStyle(self.H.table);
for i = 1:n
    s = uistyle('BackgroundColor', self.statusColor(self.Results(i).status));
    addStyle(self.H.table, s, 'row', i);
end

% Land the operator on the first thing that needs attention rather than on
% row 1, which is almost always a passing environment check.
attention = find(ismember(string({self.Results.status}), ["fail","warn"]), 1);
if isempty(attention)
    self.H.table.Selection = [];
    self.H.detail.Value = {'Nothing needs attention. Select a row to see its details.'};
else
    self.H.table.Selection = attention;
    % Selecting a row does not bring it into view, and a failure the operator
    % has to scroll to find is a failure they will miss.
    scroll(self.H.table, 'row', attention);
    evt.Selection = attention;
    self.onSelectionChanged(evt);
end

% --- footer tally
s = epsych.SelfTest.rollup(self.Results);
self.setStatus(sprintf( ...
    '%d passed  |  %d failed  |  %d warning(s)  |  %d skipped  |  %d info      (%d checks in %.1f s)', ...
    s.pass, s.fail, s.warn, s.skip, s.info, s.total, elapsed));

end

% -----------------------------------------------------------------------
function localCloseDialog(dlg)
% Close the progress dialog however this function exits.
if ~isempty(dlg) && isvalid(dlg)
    close(dlg);
end
end
