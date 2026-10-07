function selectSession(self, key)
% selectSession(self, key)
% Show one session: the Session tab draws it, the Subject tab follows its
% subject, and the browser selects its node (when the filter lists it).
% Does not change the tab in front; Session > Open does.
%
% Parameters:
%   key - session key (path relative to the root, "/" separated)
%
% See also: gui.behavior.SessionView.show, gui.behavior.Browser.reveal
arguments
    self
    key (1,1) string
end

if isempty(self.Study)
    return
end
try
    row = self.Study.Catalog.session(key);
catch ME
    self.alert_("Not a session of this root: " + key + " (" + string(ME.message) + ")", ...
        'Select Session', 'warning');
    return
end
key = string(row.Key);
self.Views.Session.show(key);
self.Views.Subject.setSubject(string(row.Subject));
self.Views.Browser.reveal(key);
self.setStatus_(row.FileName + "  ·  " + row.Project + " / " + row.Subject);

end
