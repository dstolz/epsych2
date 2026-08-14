function readRows(self, rows, options)
% readRows(self, rows)
% readRows(self, rows, Force=true)
% Read the given rows from their interfaces and report the outcome in colour.
%
% Reading is the only thing this window does to hardware without being told to
% write, and it is still never automatic: every call comes from a button, a
% double-click, or a key. That is what makes the window safe to leave open
% beside a running experiment.
%
% Three things are deliberately not read:
%   - write-only parameters, because hw.Parameter.get.Value logs a critical
%     record and returns NaN for them, so a sweep would fill the log with
%     failures that are not failures;
%   - Buffer and Coefficient Buffer parameters, unless Force is set or the
%     "Include buffers" box is ticked, because one of them can be a megabyte
%     off the device and Read All would stall on it;
%   - parameters whose object has been deleted under the window, which is what
%     a config reload leaves behind.
%
% Parameters:
%   rows           - Row indices into Rows. Out-of-range entries are ignored.
%   options.Force  - When true, read bulk types too. Set by the actions that
%                    name their target (double-click, Read Selected): asking
%                    for one buffer is not the same as sweeping them all.
%
% See also: gui.ParameterDebugger, gui.ParameterDebugger.refresh
arguments
    self
    rows (1,:) double {mustBeInteger}
    options.Force (1,1) logical = false
end

rows = rows(rows >= 1 & rows <= numel(self.Rows));
if isempty(rows)
    self.setStatus_('Nothing to read.');
    return
end

readBulk = options.Force || logical(self.H.chkBuffers.Value);

% A sweep of a few hundred hardware parameters is slow enough to look hung,
% and every read is a chance for the backend to throw. The dialog and the
% control disable are both released by onCleanup so an early return cannot
% leave the window dead.
showProgress = numel(rows) > 20;
if showProgress
    controls = [self.H.btnReadAll self.H.btnReadSel];
    set(controls, 'Enable', 'off');
    restoreControls = onCleanup(@() set(controls, 'Enable', 'on'));

    % A progress dialog is a courtesy, not a requirement: it needs a visible
    % figure to attach to, and the sweep must still run when this window was
    % built headless (which is how the smoke test drives it).
    dlg = [];
    try
        dlg = uiprogressdlg(self.H.figure, ...
            'Title','EPsych Parameter Debugger', ...
            'Message', sprintf('Reading %d parameters...', numel(rows)), ...
            'Indeterminate','on');
    catch ME
        vprintf(3, 'gui.ParameterDebugger: no progress dialog: %s', ME.message);
    end
    closeDialog = onCleanup(@() localCloseDialog(dlg));
end

nOK = 0;
nFail = 0;
nSkip = 0;
firstFailure = '';

for row = rows
    R = self.Rows(row);
    P = R.Parameter;

    if ~isvalid(P)
        self.Rows(row).State = self.STATE_FAIL;
        self.Rows(row).Note = 'parameter deleted';
        nFail = nFail + 1;
        if isempty(firstFailure)
            firstFailure = sprintf('%s: the parameter no longer exists', R.Name);
        end
        continue
    end

    if strcmp(P.Access, 'Write')
        self.Rows(row).State = self.STATE_SKIP;
        self.Rows(row).Note = 'write-only';
        nSkip = nSkip + 1;
        continue
    end

    if self.isBulk_(P) && ~readBulk
        self.Rows(row).State = self.STATE_SKIP;
        self.Rows(row).Note = 'buffer - double-click to read';
        nSkip = nSkip + 1;
        continue
    end

    try
        value = P.Value;
    catch ME
        vprintf(2, 'gui.ParameterDebugger: reading "%s" failed: %s', P.Name, ME.message);
        self.Rows(row).State = self.STATE_FAIL;
        self.Rows(row).Note = ME.message;
        nFail = nFail + 1;
        if isempty(firstFailure)
            firstFailure = sprintf('%s: %s', R.Name, ME.message);
        end
        continue
    end

    [txt, editable] = self.valueText_(P, value);
    self.Rows(row).ValueText = txt;
    self.Rows(row).Editable = editable;
    self.Rows(row).State = self.STATE_OK;
    self.Rows(row).Note = self.timestamp_(R.Interface);
    nOK = nOK + 1;
end

% One push to the table for the whole sweep. Updating cell by cell inside the
% loop above would redraw the table once per parameter.
self.Refreshing_ = true;
restoreFlag = onCleanup(@() self.clearRefreshing_());
vcol = self.valueColumn_();
ncol = self.noteColumn_();
for row = rows
    self.H.table.Data{row, vcol} = self.Rows(row).ValueText;
    self.H.table.Data{row, ncol} = self.Rows(row).Note;
end
clear restoreFlag

self.applyStyles_();
self.updateCountLabel_();

if showProgress
    clear closeDialog restoreControls
end

self.setStatus_(localSummary(nOK, nFail, nSkip, firstFailure));

end


% -----------------------------------------------------------------------
function txt = localSummary(nOK, nFail, nSkip, firstFailure)
% What the sweep did, with the first failure quoted: a count of failures with
% no example is not enough to act on, and the log is a menu away.
parts = {sprintf('%d read', nOK)};
if nFail > 0, parts{end+1} = sprintf('%d failed', nFail); end
if nSkip > 0, parts{end+1} = sprintf('%d skipped', nSkip); end

txt = [strjoin(parts, ', ') '.'];
if ~isempty(firstFailure)
    txt = sprintf('%s  First failure - %s', txt, firstFailure);
end
end


function localCloseDialog(dlg)
if ~isempty(dlg) && isvalid(dlg)
    close(dlg);
end
end
