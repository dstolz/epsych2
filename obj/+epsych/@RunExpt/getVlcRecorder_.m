function rec = getVlcRecorder_(self)
% rec = getVlcRecorder_(self)
% Lazily create the session-shared hw.VlcRecorder, seeded from the
% 'ep_RunExpt_Video' preference group so values applied in a previous
% session (including from the Webcam Recorder Setup dialog) round-trip.
% Shared by OpenVlcRecorderSetup and StartVideoRecording_ so Apply in the
% setup dialog always affects the recorder used at run time.
arguments
    self
end

if isempty(self.VlcRecorder_) || ~isvalid(self.VlcRecorder_)
    rec = hw.VlcRecorder();
    rec.set_parameter('VlcExePath', getpref('ep_RunExpt_Video','VlcExePath', char(rec.get_parameter('VlcExePath'))));
    rec.set_parameter('DeviceName', getpref('ep_RunExpt_Video','DeviceName', char(rec.get_parameter('DeviceName'))));
    rec.set_parameter('MediaFile',  getpref('ep_RunExpt_Video','MediaFile',  char(rec.get_parameter('MediaFile'))));
    rec.set_parameter('FrameRate',  getpref('ep_RunExpt_Video','FrameRate',  rec.get_parameter('FrameRate')));
    rec.set_parameter('Resolution', getpref('ep_RunExpt_Video','Resolution', rec.get_parameter('Resolution')));
    rec.set_parameter('CropTop',    getpref('ep_RunExpt_Video','CropTop',    rec.get_parameter('CropTop')));
    rec.set_parameter('CropBottom', getpref('ep_RunExpt_Video','CropBottom', rec.get_parameter('CropBottom')));
    rec.set_parameter('CropLeft',   getpref('ep_RunExpt_Video','CropLeft',   rec.get_parameter('CropLeft')));
    rec.set_parameter('CropRight',  getpref('ep_RunExpt_Video','CropRight',  rec.get_parameter('CropRight')));
    self.VlcRecorder_ = rec;
end

rec = self.VlcRecorder_;
