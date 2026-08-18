function onVersionHistory(obj)
% onVersionHistory(obj)
% File > Version History...: the versions the current protocol file holds.
%
% Every save archives the version it replaces inside the .eprot (see
% epsych.Protocol.writeProtocolFile), so the file itself is the history. From
% here an archived version can be opened as a working copy — loaded into the
% designer, marked modified, current path kept, so Ctrl+S saves it back as a
% new version — or restored, rewriting the file through
% epsych.Protocol.restoreVersion.
%
% See also: epsych.Protocol.listVersions, epsych.Protocol.loadVersion,
%   epsych.Protocol.restoreVersion

    p = obj.CurrentProtocolPath;
    if isempty(p) || ~isfile(p)
        obj.setStatus('Version history lives in the protocol file.', ...
            'Save the protocol to an .eprot first; every save archives the version it replaces.');
        return
    end

    [~, fn, fe] = fileparts(p);
    fileLabel = [fn, fe];
    if strcmpi(fe, '.json')
        uialert(obj.Figure, ['JSON protocol files keep no version history. ' ...
            'Save as .eprot to archive versions.'], 'Version History', 'Icon', 'info');
        return
    end

    try
        index = epsych.Protocol.listVersions(p);
    catch ME
        uialert(obj.Figure, ME.message, 'Version History', 'Icon', 'error');
        return
    end

    [action, ver] = localChooseVersion(obj.Figure, fileLabel, index);

    switch action
        case 'open'
            localOpenCopy(obj, p, fileLabel, ver);
        case 'restore'
            localRestore(obj, p, fileLabel, ver);
    end
end

% -----------------------------------------------------------------------
function localOpenCopy(obj, p, fileLabel, ver)
% Load one archived version into the designer as an unsaved working copy.
% CurrentProtocolPath stays, so saving mints a new version of the same file
% rather than silently rewinding it.
    if ~obj.confirmDiscardChanges(), return, end

    warning('off', 'MATLAB:dispatcher:UnresolvedFunctionHandle');
    try
        P = epsych.Protocol.loadVersion(p, ver);
    catch ME
        warning('on', 'MATLAB:dispatcher:UnresolvedFunctionHandle');
        uialert(obj.Figure, ME.message, 'Version History', 'Icon', 'error');
        return
    end
    warning('on', 'MATLAB:dispatcher:UnresolvedFunctionHandle');

    obj.Protocol = P;
    obj.IsModified_ = true;
    obj.setParameterNameFilter('');
    obj.refreshUI();
    obj.Figure.Name = sprintf('Protocol Designer  [%s] (archived copy)', ver);
    obj.setStatus(sprintf('Viewing archived %s of %s', ver, fileLabel), ...
        'This copy is unsaved: Ctrl+S saves it back to the same file as a new version.');
end

% -----------------------------------------------------------------------
function localRestore(obj, p, fileLabel, ver)
% Rewrite the file back to an archived version, then reload the designer
% from it so what is shown is what is on disk.
    if ~obj.confirmDiscardChanges(), return, end

    choice = uiconfirm(obj.Figure, sprintf(['Restore %s of %s?\n\n' ...
        '"As New Version" brings the archived content back as a new version, so the ' ...
        'version counter keeps moving forward and subjects recorded on newer versions ' ...
        'still read as behind the file.\n\n' ...
        '"Exact" rewinds the file to %s exactly, version string included; subjects ' ...
        'recorded on a newer version will then read as ahead of the file.'], ...
        ver, fileLabel, ver), ...
        'Restore Version', ...
        'Options', {'Restore as New Version', 'Restore Exact', 'Cancel'}, ...
        'DefaultOption', 'Restore as New Version', 'CancelOption', 'Cancel', ...
        'Icon', 'warning');

    switch choice
        case 'Restore as New Version'
            mode = 'newversion';
        case 'Restore Exact'
            mode = 'exact';
        otherwise
            return
    end

    report = epsych.Protocol.restoreVersion(p, ver, Mode = mode);
    if ~report.ok
        uialert(obj.Figure, report.message, 'Restore Version', 'Icon', 'error');
        return
    end

    obj.openProtocolFile(p);
    obj.Figure.Name = sprintf('Protocol Designer  [%s]', report.NewVersion);
    obj.setStatus(report.message, '');
end

% -----------------------------------------------------------------------
function [action, ver] = localChooseVersion(parent, fileLabel, index)
% Modal list of the file's versions. uiconfirm cannot show a list, so this is
% a small figure, in the style of gui.SubjectManager's revert dialog.
    action = 'cancel';
    ver = '';

    d = uifigure('Name', sprintf('Version History - %s', fileLabel), ...
        'Position', localCentred(parent, 560, 340), 'WindowStyle', 'modal', ...
        'Resize', 'off');
    cleanup = onCleanup(@() localClose(d));

    g = uigridlayout(d, [4 2]);
    g.RowHeight = {'fit', '1x', 'fit', 32};
    g.ColumnWidth = {'1x', '1x'};
    g.Padding = [12 10 12 10];

    lbl = uilabel(g, 'Text', sprintf(['%s holds %d version(s). Every save archives ' ...
        'the version it replaces inside the file.'], fileLabel, numel(index)), ...
        'WordWrap', 'on');
    lbl.Layout.Row = 1; lbl.Layout.Column = [1 2];

    items = arrayfun(@(e) localItemText(e), index, 'uni', 0);
    lst = uilistbox(g, 'Items', items, 'ItemsData', 1:numel(index), ...
        'Value', 1, 'Multiselect', 'off', ...
        'ValueChangedFcn', @(~, ~) localSelectionChanged());
    lst.Layout.Row = 2; lst.Layout.Column = [1 2];

    note = uilabel(g, 'WordWrap', 'on', 'FontColor', [0.45 0.48 0.52], 'Text', ...
        ['Open Copy loads a version into the designer without touching the file. ' ...
         'Restore rewrites the file back to the selected version; the content it ' ...
         'replaces is archived first, so a restore is itself undoable.']);
    note.Layout.Row = 3; note.Layout.Column = [1 2];

    gBtn = uigridlayout(g, [1 4]);
    gBtn.Layout.Row = 4; gBtn.Layout.Column = [1 2];
    gBtn.ColumnWidth = {'1x', 110, 110, 100};
    gBtn.Padding = [0 0 0 0];
    uilabel(gBtn, 'Text', '');
    uibutton(gBtn, 'Text', 'Open Copy', 'ButtonPushedFcn', @(~, ~) localAccept('open'));
    btnRestore = uibutton(gBtn, 'Text', 'Restore...', ...
        'ButtonPushedFcn', @(~, ~) localAccept('restore'));
    uibutton(gBtn, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) uiresume(d));

    localSelectionChanged();

    d.CloseRequestFcn = @(~, ~) uiresume(d);
    uiwait(d);

    function localSelectionChanged()
        % The current version is already on disk; only archived rows restore.
        btnRestore.Enable = ~index(lst.Value).IsCurrent;
    end

    function localAccept(a)
        action = a;
        ver = index(lst.Value).Version;
        uiresume(d);
    end
end

% -----------------------------------------------------------------------
function txt = localItemText(e)
% One version as a single line: version, when it was written, how, and
% whether it is what the file holds now.
    ver = e.Version;
    if isempty(ver), ver = '(no version)'; end

    txt = ver;
    if ~isempty(e.SavedAt)
        txt = sprintf('%s \x00B7 %s', txt, e.SavedAt);
    end
    if e.IsCurrent
        txt = sprintf('%s  (current)', txt);
    elseif ~isempty(e.Origin) && ~strcmp(e.Origin, 'save')
        txt = sprintf('%s \x00B7 %s', txt, e.Origin);
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
% Centre on the designer window; a wildly off-screen parent still yields a
% usable position.
    pos = [100 100 w h];
    try
        p = parent.Position;
        pos = [p(1) + (p(3) - w) / 2, p(2) + (p(4) - h) / 2, w, h];
    catch
    end
end
