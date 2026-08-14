function StartVideoRecording_(self)
% StartVideoRecording_(self)
% Begin the per-run webcam recording when enabled via the "Record video"
% toolbar toggle / 'EnableRecording' preference. Called at run start, and
% again whenever the toggle is pressed mid-session. Never throws: a failed
% recording is reported via vprintf and the run proceeds without video — the
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

% The name comes from the filename ExptDispatch reserved for subject 1, which
% only exists once a run has been prepared.
if isempty(self.RUNTIME.SessionDataFilename)
    vprintf(0,1,'No data filename has been reserved yet; video recording starts with the run.')
    self.setStatus('Video recording starts with the run.','press Run to begin.')
    return
end

try
    % PATHS is the session's value: the rig preference unless the project whose
    % subjects are in this session named its own.
    root = strtrim(char(self.PATHS.VideoRootDir));
    if isempty(root)
        root = char(self.dfltDataPath);
        vprintf(0,'No Video Recording Path set (project > Session Defaults); recording under Data Save Path "%s"',root)
    end

    % Name the recording after subject 1's reserved data file so the video and
    % the .mat it accompanies can be paired by name.
    ffn = epsych.RunExpt.videoRecordingFilename(root, self.RUNTIME.SessionDataFilename(1));
    ffn = localNextSegment(ffn);

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

end

% -----------------------------------------------------------------------
function ffn = localNextSegment(ffn)
% Free path for this recording. Normally the name derived from the data file
% is unused; it is not when the operator stops and restarts recording within
% one session, and reusing it there would overwrite the segment already
% finalized on disk. Later segments get a -2, -3 suffix, so the data filename
% stays the prefix and the pairing survives.
if ~isfile(ffn), return, end

[pn,name,ext] = fileparts(ffn);
n = 1;
candidate = ffn;
while isfile(candidate)
    n = n + 1;
    candidate = fullfile(pn, sprintf('%s-%d%s', name, n, ext));
end

vprintf(0,'Recording "%s%s" already exists; this segment is "%s-%d%s".',name,ext,name,n,ext)
ffn = char(candidate);
end
