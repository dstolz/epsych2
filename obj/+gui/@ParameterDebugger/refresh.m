function refresh(self)
% refresh(self)
% Rebuild the source list and the parameter table from the current state of
% the session.
%
% This is a full rebuild, not an update: parameter objects are replaced
% wholesale when a config is loaded or a protocol is recompiled, so anything
% held from before would be a handle to an object nothing else refers to any
% more. The cost of rebuilding is a table redraw, and it happens only when the
% operator changes what is listed.
%
% Everything read so far is discarded with the old rows, which is deliberate:
% a value read from a protocol that has since been reloaded is not evidence
% about the one now in front of the operator.
%
% See also: gui.ParameterDebugger, gui.ParameterDebugger.readRows
arguments
    self
end

if ~isfield(self.H,'table') || ~isgraphics(self.H.table), return, end

self.Refreshing_ = true;
restore = onCleanup(@() self.clearRefreshing_());

% ---------- Sources -----------------------------------------------------
self.Sources_ = self.resolveSources_();

if isempty(self.Sources_)
    self.H.source.Items = {'(none)'};
    self.H.source.Enable = 'off';
else
    labels = {self.Sources_.Label};
    self.H.source.Items = labels;
    self.H.source.Enable = 'on';

    % Keep the operator on the source they chose. The label carries a " - live"
    % marker that appears the moment a run starts, so the match is on the
    % subject prefix rather than on the whole string.
    idx = localMatchSource(labels, self.LastSource_);
    self.H.source.Value = labels{idx};
    self.LastSource_ = labels{idx};
end

% ---------- Rows --------------------------------------------------------
interfaces = hw.Interface.empty(1,0);
if ~isempty(self.Sources_)
    pick = find(strcmp({self.Sources_.Label}, self.H.source.Value), 1);
    if ~isempty(pick)
        interfaces = self.Sources_(pick).Interfaces;
    end
end

self.Interfaces_ = interfaces;
self.buildRows_(interfaces, self.H.filter.Value);

% ---------- Table -------------------------------------------------------
n = numel(self.Rows);
data = cell(n, 8);
for i = 1:n
    R = self.Rows(i);
    data(i,:) = {R.Where, R.Name, R.Type, R.Access, R.ValueText, R.Unit, R.Flags, R.Note};
end

self.H.table.Data = data;
self.applyStyles_();

hasRows = n > 0;
self.H.table.Visible = matlab.lang.OnOffSwitchState(hasRows);
self.H.emptyState.Visible = matlab.lang.OnOffSwitchState(~hasRows);
if ~hasRows
    self.H.emptyState.Text = localEmptyText(self, interfaces);
end

self.updateCountLabel_();

clear restore
self.updateEnableStates_();

if hasRows
    self.setStatus_(sprintf(['%d parameter(s) listed. Double-click a name to read one, ' ...
        'or Read All (F5).'], n));
end

end


% -----------------------------------------------------------------------
function idx = localMatchSource(labels, wanted)
% Index of the previously selected source, matched on the part of the label
% before the live marker so a run starting does not reset the selection.
idx = 1;
if isempty(wanted), return, end

hit = find(strcmp(labels, wanted), 1);
if ~isempty(hit)
    idx = hit;
    return
end

stem = @(s) strtrim(extractBefore([s ' - live'], ' - live'));
wantedStem = stem(wanted);
hit = find(cellfun(@(s) isequal(stem(s), wantedStem), labels), 1);
if ~isempty(hit)
    idx = hit;
end
end


function txt = localEmptyText(self, interfaces)
% Why the table is empty, in the operator's terms. The three cases are worth
% distinguishing: no protocol at all, a protocol whose parameters are all
% hidden or filtered out, and a protocol that genuinely defines none.
if isempty(interfaces)
    if isempty(self.Sources_)
        txt = ['No protocol is loaded. Load a configuration in the session window, ' ...
               'or open this window against a protocol directly.'];
    else
        txt = 'The selected protocol has no hardware interfaces.';
    end
    return
end

if ~isempty(strtrim(self.H.filter.Value))
    txt = sprintf('No parameter matches "%s". Clear the Find box to see them all.', ...
        strtrim(self.H.filter.Value));
elseif ~self.H.chkHidden.Value
    txt = ['No visible parameters. Tick "Show hidden" if this protocol keeps ' ...
           'its parameters out of the GUI.'];
else
    txt = 'This protocol defines no parameters.';
end
end
