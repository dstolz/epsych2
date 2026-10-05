function changed = applyRecordVideo_(self, tf)
% changed = applyRecordVideo_(self, tf)
% Set this session's webcam-recording choice, and the toggle that shows it.
%
% The roster's door onto the Record Video toggle: adding subjects whose
% memberships say whether they are filmed lands here
% (epsych.SubjectRoster.assignToSession). Unlike pressing the toggle
% (onRecordVideoToggled_), this never writes the 'EnableRecording'
% preference -- a subject's setting is that subject's, and must not become the
% rig's default for whoever runs next.
%
% Setting the toggle's State programmatically does not fire its
% ClickedCallback, so nothing here can start or stop a recording; the roster
% refuses to change subjects during a run anyway, and the choice takes effect
% at the next Run (StartVideoRecording_).
%
% Parameters:
%	tf	- true to record this session's runs.
%
% Returns:
%	changed	- true when the session's choice was different before.
%
% See also: epsych.RunExpt.onRecordVideoToggled_, epsych.RunExpt.StartVideoRecording_
arguments
    self
    tf (1,1) logical
end

changed = self.RecordVideo ~= tf;
self.RecordVideo = tf;

if isgraphics(self.H.setup_record_video)
    self.H.setup_record_video.State = tf;
end
end
