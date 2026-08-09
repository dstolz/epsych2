function StopVideoLiveView_(self)
% StopVideoLiveView_(self)
% Close the display-only webcam view; no-op when none is open. The
% VideoLiveViewActive_ flag guards this so it never closes a run recording or
% a preview owned by the Webcam Recorder Setup dialog, and so repeated calls
% from the several paths that end a live view (toggle, run start, setup
% dialog, window close) are safe.
arguments
    self
end

if ~self.VideoLiveViewActive_, return, end
self.VideoLiveViewActive_ = false;

try
    if ~isempty(self.VlcRecorder_) && isvalid(self.VlcRecorder_)
        self.VlcRecorder_.trigger('Stop');
        % Clear the banner so it cannot reappear over the setup dialog's own
        % VLC preview, which is a different feature with its own labelling.
        self.VlcRecorder_.set_parameter('DisplayBanner','');
        vprintf(0,'Live webcam view closed.')
        self.setStatus('Live webcam view closed.')
    end
catch ME
    vprintf(0,1,ME)
end

self.UpdateVideoLiveViewUI_;
