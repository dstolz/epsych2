function updateRegistryView_(self)
% updateRegistryView_(self)
% Show, hide and label everything the lab's subject registry adds here.
%
% Called from refresh, so a registry switched on or off in RunExpt's Customize
% dialog while this window is open appears or disappears at the next refresh.
% With no registry set up, every piece stays hidden and takes no space: the
% window is the one it was before the registry existed. The lamp's text is the
% registry's own status (cheap by contract -- no network), and it opens the
% registry's settings window, where a record that needs a person is resolved.
%
% See also: epsych.SubjectRegistry, gui.SubjectManager.registryAction_

if ~isfield(self.H, 'btnRegistry') || ~isgraphics(self.H.btnRegistry), return, end

reg = epsych.SubjectRegistry.current();
on = reg.isEnabled();
onoff = @(tf) matlab.lang.OnOffSwitchState(tf);

self.H.btnRegistry.Visible = onoff(on);
self.H.mnu_registry.Visible = onoff(on);
self.H.cmnu_reg_link.Visible = onoff(on);
if ~on
    self.H.rosterGrid.ColumnWidth{2} = 0;
    return
end
self.H.rosterGrid.ColumnWidth{2} = 'fit';

label = char(reg.label());
self.H.mnu_registry.Text = label;
self.H.cmnu_reg_link.Text = sprintf('Link to %s Subject...', label);

try
    st = reg.status();
catch ME
    vprintf(0, 1, ME);
    st = epsych.SubjectRegistry.blankStatus();
    st.State = "attention";
    st.Message = string(ME.message);
end

txt = sprintf('%s: %s', label, st.State);
if st.NeedYou > 0
    txt = sprintf('%s %s %d need you', txt, char(183), st.NeedYou);
elseif st.Pending > 0
    txt = sprintf('%s %s %d to send', txt, char(183), st.Pending);
end
self.H.btnRegistry.Text = txt;
tip = sprintf(['%s is %s. Records of sessions and weighings wait on this computer ' ...
    'and are sent when it answers; a session never waits for it.'], label, st.State);
if st.Message ~= ""
    tip = sprintf('%s\n%s', tip, st.Message);
end
self.H.btnRegistry.Tooltip = [tip newline 'Click for its settings.'];
if st.NeedYou > 0 || st.State == "attention"
    self.H.btnRegistry.FontColor = [0.75 0.10 0.10];
elseif st.State == "offline"
    self.H.btnRegistry.FontColor = [0.70 0.40 0.05];
else
    self.H.btnRegistry.FontColor = [0.15 0.45 0.20];
end

% What each item needs: a writable roster to link or import into, and a
% project to import into or retire from.
hasRoster = ~isempty(self.Roster) && isvalid(self.Roster);
writable = hasRoster && self.Roster.IsBound && self.Roster.IsWritable && ~self.Roster.IsReadOnly;
inProject = ~isempty(self.selectedProject_());
self.H.mnu_reg_link.Enable = onoff(writable);
self.H.mnu_reg_unlink.Enable = onoff(writable);
self.H.cmnu_reg_link.Enable = onoff(writable);
self.H.mnu_reg_import.Enable = onoff(writable && inProject);
self.H.mnu_reg_link_project.Enable = onoff(writable && inProject);
self.H.mnu_reg_retire.Enable = onoff(writable && inProject);
end
