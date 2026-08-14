function onImportFromConfig_(self)
% onImportFromConfig_(self)
% Import the subjects in a .ecfg file, with a per-row preview first.
%
% Import is offered, never automatic, and never overwrites: a name that already
% exists defaults to Link rather than replacing a curated record with a one-off
% session's copy. There is no undo on a shared roster, so the preview is where
% the operator decides, one subject at a time.
%
% See also: epsych.SubjectRoster.importFromConfig, epsych.RunExpt.LoadConfig
arguments
    self
end

start = getpref('ep_RunExpt_Setup','CDir',cd);
if ~isfolder(start), start = cd; end

[fn, pn] = uigetfile({'*.ecfg','EPsych Config (*.ecfg)'; '*.*','All Files (*.*)'}, ...
    'Select a Configuration to Import From', start);
if isequal(fn, 0), return, end

cfn = fullfile(pn, fn);

found = epsych.SubjectRoster.readConfigSubjects_(cfn);
if isempty(found)
    uialert(self.H.figure, sprintf('No subjects were found in "%s".', fn), ...
        'Import from Config', 'Icon','info');
    return
end

% --- preview dialog ------------------------------------------------------
dlg = uifigure('Name','Import Subjects', 'Position',[0 0 620 420], ...
    'WindowStyle','modal', 'CloseRequestFcn', @(~,~) onCancel());
movegui(dlg,'center');

g = uigridlayout(dlg, [4 1]);
g.RowHeight = {'fit', '1x', 28, 32};
g.Padding = [12 12 12 12];
g.RowSpacing = 8;

uilabel(g, 'Text', sprintf(['%d subject(s) in "%s". Existing names default to Link, ' ...
    'which never overwrites the roster record.'], numel(found), fn), 'WordWrap','on');

% Default per row: Link on an exact case-insensitive name match, Import
% otherwise. The operator can override any row.
actions = cell(numel(found), 1);
data = cell(numel(found), 4);
for i = 1:numel(found)
    existing = self.Roster.findSubject(found(i).Name);
    if isempty(existing)
        actions{i} = 'Import';
        status = 'new';
    else
        actions{i} = 'Link';
        status = 'already in the roster';
    end
    data{i,1} = found(i).Name;
    data{i,2} = found(i).Species;
    data{i,3} = status;
    data{i,4} = actions{i};
end

uitable(g, 'Data', data, ...
    'ColumnName', {'Subject','Species','Status','Action'}, ...
    'ColumnFormat', {'char','char','char', {'Import','Link','Skip'}}, ...
    'ColumnEditable', [false false false true], ...
    'ColumnWidth', {150, 110, 180, 100}, ...
    'RowName', {}, ...
    'CellEditCallback', @(~,evt) onActionEdit(evt));

gProj = uigridlayout(g, [1 2]);
gProj.ColumnWidth = {130, '1x'};
gProj.Padding = [0 0 0 0];
uilabel(gProj, 'Text','Add to project:', 'HorizontalAlignment','right');

projectItems = {'(none)'};
projectData  = {''};
if ~isempty(self.Roster.Projects)
    projectItems = [projectItems, {self.Roster.Projects.Name}];
    projectData  = [projectData,  {self.Roster.Projects.ProjectID}];
end
ddProject = uidropdown(gProj, 'Items', projectItems, 'ItemsData', projectData, ...
    'Value', self.selectedProject_());

gButtons = uigridlayout(g, [1 3]);
gButtons.ColumnWidth = {'1x', 90, 90};
gButtons.Padding = [0 0 0 0];
uilabel(gButtons, 'Text','');
uibutton(gButtons, 'Text','Import', 'ButtonPushedFcn', @(~,~) onImport());
uibutton(gButtons, 'Text','Cancel', 'ButtonPushedFcn', @(~,~) onCancel());

uiwait(dlg);

% -------------------------------------------------------------------
    function onActionEdit(evt)
        actions{evt.Indices(1)} = evt.NewData;
    end

% -------------------------------------------------------------------
    function onImport()
        projectId = ddProject.Value;
        if isgraphics(dlg)
            dlg.CloseRequestFcn = '';
            delete(dlg);
        end

        try
            report = self.Roster.importFromConfig(cfn, ...
                ProjectID = projectId, Actions = lower(actions));
        catch ME
            vprintf(0, 1, ME);
            uialert(self.H.figure, ME.message, 'Import from Config', 'Icon','error');
            return
        end

        if ~isempty(projectId)
            self.PendingProject_ = projectId;
        end
        self.refresh();
        self.setStatus_(sprintf('Imported from "%s": %s', fn, report.message));
    end

% -------------------------------------------------------------------
    function onCancel()
        if isgraphics(dlg)
            dlg.CloseRequestFcn = '';
            delete(dlg);
        end
    end

end
