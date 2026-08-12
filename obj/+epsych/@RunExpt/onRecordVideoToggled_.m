function onRecordVideoToggled_(self, enable)
% onRecordVideoToggled_(self, enable)
% Handle the "Record video" toolbar toggle.
%
% The toggle is the recording opt-in for the next run ('EnableRecording'
% preference), and while a session is already RUNNING it also starts or stops
% the recording immediately: an operator who decides mid-session that a
% subject is worth filming should not have to end the run to get video.
%
% A mid-run recording is named from the data filename reserved at dispatch
% (RUNTIME.SessionDataFilename), so it pairs with the .mat by name exactly as
% a run-start recording does.
%
% Preview never records. The preference is still stored, so the next real Run
% picks it up, but nothing is launched.
%
% Parameters:
%	enable	- New toggle state; true = record.
%
% See also: epsych.RunExpt.StartVideoRecording_, epsych.RunExpt.StopVideoRecording_
arguments
    self
    enable (1,1) logical
end

setpref('ep_RunExpt_Video','EnableRecording',enable);

if self.STATE ~= PRGMSTATE.RUNNING, return, end

if self.RUNTIME.isTest
    if enable
        self.setStatus('Preview runs never record video.','video will record on the next Run.')
    end
    return
end

if enable
    % StartVideoRecording_ re-reads the preference set above, closes any live
    % view, and reports its own success or failure without throwing.
    if self.VideoRecordingActive_, return, end
    self.StartVideoRecording_
else
    self.StopVideoRecording_
end
