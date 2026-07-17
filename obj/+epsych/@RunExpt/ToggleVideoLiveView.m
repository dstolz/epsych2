function ToggleVideoLiveView(self)
% ToggleVideoLiveView(self)
% Open or close a display-only webcam view. VLC uses the same device, frame
% rate, resolution, and crop as a recording would, but runs without a --sout
% chain, so nothing reaches the disk. The VLC window carries a "NOT
% RECORDING" overlay and title, and the session window shows a matching
% banner, so a displayed stream is never mistaken for a recorded one.
%
% Never throws: the view is a convenience, so a failure is reported and the
% session carries on.
%
% See also: epsych.RunExpt.StopVideoLiveView_, hw.VlcRecorder
arguments
    self
end

if self.VideoLiveViewActive_
    self.StopVideoLiveView_;
    return
end

% Both refusals below protect a VLC instance that someone else owns: Play
% relaunches the process, which would end a run's recording or fight the
% setup dialog for the camera.
if self.VideoRecordingActive_
    uialert(self.H.figure1, ...
        ['This run is recording video, and the recording window already shows the live stream. ' ...
         'Stop the run to view the camera without recording.'], ...
        'EPsych','Icon','info');
    return
end

if ~isempty(self.VlcRecorderSetupGUI_) && isvalid(self.VlcRecorderSetupGUI_)
    uialert(self.H.figure1, ...
        ['The Webcam Recorder Setup dialog has the camera open. Close it first, ' ...
         'or use its "Preview in VLC" button.'], ...
        'EPsych','Icon','info');
    return
end

try
    rec = self.getVlcRecorder_();

    % An empty RecordingFile is what makes VLC display-only, so set it here
    % rather than trusting what an earlier run or dialog left behind.
    rec.set_parameter('RecordingFile','');
    rec.set_parameter('DisplayBanner','LIVE VIEW - NOT RECORDING');

    if rec.trigger('Play')
        self.VideoLiveViewActive_ = true;
        vprintf(0,'Live webcam view opened. Video is NOT being recorded.')
    else
        uialert(self.H.figure1, ...
            'Could not open the live webcam view. Check View > Webcam Recorder Setup.', ...
            'EPsych','Icon','error');
        vprintf(0,1,'Live webcam view failed to open.')
    end
catch ME
    vprintf(0,1,ME)
    vprintf(0,1,'Live webcam view failed to open.')
end

self.UpdateVideoLiveViewUI_;
