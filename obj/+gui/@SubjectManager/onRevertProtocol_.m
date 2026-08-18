function onRevertProtocol_(self)
% onRevertProtocol_(self)
% Put the selected subject back on a protocol it was on before.
%
% The dialog lists what the roster recorded, and says for each entry whether
% going back is exact. It is exact when the named file still holds the version
% it was recorded at — which is the case when protocols are revised as separate
% files, and not the case when one file is saved over. Saving an .eprot
% overwrites it in place and keeps no archive, so an entry whose file has moved
% on cannot be restored as content; reverting to it restores the pointer and
% the recorded version, and says so.
%
% Retired members are refused, as they are everywhere else in this window's
% protocol handling.
%
% See also: epsych.SubjectRoster.revertProtocol, epsych.SubjectRoster.protocolHistory
arguments
    self
end

projectId = self.selectedProject_();
if isempty(projectId)
    uialert(self.H.figure, ...
        ['Select a project on the left first. Protocol history is recorded per ' ...
         'project, so there is none to show in the All Projects view.'], ...
        'Revert Protocol', 'Icon','info');
    return
end

rec = self.selectedRow_();
if isempty(rec), return, end

% Retired members are out of the protocol workflow in both directions: what a
% finished animal is recorded as having run is the record, and rewriting it
% backwards is as wrong as rewriting it forwards.
if self.isRetiredIn_(rec.SubjectID, projectId)
    uialert(self.H.figure, sprintf( ...
        ['"%s" is retired from this project, so its protocol record is left ' ...
         'alone.\n\nRestore it to the project first if it is going to run again.'], ...
        rec.Name), 'Revert Protocol', 'Icon','info');
    return
end

history = self.Roster.protocolHistory(rec.SubjectID, projectId);
if isempty(history)
    uialert(self.H.figure, sprintf( ...
        ['There is no earlier protocol on record for "%s".\n\nHistory starts the ' ...
         'first time a subject''s protocol or version changes, so a subject that ' ...
         'has only ever been on one protocol has nothing to go back to.'], rec.Name), ...
        'Revert Protocol', 'Icon','info');
    return
end

current = self.Roster.protocolStatus(rec.SubjectID, projectId);

items = arrayfun(@(h) localItemText(h), history, 'uni', 0);

[choice, ok] = localChoose(self.H.figure, rec.Name, current, items);
if ~ok, return, end

report = self.Roster.revertProtocol(rec.SubjectID, projectId, Index = choice);

if ~report.ok
    uialert(self.H.figure, report.message, 'Revert Protocol', 'Icon','error');
    return
end

% A pending override would keep the table showing the file the operator was
% moving away from, over the record they just restored.
if self.ProtocolOverrides_.isKey(rec.SubjectID)
    self.ProtocolOverrides_.remove(rec.SubjectID);
end

self.refresh();
self.setStatus_(sprintf('%s: %s', rec.Name, report.message));

if ~report.Recoverable
    uialert(self.H.figure, report.message, 'Revert Protocol', 'Icon','warning');
end

end

% -----------------------------------------------------------------------
function txt = localItemText(h)
% One history entry as a single line: file, version, when, and whether the
% file still holds that version.
[~, fn, fe] = fileparts(h.File);

when = '';
if ~isnat(h.Stamp)
    when = sprintf(' \x00B7 %s', char(h.Stamp, 'dd-MMM-yyyy HH:mm'));
end

version = h.Version;
if isempty(version), version = '(not recorded)'; end

if h.Recoverable
    note = '';
elseif isempty(h.OnDiskVersion)
    note = '  [file missing]';
else
    note = sprintf('  [file now holds %s]', h.OnDiskVersion);
end

txt = sprintf('%s%s  %s%s%s', fn, fe, version, when, note);
end

% -----------------------------------------------------------------------
function [idx, ok] = localChoose(parent, name, current, items)
% Modal list of history entries. uiconfirm caps out at four options and cannot
% show a list, so this is a small figure rather than a stock dialog.
idx = 0;
ok  = false;

d = uifigure('Name', sprintf('Revert Protocol - %s', name), ...
    'Position', localCentred(parent, 560, 340), 'WindowStyle','modal', ...
    'Resize','off');
cleanup = onCleanup(@() localClose(d));

g = uigridlayout(d, [4 2]);
g.RowHeight = {'fit', '1x', 'fit', 32};
g.ColumnWidth = {'1x', 100};
g.Padding = [12 10 12 10];

currentText = '(none)';
if ~isempty(current.Protocol)
    [~, cn, ce] = fileparts(current.Protocol);
    cv = current.Version;
    if isempty(cv), cv = '(not recorded)'; end
    currentText = sprintf('%s%s  %s', cn, ce, cv);
end

lbl = uilabel(g, 'Text', sprintf('%s is on: %s\n\nGo back to:', name, currentText), ...
    'WordWrap','on');
lbl.Layout.Row = 1; lbl.Layout.Column = [1 2];

lst = uilistbox(g, 'Items', items, 'ItemsData', 1:numel(items), ...
    'Value', 1, 'Multiselect','off');
lst.Layout.Row = 2; lst.Layout.Column = [1 2];

note = uilabel(g, 'WordWrap','on', 'FontColor',[0.45 0.48 0.52], 'Text', ...
    ['An entry marked [file now holds ...] cannot be restored as content: saving a ' ...
     'protocol overwrites the file, so only the pointer and the recorded version ' ...
     'come back. Revise protocols as separate files to make going back exact.']);
note.Layout.Row = 3; note.Layout.Column = [1 2];

gBtn = uigridlayout(g, [1 3]);
gBtn.Layout.Row = 4; gBtn.Layout.Column = [1 2];
gBtn.ColumnWidth = {'1x', 100, 100};
gBtn.Padding = [0 0 0 0];
uilabel(gBtn, 'Text','');
uibutton(gBtn, 'Text','Revert', 'ButtonPushedFcn', @(~,~) localAccept());
uibutton(gBtn, 'Text','Cancel', 'ButtonPushedFcn', @(~,~) uiresume(d));

d.CloseRequestFcn = @(~,~) uiresume(d);
uiwait(d);

    function localAccept()
        idx = lst.Value;
        ok  = true;
        uiresume(d);
    end
end

% -----------------------------------------------------------------------
function localClose(d)
if isgraphics(d)
    d.CloseRequestFcn = '';
    delete(d);
end
end

% -----------------------------------------------------------------------
function pos = localCentred(parent, w, h)
% Centre on the manager window, clamped onto the screen by movegui later.
pos = [100 100 w h];
try
    p = parent.Position;
    pos = [p(1) + (p(3)-w)/2, p(2) + (p(4)-h)/2, w, h];
catch
end
end
