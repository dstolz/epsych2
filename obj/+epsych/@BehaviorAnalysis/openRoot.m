function ok = openRoot(self, root, options)
% ok = openRoot(self, root)
% ok = openRoot(self, root, Store = folder)
% Open a data root in the window: a behavior.Study over it, the views over
% the Study, and a scan (refused while a session is running).
%
% root "" asks for a folder (only when the window is shown). Opening another
% root while this one has unsaved changes asks Save / Discard / Cancel
% first. The root is remembered in RecentRoots and LastRoot; a Store given,
% or one remembered for this root (AlternateStores), keeps the project file
% outside the root.
%
% Parameters:
%   root  - data root folder
%   Store - alternate project store folder ("" = remembered, else
%           <root>/EPsych_Analysis)
%   Force - skip the unsaved-changes question (the caller asked it)
%
% Returns:
%   ok - the root is open (its scan may still have been refused)
%
% See also: epsych.BehaviorAnalysis, behavior.Study
arguments
    self
    root (1,1) string = ""
    options.Store (1,1) string = ""
    options.Force (1,1) logical = false
end

ok = false;
if root == ""
    if ~self.isVisible_()
        return
    end
    start = string(self.getPref_('LastRoot', ""));
    if start == "" || ~isfolder(start), start = string(pwd); end
    d = uigetdir(char(start), 'Choose a data root (<Project>/<Subject>/<sessions>.mat)');
    figure(self.H.figure);
    if isequal(d, 0), return, end
    root = string(d);
end
if ~isfolder(root)
    self.alert_("There is no folder " + root + ".", 'Open Root', 'warning');
    return
end

if ~options.Force && ~self.confirmDiscard_('Open Root')
    return
end

store = options.Store;
if store == ""
    A = self.alternateStores_();
    i = find(strcmp(epsych.BehaviorAnalysis.normKey([A.Root]), ...
        epsych.BehaviorAnalysis.normKey(string(localAbsolute(root)))), 1);
    if ~isempty(i) && isfolder(A(i).Store)
        store = A(i).Store;
    end
end

try
    S = behavior.Study(root, Store = store, Roster = self.Roster_, Scan = false, ...
        CacheFolder = self.CacheFolder_);
catch ME
    vprintf(0, 1, ME);
    self.alert_("This root could not be opened: " + string(ME.message), 'Open Root', 'error');
    return
end

self.releaseStudy_();
self.StoreProblem_ = "";
self.BarDismissed_ = "";
self.attachStudy_(S);
self.rememberRoot_(S.Root);
ok = true;

self.rescan();
self.refreshHeader_();
self.setStatus_(sprintf("Opened %s: %d session(s). %s", S.Root, height(S.Catalog.Sessions), ...
    S.Project.summary()));

end


function p = localAbsolute(p)
% The root as behavior.Catalog spells it: absolute, no trailing separator.
p = char(p);
if ~(startsWith(p, filesep) || (numel(p) > 1 && p(2) == ':'))
    p = fullfile(pwd, p);
end
while numel(p) > 3 && any(p(end) == '/\')
    p(end) = [];
end
end
