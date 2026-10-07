function showTab(self, name)
% showTab(self, name)
% Bring a tab forward: "Session", "Subject", "Compare" or "Table". A tab
% that was behind redraws now if anything changed meanwhile.
%
% See also: epsych.BehaviorAnalysis
arguments
    self
    name (1,1) string {mustBeMember(name, ["Session" "Subject" "Compare" "Table"])}
end

self.H.tabs.SelectedTab = self.H.tab.(name);
self.activateTab_(name);

end
