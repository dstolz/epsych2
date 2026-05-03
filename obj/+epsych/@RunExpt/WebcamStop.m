function WebcamStop(self)
% WebcamStop(self)
% Stop the active webcam recording and close the VLC preview window.
%
% Sends Stop trigger to hw.VlcRecorder (finalises the recording file and
% closes VLC), then disconnects and clears the recorder object.
% Menu item state is restored: "Webcam Preview / Record..." is re-enabled
% and "Stop Webcam" is disabled.

if isempty(self.vlcRecorder_) || ~isvalid(self.vlcRecorder_)
    self.vlcRecorder_ = [];
    return
end

try
    self.vlcRecorder_.trigger('Stop');
    self.vlcRecorder_.disconnect();
catch ME
    vprintf(0, 1, ME);
end

self.vlcRecorder_ = [];

% Restore menu state if handles are still valid.
if isfield(self.H, 'mnu_webcam_record') && isgraphics(self.H.mnu_webcam_record)
    self.H.mnu_webcam_record.Enable = 'on';
end
if isfield(self.H, 'mnu_webcam_stop') && isgraphics(self.H.mnu_webcam_stop)
    self.H.mnu_webcam_stop.Enable = 'off';
end

vprintf(2, 'epsych.RunExpt: webcam stopped.');
