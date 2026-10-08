function buildMenus_(self)
% buildMenus_(self)
% The menu bar. Ctrl+<letter> shortcuts are menu Accelerators; the keys a
% uimenu cannot carry (F1, F5, Delete, Enter, Ctrl+Shift+F) are handled by
% the window's key handler (onKeyPress_), and named in the item text so
% they can be found. Items whose contents depend on the data (Recent Roots,
% Presets, Parameter, Group by, Color by, X axis) are filled by
% refreshMenus_.
%
% See also: epsych.BehaviorAnalysis.buildUI

f = self.H.figure;

% ---------- File -----------------------------------------------------------
m = uimenu(f, 'Text', '&File');
uimenu(m, 'Text', '&Open Root...', 'Accelerator', 'O', 'MenuSelectedFcn', @(~,~) self.openRoot(""));
self.H.mnu_recent = uimenu(m, 'Text', 'Recent &Roots');
self.H.mnu_rescan = uimenu(m, 'Text', 'Re&scan  (F5)', 'Separator', 'on', ...
    'MenuSelectedFcn', @(~,~) self.rescan());
self.H.mnu_save = uimenu(m, 'Text', '&Save Project', 'Accelerator', 'S', ...
    'MenuSelectedFcn', @(~,~) self.saveProject());
self.H.mnu_export = uimenu(m, 'Text', '&Export Tables...', 'Accelerator', 'E', 'Separator', 'on', ...
    'MenuSelectedFcn', @(~,~) self.exportDialog_());
self.H.mnu_script = uimenu(m, 'Text', '&Generate Script');
uimenu(self.H.mnu_script, 'Text', 'Checked Sessions (Compare)...', 'Accelerator', 'G', ...
    'MenuSelectedFcn', @(~,~) self.scriptMenu_("selected"));
uimenu(self.H.mnu_script, 'Text', 'This Session...', ...
    'MenuSelectedFcn', @(~,~) self.scriptMenu_("session"));
uimenu(self.H.mnu_script, 'Text', 'Every Visible Session...', ...
    'MenuSelectedFcn', @(~,~) self.scriptMenu_("study"));
self.H.mnu_figure = uimenu(m, 'Text', 'Export &Figure...  (Ctrl+Shift+F)', ...
    'MenuSelectedFcn', @(~,~) self.figureMenu_());
uimenu(m, 'Text', '&Close', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) self.onCloseRequest_());

% ---------- Session --------------------------------------------------------
m = uimenu(f, 'Text', '&Session');
self.H.mnu_session = m;
uimenu(m, 'Text', '&Open  (Enter)', 'MenuSelectedFcn', @(~,~) self.sessionAction_("open"));
uimenu(m, 'Text', '&Review Session...', 'Accelerator', 'R', ...
    'MenuSelectedFcn', @(~,~) self.sessionAction_("review"));
uimenu(m, 'Text', '&Hide / Unhide  (Del)', 'Separator', 'on', ...
    'MenuSelectedFcn', @(~,~) self.sessionAction_("hide"));
uimenu(m, 'Text', 'Trial &Window Override...', 'Accelerator', 'W', ...
    'MenuSelectedFcn', @(~,~) self.sessionAction_("window"));
uimenu(m, 'Text', '&Comment...', 'Accelerator', 'N', ...
    'MenuSelectedFcn', @(~,~) self.sessionAction_("comment"));
uimenu(m, 'Text', 'Copy &Path', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) self.sessionAction_("copy"));
uimenu(m, 'Text', 'Show in &Folder', 'MenuSelectedFcn', @(~,~) self.sessionAction_("folder"));

% ---------- Analysis -------------------------------------------------------
m = uimenu(f, 'Text', '&Analysis');
self.H.mnu_analysis = m;
uimenu(m, 'Text', '&Settings...', 'MenuSelectedFcn', @(~,~) self.settingsDialog_());
uimenu(m, 'Text', 'ps&ignifit Settings...', ...
    'MenuSelectedFcn', @(~,~) self.settingsDialog_(Section = "psignifit"));
self.H.mnu_presets = uimenu(m, 'Text', '&Presets');
self.H.mnu_parameter = uimenu(m, 'Text', 'P&arameter');
uimenu(m, 'Text', '&Recompute All', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) self.recomputeAll());
% Background precompute (behavior.Precompute): Now, Automatically, Stop.
self.H.mnu_precompute = uimenu(m, 'Text', 'Pre&compute Fits Now', ...
    'MenuSelectedFcn', @(~,~) self.precomputeFits());
self.H.mnu_autoPrecompute = uimenu(m, 'Text', 'Precompute psignifit Fits &Automatically', ...
    'Checked', matlab.lang.OnOffSwitchState(self.AutoPrecompute_), ...
    'MenuSelectedFcn', @(~,~) self.toggleAutoPrecompute_());
self.H.mnu_stopPrecompute = uimenu(m, 'Text', 'S&top Precomputing', 'Enable', 'off', ...
    'MenuSelectedFcn', @(~,~) self.stopPrecompute());

% ---------- Groups ---------------------------------------------------------
m = uimenu(f, 'Text', '&Groups');
self.H.mnu_groups = m;
uimenu(m, 'Text', '&Manage Groupings...', 'Accelerator', 'M', ...
    'MenuSelectedFcn', @(~,~) self.groupingsDialog_());
self.H.mnu_groupby = uimenu(m, 'Text', '&Group by', 'Separator', 'on');
self.H.mnu_colorby = uimenu(m, 'Text', '&Color by');
self.H.mnu_xaxis = uimenu(m, 'Text', '&X axis');

% ---------- View -----------------------------------------------------------
m = uimenu(f, 'Text', '&View');
keys = ["1" "2" "3" "4" "5"];
for k = 1:numel(self.TAB_NAMES)
    name = self.TAB_NAMES(k);
    uimenu(m, 'Text', char(name), 'Accelerator', char(keys(k)), ...
        'MenuSelectedFcn', @(~,~) self.userShowTab_(name));
end
self.H.mnu_browser = uimenu(m, 'Text', '&Browser', 'Accelerator', 'B', 'Separator', 'on', ...
    'Checked', matlab.lang.OnOffSwitchState(self.BrowserVisible_), ...
    'MenuSelectedFcn', @(~,~) self.toggleBrowser_());
uimenu(m, 'Text', '&Find', 'Accelerator', 'F', 'MenuSelectedFcn', @(~,~) self.find_());
% Every plot also has the item on its own right-click menu.
self.H.mnu_openfig = uimenu(m, 'Text', 'Open Plot in New Fi&gure', 'Separator', 'on');
uimenu(self.H.mnu_openfig, 'Text', '(no plot on this tab yet)', 'Enable', 'off');
m.MenuSelectedFcn = @(~,~) self.fillPlotMenu_();

% ---------- Help -----------------------------------------------------------
m = uimenu(f, 'Text', '&Help');
uimenu(m, 'Text', '&Documentation  (F1)', 'MenuSelectedFcn', @(~,~) self.openDocumentation_());
uimenu(m, 'Text', 'Open &Log Folder', 'MenuSelectedFcn', @(~,~) self.openLogFolder_());

end
