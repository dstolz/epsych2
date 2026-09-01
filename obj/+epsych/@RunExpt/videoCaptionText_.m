function txt = videoCaptionText_(self, recordingFile)
% txt = videoCaptionText_(self, recordingFile)
% Resolve the webcam recorder's caption template against this session.
%
% The recorder holds the template (the operator's, edited in View > Webcam
% Recorder Setup and remembered in the 'ep_RunExpt_Video' preferences); this
% fills in what only a session knows. Returns "" when captions are off or the
% template is empty, which leaves the recording unmarked.
%
% {subject} and {box} name the FIRST subject, the same one the recording file
% is named after (see StartVideoRecording_), so a caption can never disagree
% with the filename it accompanies; {subjects} lists them all for a rig running
% several boxes past one camera.
%
% Never throws: a caption is decoration on a recording, and a run must not fail
% for want of one. A failure logs and yields "".
%
% Parameters:
%   self          - epsych.RunExpt
%   recordingFile - full path of the recording, for {file}
%
% Returns:
%   txt - the expanded caption (string), or "" for none
%
% See also: hw.VlcRecorder.expandCaption, epsych.RunExpt.StartVideoRecording_

arguments
    self
    recordingFile (1,:) char = ''
end

txt = "";

try
    rec = self.getVlcRecorder_();
    if ~logical(rec.get_parameter('EnableCaption')), return, end

    template = string(rec.get_parameter('CaptionTemplate'));
    if strlength(strtrim(template)) == 0, return, end

    tokens = struct();
    tokens.File = string(recordingFile);

    % The session start, not the moment recording began: an operator who stops
    % and restarts the camera mid-session gets segments that agree on when the
    % session began. StartTime defaults to NaT, so test it with isnat -- a NaT
    % datetime is never empty, and expandCaption would format it as "NaT".
    if ~isempty(self.RUNTIME) && isvalid(self.RUNTIME) && ~isnat(self.RUNTIME.StartTime)
        tokens.When = self.RUNTIME.StartTime;
    end

    if ~isempty(self.CONFIG) && isa(self.CONFIG(1).SUBJECT, 'epsych.Subject')
        names = arrayfun(@(c) string(c.SUBJECT.Name), self.CONFIG);
        tokens.Subject  = names(1);
        tokens.Subjects = names;
        tokens.Box      = string(self.CONFIG(1).SUBJECT.BoxID);
    end

    txt = hw.VlcRecorder.expandCaption(template, tokens);
catch ME
    vprintf(0, 1, ME)
    vprintf(1, 'Could not build the video caption; recording without one.')
    txt = "";
end

end
