function onRevertProtocol_(self)
% onRevertProtocol_(self)
% Put the selected subject back on a protocol it was on before.
%
% The dialog lists what the roster recorded and, for whichever entry is
% selected, spells out what going back to it actually does: whether it is
% exact, and whether anything is written to the .eprot. That consequence used
% to be a second dialog raised after this one closed, which a modal uifigure
% could leave stranded behind an undismissable window — there is only ever one
% window in this flow now, so the operator reads the consequence and answers it
% in the same place. The one choice an archived entry carries is the checkbox
% under the list, enabled only when the selected entry offers it: rewrite the
% file itself back to that version, or hold this subject alone on it. Both give
% the subject that version exactly — a held subject's sessions load it out of
% the file's archive — so the checkbox is only about whether the file, and
% therefore every other subject on it, moves too.
%
% Show Changes... answers the question the consequence text cannot: not what
% reverting does to the roster, but what the subject would run differently
% afterwards, parameter by parameter. It compares what it is on now with the
% selected entry — across two files when the protocol was revised by saving it
% under a new name — and is off for an entry whose content cannot be produced.
%
% Retired members are refused, as they are everywhere else in this window's
% protocol handling.
%
% See also: epsych.SubjectRoster.revertProtocol, epsych.SubjectRoster.protocolHistory,
%   epsych.Protocol.restoreVersion, gui.compareProtocolVersions
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

[choice, ok, restoreContent] = localChoose(self.H.figure, rec.Name, current, history, items);
if ~ok, return, end

report = self.Roster.revertProtocol(rec.SubjectID, projectId, Index = choice, ...
    RestoreContent = restoreContent);

if ~report.ok
    self.setStatus_(sprintf('%s: %s', rec.Name, report.message));
    uialert(self.H.figure, report.message, 'Revert Protocol', 'Icon','error');
    return
end

if report.ContentRestored && ~isempty(report.OthersOnFile)
    vprintf(1, 'Protocol content restore also affects %d other subject(s) on the file: %s', ...
        numel(report.OthersOnFile), strjoin(report.OthersOnFile, ', '));
end

% A pending override would keep the table showing the file the operator was
% moving away from, over the record they just restored.
if self.ProtocolOverrides_.isKey(rec.SubjectID)
    self.ProtocolOverrides_.remove(rec.SubjectID);
end

self.refresh();
self.setStatus_(sprintf('%s: %s', rec.Name, report.message));

% An inexact revert is no longer news at this point: the dialog said so before
% the operator chose the entry. The status line carries the outcome, the log
% keeps it, and no second window has to be dismissed.
if ~report.Recoverable
    vprintf(1, '%s: %s', rec.Name, report.message);
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

if strcmp(h.Source, 'disk')
    note = '';
elseif strcmp(h.Source, 'archive')
    note = '  [in file''s version archive]';
elseif isempty(h.OnDiskVersion)
    note = '  [file missing]';
else
    note = sprintf('  [file now holds %s \x2014 not archived]', h.OnDiskVersion);
end

txt = sprintf('%s%s  %s%s%s', fn, fe, localVersionText(h.Version), when, note);
end

% -----------------------------------------------------------------------
function v = localVersionText(v)
if isempty(v), v = '(not recorded)'; end
end

% -----------------------------------------------------------------------
function [txt, exact] = localConsequence(h)
% What reverting to this entry does, in the operator's terms. `exact` says
% whether the subject ends up on the protocol as it was, which is what decides
% the colour: the entry that cannot come back in full is the one worth reading.
[~, fn, fe] = fileparts(h.File);
exact = true;

% An entry from before versions were recorded has no number to name, so every
% sentence below takes the version as a phrase rather than parenthesising it.
version = h.Version;
if isempty(version), version = 'the version recorded for it'; end

switch h.Source
    case 'disk'
        txt = sprintf(['%s%s still holds %s, so going back is exact. Nothing is ' ...
            'written to the file \x2014 only the record of what this subject runs.'], ...
            fn, fe, version);

    case 'archive'
        txt = sprintf(['The version archive inside %s%s keeps %s, so it comes back ' ...
            'exactly either way. Left unticked, this subject alone is held on %s: the ' ...
            'file is untouched and keeps serving everyone else what it holds now, and ' ...
            'this subject''s sessions load %s out of the archive until an update ' ...
            'releases the hold. With the box ticked the file itself is rewritten to ' ...
            'that version \x2014 which changes it for every subject on it \x2014 and ' ...
            'the content being replaced is archived in turn, so that is undoable too.'], ...
            fn, fe, version, version, version);

    otherwise
        exact = false;
        if isempty(h.OnDiskVersion)
            txt = sprintf(['%s%s is missing, so only the protocol and %s come back. ' ...
                'Put the file back where it was before running this subject.'], ...
                fn, fe, version);
        else
            txt = sprintf(['%s%s now holds %s and carries no archived copy of %s ' ...
                '\x2014 it was last saved by an EPsych that did not keep superseded ' ...
                'versions. Reverting records the protocol and the version, but the ' ...
                'subject will run whatever the file holds now. Revise protocols as ' ...
                'separate files to make going back exact.'], ...
                fn, fe, h.OnDiskVersion, version);
        end
end
end

% -----------------------------------------------------------------------
function [idx, ok, restoreContent] = localChoose(parent, name, current, history, items)
% Modal list of history entries, with the consequence of the selected one and
% the only choice it carries. uiconfirm caps out at four options and cannot
% show a list, so this is a small figure rather than a stock dialog.
%
% Deliberately free of nested functions: a callback handle onto a nested
% function keeps this workspace alive for as long as the figure holds the
% handle, which is what kept an earlier version of this dialog on screen after
% it had been answered. The answer travels back through the figure's UserData.
idx = 0;
ok  = false;
restoreContent = false;

d = uifigure('Name', sprintf('Revert Protocol - %s', name), ...
    'Position', localCentred(parent, 580, 430), 'WindowStyle','modal', ...
    'Resize','off');
cleanup = onCleanup(@() localClose(d));

g = uigridlayout(d, [5 1]);
g.RowHeight = {'fit', '1x', 'fit', 'fit', 32};
g.ColumnWidth = {'1x'};
g.Padding = [12 10 12 10];

currentText = '(none)';
if ~isempty(current.Protocol)
    [~, cn, ce] = fileparts(current.Protocol);
    currentText = sprintf('%s%s  %s', cn, ce, localVersionText(current.Version));
end

uilabel(g, 'Text', sprintf('%s is on: %s\n\nGo back to:', name, currentText), ...
    'WordWrap','on');

lst = uilistbox(g, 'Items', items, 'ItemsData', 1:numel(items), ...
    'Value', 1, 'Multiselect','off');

note = uilabel(g, 'WordWrap','on');

chk = uicheckbox(g, 'Text', ...
    ['Also restore the file''s content to this version ' ...
     '(rewrites the .eprot for every subject on it)']);

gBtn = uigridlayout(g, [1 4]);
gBtn.ColumnWidth = {'1x', 130, 100, 100};
gBtn.Padding = [0 0 0 0];
uilabel(gBtn, 'Text','');
btnChanges = uibutton(gBtn, 'Text','Show Changes...', ...
    'ButtonPushedFcn', @(~,~) localShowChanges(d, lst, history, current, name));
uibutton(gBtn, 'Text','Revert', 'ButtonPushedFcn', @(~,~) localAccept(d, lst, chk, history));
uibutton(gBtn, 'Text','Cancel', 'ButtonPushedFcn', @(~,~) uiresume(d));

lst.ValueChangedFcn = @(src,~) localShowEntry(src, history, note, chk, btnChanges);
localShowEntry(lst, history, note, chk, btnChanges);

d.CloseRequestFcn = @(~,~) uiresume(d);
uiwait(d);

if isgraphics(d) && ~isempty(d.UserData)
    idx = d.UserData.Index;
    restoreContent = d.UserData.RestoreContent;
    ok  = true;
end

localClose(d);
clear cleanup
drawnow;
end

% -----------------------------------------------------------------------
function localShowEntry(lst, history, note, chk, btnChanges)
% Re-state the consequence for whichever entry is selected, and offer the
% content restore only where there is content to restore.
h = history(lst.Value);
[txt, exact] = localConsequence(h);

note.Text = txt;
if exact
    note.FontColor = [0.45 0.48 0.52];
else
    note.FontColor = [0.72 0.42 0.05];
end

isArchive = strcmp(h.Source, 'archive');
chk.Enable = isArchive;
% Off by default, matching revertProtocol's own default: holding this one
% subject on the archived version already gives it that version exactly, so
% there is no reason to rewrite a file other animals are on unless that is
% what the operator actually means.
chk.Value  = false;

% An entry whose content cannot be produced has nothing to compare against:
% that is the same 'none' case the consequence text has just explained.
btnChanges.Enable = h.Recoverable;
end

% -----------------------------------------------------------------------
function localShowChanges(d, lst, history, current, name)
% What this subject would actually run differently after reverting. The sides
% are ordered the way the operator is about to travel — from what it runs now
% to what it would run — so From/To read as before/after rather than as
% older/newer, which is not the same thing when a revert goes backwards.
h = history(lst.Value);

gui.compareProtocolVersions(d, ...
    struct('File', current.Protocol, 'Version', current.Version), ...
    struct('File', h.File, 'Version', h.Version), ...
    Name = sprintf('Protocol Changes - %s', name), ...
    FromLabel = sprintf('%s (now)', localSideLabel(current.Protocol, current.Version)), ...
    ToLabel = sprintf('%s (after reverting)', localSideLabel(h.File, h.Version)), ...
    Note = sprintf(['What %s would run differently after reverting. Nothing is ' ...
        'written from this window.'], name));
end

% -----------------------------------------------------------------------
function s = localSideLabel(file, version)
[~, fn, fe] = fileparts(file);
s = strtrim(sprintf('%s%s %s', fn, fe, localVersionText(version)));
end

% -----------------------------------------------------------------------
function localAccept(d, lst, chk, history)
% Take the checkbox at face value only where the entry offers a restore, so a
% tick carried over from another entry cannot rewrite a file.
idx = lst.Value;
d.UserData = struct('Index', idx, ...
    'RestoreContent', strcmp(history(idx).Source, 'archive') && chk.Value);
uiresume(d);
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
