function StartVideoRecording_(self)
% StartVideoRecording_(self)
% Begin the per-run webcam recording when enabled via the "Record video"
% checkbox / 'EnableRecording' preference. Never throws: a failed recording
% is reported via vprintf and the run proceeds without video — the
% experiment matters more than the camera.
arguments
    self
end

% A run without recording leaves any live view alone, so the operator can
% still watch the camera through the session.
if ~getpref('ep_RunExpt_Video','EnableRecording',false), return, end

% Recording relaunches VLC, which would silently take down a live view and
% leave the window claiming one is open.
if self.VideoLiveViewActive_
    vprintf(0,'Closing the live webcam view; this run records the camera instead.')
    self.StopVideoLiveView_;
end

try
    root = strtrim(char(getpref('ep_RunExpt_Video','RecordingRootDir','')));
    if isempty(root)
        root = char(self.dfltDataPath);
        vprintf(0,'No Video Recording Path set (Customize > Paths); recording under Data Save Path "%s"',root)
    end

    % Name the recording after subject 1's reserved data file so the video and
    % the .mat it accompanies can be paired by name.
    ffn = epsych.RunExpt.videoRecordingFilename(root, self.RUNTIME.SessionDataFilename(1));

    rec = self.getVlcRecorder_();
    rec.set_parameter('RecordingFile', ffn);

    if rec.trigger('Play')
        self.VideoRecordingActive_ = true;
        vprintf(0,'Video recording started: %s',ffn)
        [~,vfn,vext] = fileparts(ffn);
        self.setStatus(sprintf('Video recording started: %s%s',vfn,vext))
    else
        vprintf(0,1,'Video recording failed to start; continuing without video. Check View > Webcam Recorder Setup.')
        self.setStatus('Video recording failed to start; the session continues without video.', ...
            'check View > Webcam Recorder Setup.')
    end
catch ME
    vprintf(0,1,ME)
    vprintf(0,1,'Video recording failed to start; continuing without video.')
    self.setStatus('Video recording failed to start; the session continues without video.')
end
