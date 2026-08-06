function StopVideoRecording_(self)
% StopVideoRecording_(self)
% Finalize the run recording; no-op when none is active. The
% VideoRecordingActive_ flag guards this so run teardown never closes an
% operator preview opened from the Webcam Recorder Setup dialog, and so
% repeated calls from multiple end paths (Stop, auto-stop, error, close) are
% safe.
arguments
    self
end

if ~self.VideoRecordingActive_, return, end
self.VideoRecordingActive_ = false;

try
    if ~isempty(self.VlcRecorder_) && isvalid(self.VlcRecorder_)
        self.VlcRecorder_.trigger('Stop');
        % Clear the target so a later display-only Play cannot clobber the finished file.
        self.VlcRecorder_.set_parameter('RecordingFile','');
        vprintf(0,'Video recording stopped.')
        self.setStatus('Video recording stopped.')
    end
catch ME
    vprintf(0,1,ME)
end
