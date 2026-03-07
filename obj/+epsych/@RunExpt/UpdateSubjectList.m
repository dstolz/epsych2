function UpdateSubjectList(self)
% UpdateSubjectList — Populate the subject uitable and controls.
% Behavior
%   Reflects CONFIG contents in the table and toggles action buttons.
arguments
    self
end
if self.STATE >= PRGMSTATE.RUNNING, return, end

if isempty(self.CONFIG) || isempty(self.CONFIG(1).SUBJECT)
    set(self.H.subject_list,'data',[])
    set([self.H.setup_remove_subject self.H.view_trials],'Enable','off')
    return
end

for i = 1:length(self.CONFIG)
    data(i,1) = {self.CONFIG(i).SUBJECT.BoxID}; %#ok<AGROW>
    data(i,2) = {self.CONFIG(i).SUBJECT.Name};  %#ok<AGROW>
    [~,fn,~] = fileparts(self.CONFIG(i).protocol_fn);
    data(i,3) = {char(fn)}; %#ok<AGROW>
end
set(self.H.subject_list,'Data',data)

if size(data,1) == 0
    set([self.H.setup_remove_subject self.H.view_trials],'Enable','off')
else
    set([self.H.setup_remove_subject self.H.edit_protocol self.H.view_trials],'Enable','on')
end
