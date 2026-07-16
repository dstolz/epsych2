function StartVideoRecording_(self)
% StartVideoRecording_(self)
% Begin the per-run webcam recording when enabled via the "Record video"
% checkbox / 'EnableRecording' preference. Never throws: a failed recording
% is reported via vprintf and the run proceeds without video — the
% experiment matters more than the camera.
arguments
    self
end

if ~getpref('ep_RunExpt_Video','EnableRecording',false), return, end

try
    root = strtrim(char(getpref('ep_RunExpt_Video','RecordingRootDir','')));
    if isempty(root)
        root = char(self.dfltDataPath);
        vprintf(0,'No Video Recording Path set (Customize > Paths); recording under Data Save Path "%s"',root)
    end

    ffn = epsych.RunExpt.videoRecordingFilename(root, string(self.CONFIG(1).SUBJECT.Name));

    rec = self.getVlcRecorder_();
    rec.set_parameter('RecordingFile', ffn);

    if rec.trigger('Play')
        self.VideoRecordingActive_ = true;
        vprintf(0,'Video recording started: %s',ffn)
    else
        vprintf(0,1,'Video recording failed to start; continuing without video. Check View > Webcam Recorder Setup.')
    end
catch ME
    vprintf(0,1,ME)
    vprintf(0,1,'Video recording failed to start; continuing without video.')
end
