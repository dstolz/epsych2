function refreshHeader_(self)
% refreshHeader_(self)
% Bring the header, the notification bar, the title and the data-dependent
% menus up to date with the Study. Called on every Study event the window
% follows; writes the controls under Updating_ so their callbacks do not
% take the write for an edit.
%
% See also: epsych.BehaviorAnalysis.buildUI

if ~isfield(self.H, 'figure') || ~isgraphics(self.H.figure)
    return
end
self.Updating_ = true;
cleanup = onCleanup(@() self.doneUpdating_());

H_ = self.H;
S = self.Study;
controls = [H_.ddPreset H_.ddAnalysis H_.ddParameter H_.edWindow H_.chkTest H_.edTypes];
if isempty(S)
    H_.lblRoot.Text = '(no data root open)';
    H_.lblRoot.Tooltip = '';
    H_.lblCounts.Text = '';
    H_.lblSave.Text = '';
    set(controls, 'Enable', 'off');
    H_.figure.Name = 'Behavior Analysis';
    self.refreshMenus_();
    self.setBar_("");
    return
end
set(controls, 'Enable', 'on');

P = S.Project;
C = S.Catalog;
s = S.Settings;

% ---- root, counts, save state -----------------------------------------
H_.lblRoot.Text = char(S.Root);
H_.lblRoot.Tooltip = char(sprintf("Project file: %s\n%s\nScan cache: %s (%s)\nScanned: %s", ...
    P.File, P.summary(), C.CacheFile, C.CacheState, localTime(C.ScannedAt)));
T = S.sessions(IncludeHidden = true);
n = height(T);
nSubj = 0;
nHidden = 0;
nTest = 0;
if n > 0
    nSubj = numel(unique(string(T.Project) + "/" + string(T.Subject)));
    nHidden = sum(T.Hidden);
    nTest = sum(T.IsTest);
end
H_.lblCounts.Text = char(sprintf("%d sessions · %d subjects · %d hidden · %d test · %d checked", ...
    n, nSubj, nHidden, nTest, numel(self.analysedKeys())));
[~, rootName] = fileparts(S.Root);
if P.ReadOnly
    H_.lblSave.Text = 'Read-only';
    H_.lblSave.FontColor = self.WARN;
elseif P.Dirty
    H_.lblSave.Text = 'Unsaved';
    H_.lblSave.FontColor = self.WARN;
    rootName = rootName + " *";
elseif P.LoadedStamp.Exists
    H_.lblSave.Text = 'Saved';
    H_.lblSave.FontColor = self.MUTED;
else
    H_.lblSave.Text = 'New';
    H_.lblSave.FontColor = self.MUTED;
end
H_.figure.Name = char("Behavior Analysis — " + rootName);

% ---- preset ------------------------------------------------------------
names = reshape(string([P.Presets.Name]), 1, []);
current = "::custom";
cur = s.toStruct();
for k = 1:numel(names)
    try
        if isequal(behavior.Settings.fromStruct(P.Presets(k).Settings).toStruct(), cur)
            current = names(k);
            break
        end
    catch ME
        vprintf(2, ME);
    end
end
H_.ddPreset.Items = cellstr(["(custom)" names "Save as..." "Manage..."]);
H_.ddPreset.ItemsData = cellstr(["::custom" names "::saveas" "::manage"]);
H_.ddPreset.Value = char(current);

% ---- analysis settings ----------------------------------------------------
H_.ddAnalysis.Value = char(s.Analysis);
params = self.parameterNames_();
if s.Parameter ~= "" && ~ismember(s.Parameter, params)
    params = [s.Parameter params];
end
H_.ddParameter.Items = cellstr(["(auto)" params]);
H_.ddParameter.ItemsData = cellstr(["" params]);
H_.ddParameter.Value = char(s.Parameter);
H_.edWindow.Value = char(s.Window);
H_.chkTest.Value = s.ExcludeTest;
H_.edTypes.Value = char(strjoin(string(s.ExcludeTrialTypes), ", "));

% ---- notification bar ----------------------------------------------------
msg = strings(1, 0);
if self.StoreProblem_ ~= ""
    msg(end+1) = self.StoreProblem_;
elseif P.ReadOnly
    msg(end+1) = "The project file is read-only here (" + strjoin(P.Warnings, " ") + ").";
elseif isfile(P.Store)
    msg(end+1) = "The project cannot be saved: " + P.Store + " is a file, not a folder.";
end
nWarn = numel(C.Warnings) + numel(P.Warnings);
if nWarn > 0
    msg(end+1) = sprintf("%d warning(s) from the scan and the project file.", nWarn);
end
H_.barWarnings.Visible = matlab.lang.OnOffSwitchState(nWarn > 0);
H_.barStore.Visible = matlab.lang.OnOffSwitchState(self.StoreProblem_ ~= "" || P.ReadOnly || isfile(P.Store));
self.setBar_(strjoin(msg, "  "));

self.refreshMenus_();
delete(cleanup);

end


function txt = localTime(t)
if isnat(t)
    txt = "never";
else
    txt = string(t, 'yyyy-MM-dd HH:mm:ss');
end
end
