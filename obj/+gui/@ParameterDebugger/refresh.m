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

% A read sweep holds the same flag for its whole duration. Rebuilding Rows
% underneath it would leave the indices that sweep is iterating pointing at
% different parameters, so the rebuild is dropped rather than interleaved --
% Ctrl+R during a long sweep does nothing, and works the moment it ends.
if self.Refreshing_, return, end

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

% The Find box narrows what is listed, and it is the operator's, not the
% session's: a rebuild keeps it, so a refresh in the middle of a search does
% not put two hundred rows back in front of them.
self.markFilterValid_(true);
self.buildRows_(interfaces);
self.renderTable_();

clear restore
self.updateEnableStates_();

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

