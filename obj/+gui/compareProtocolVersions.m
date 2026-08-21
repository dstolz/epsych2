function compareProtocolVersions(parent, from, to, options)
% gui.compareProtocolVersions(parent, from, to)
% gui.compareProtocolVersions(parent, from, to, Name = ..., Note = ...)
% Show what differs between two protocol versions.
%
% The one window both version workflows open: the Protocol Designer's File >
% Version History, where it answers "what changed since that version", and the
% Subjects window's Revert Protocol, where it answers "what would reverting
% actually change". The two sides may be two versions of one file or one
% version of each of two files, which is what a subject's protocol history
% produces when a protocol was revised by saving it under a new name.
%
% It is modal and blocks, because both callers open it from a modal dialog of
% their own: an ordinary window raised from there would be stranded behind the
% dialog that opened it, with no way to reach either.
%
% Parameters:
%   parent - figure to centre on, and the window this one is modal over
%   from   - struct(File, Version) for the OLDER side. Version '' means that
%            file's current content
%   to     - struct(File, Version) for the NEWER side
%
% Options:
%   Name      - window title. Default 'Protocol Changes'
%   Note      - one line of context under the header, in the caller's terms
%               ('what reverting this subject would change', say)
%   FromLabel - override the side captions, which default to
%   ToLabel     '<file> <version>'
%
% See also: epsych.Protocol.compareVersions, epsych.Protocol.diffStructs,
%   epsych.ProtocolDesigner.onVersionHistory

arguments
    parent
    from (1,1) struct
    to (1,1) struct
    options.Name (1,:) char = 'Protocol Changes'
    options.Note (1,:) char = ''
    options.FromLabel (1,:) char = ''
    options.ToLabel (1,:) char = ''
end

report = epsych.Protocol.compareVersions( ...
    localField(from, 'File'), localField(from, 'Version'), ...
    localField(to,   'File'), localField(to,   'Version'));

fromLabel = options.FromLabel;
if isempty(fromLabel), fromLabel = report.A.Label; end
toLabel = options.ToLabel;
if isempty(toLabel), toLabel = report.B.Label; end

d = uifigure('Name', options.Name, 'Position', localCentred(parent, 940, 560), ...
    'WindowStyle','modal');
cleanup = onCleanup(@() localClose(d));

g = uigridlayout(d, [5 1]);
g.RowHeight = {'fit', 'fit', 32, '1x', 32};
g.ColumnWidth = {'1x'};
g.Padding = [12 10 12 10];

header = sprintf('From:  %s\nTo:      %s', fromLabel, toLabel);
if ~isempty(options.Note)
    header = sprintf('%s\n\n%s', header, options.Note);
end
uilabel(g, 'Text', header, 'WordWrap','on');

summary = uilabel(g, 'Text', report.Summary, 'WordWrap','on', 'FontWeight','bold');
if ~report.ok
    summary.FontColor = [0.72 0.42 0.05];
elseif report.Identical
    summary.FontColor = [0.13 0.45 0.20];
end

gTop = uigridlayout(g, [1 4]);
gTop.ColumnWidth = {50, '1x', 150, 110};
gTop.RowHeight = {'fit'};
gTop.Padding = [0 0 0 0];
uilabel(gTop, 'Text','Find:');
findFld = uieditfield(gTop, 'Placeholder', 'filter by parameter, field, or value');
onlyChk = uicheckbox(gTop, 'Text','Changed only', 'Value', false, ...
    'Tooltip','Hide parameters and settings that were added or removed outright');
uibutton(gTop, 'Text','Copy Report', 'ButtonPushedFcn', @(~,~) localCopy(d));

t = uitable(g, 'ColumnName', {'Change', 'Where', 'Field', 'From', 'To'}, ...
    'ColumnWidth', {80, '2x', 110, '3x', '3x'}, ...
    'RowName', {}, 'SelectionType','row');

gBtn = uigridlayout(g, [1 2]);
gBtn.ColumnWidth = {'1x', 100};
gBtn.RowHeight = {'fit'};
gBtn.Padding = [0 0 0 0];
uilabel(gBtn, 'Text','');
uibutton(gBtn, 'Text','Close', 'ButtonPushedFcn', @(~,~) uiresume(d));

% Callbacks take the figure and read the handles back off it, so none of them
% holds this workspace alive after the window has been answered.
d.UserData = struct('Report', report, 'Table', t, 'Find', findFld, ...
    'Only', onlyChk, 'Summary', summary, ...
    'FromLabel', fromLabel, 'ToLabel', toLabel);

% Filter as it is typed: the rows are already in memory, so there is nothing
% to re-read and no reason to make the operator press Enter.
findFld.ValueChangingFcn = @(~, evt) localFill(d, evt.Value);
findFld.ValueChangedFcn  = @(src, ~) localFill(d, src.Value);
onlyChk.ValueChangedFcn  = @(~, ~) localFill(d, findFld.Value);

localFill(d, '');

d.CloseRequestFcn = @(~,~) uiresume(d);
uiwait(d);

localClose(d);
clear cleanup
drawnow;
end

% -----------------------------------------------------------------------
function localFill(d, filterText)
% Repaint the table for the current filter. The text is always passed in: a
% ValueChangingFcn fires before the field itself holds what was typed, so
% reading it back here would always be one keystroke behind.
if ~isgraphics(d), return, end
S = d.UserData;

C = S.Report.Changes;
if S.Only.Value && ~isempty(C)
    C = C(strcmp({C.Change}, 'changed'));
end

if ~isempty(filterText) && ~isempty(C)
    hay = cellfun(@(varargin) lower(strjoin(varargin, ' ')), ...
        {C.Path}, {C.Item}, {C.Old}, {C.New}, {C.Change}, 'uni', 0);
    C = C(contains(hay, lower(filterText)));
end

removeStyle(S.Table);
if isempty(C)
    S.Table.Data = cell(0, 5);
    return
end

S.Table.Data = [reshape({C.Change}, [], 1), reshape({C.Path}, [], 1), ...
    reshape({C.Item}, [], 1), reshape({C.Old}, [], 1), reshape({C.New}, [], 1)];

% Colour the verb, not the row: a wall of coloured text is harder to read than
% the one column that says what kind of change this is.
localStyleRows(S.Table, strcmp({C.Change}, 'added'),   [0.13 0.45 0.20]);
localStyleRows(S.Table, strcmp({C.Change}, 'removed'), [0.65 0.16 0.16]);
localStyleRows(S.Table, strcmp({C.Change}, 'changed'), [0.10 0.35 0.60]);
end

% -----------------------------------------------------------------------
function localStyleRows(t, mask, color)
rows = reshape(find(mask), [], 1);
if isempty(rows), return, end
addStyle(t, uistyle('FontColor', color, 'FontWeight','bold'), 'cell', ...
    [rows, ones(numel(rows), 1)]);
end

% -----------------------------------------------------------------------
function localCopy(d)
% The comparison as plain text, for pasting into a lab notebook. Everything is
% copied, not just what the filter shows: a record of what changed that
% silently omits rows is worse than no record at all.
S = d.UserData;
C = S.Report.Changes;

head = {'Protocol comparison', ...
    sprintf('  From: %s', S.FromLabel), ...
    sprintf('  To:   %s', S.ToLabel), ...
    sprintf('  %s', S.Report.Summary), ''};

body = cell(1, numel(C));
for i = 1:numel(C)
    where = C(i).Path;
    if ~isempty(C(i).Item)
        where = sprintf('%s [%s]', where, C(i).Item);
    end
    switch C(i).Change
        case 'added'
            body{i} = sprintf('  + %s: %s', where, C(i).New);
        case 'removed'
            body{i} = sprintf('  - %s: %s', where, C(i).Old);
        otherwise
            body{i} = sprintf('  ~ %s: %s  ->  %s', where, C(i).Old, C(i).New);
    end
end

try
    clipboard('copy', strjoin([head, body], newline));
    S.Summary.Text = sprintf('%s  (copied to clipboard)', S.Report.Summary);
catch ME
    vprintf(0, 1, ME);
    S.Summary.Text = sprintf('%s  (could not reach the clipboard; see the log)', ...
        S.Report.Summary);
end
end

% -----------------------------------------------------------------------
function v = localField(S, name)
v = '';
if isfield(S, name) && ~isempty(S.(name))
    v = char(string(S.(name)));
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
% Centre on the window that opened this one; a wildly off-screen or deleted
% parent still yields a usable position.
pos = [100 100 w h];
try
    p = parent.Position;
    pos = [p(1) + (p(3) - w) / 2, p(2) + (p(4) - h) / 2, w, h];
catch
end
end
