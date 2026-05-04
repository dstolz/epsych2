function WebcamRecord(self)
% WebcamRecord(self)
% Launch a webcam preview window and optionally begin recording to a file.
%
% Workflow:
%   1. If a webcam session is already active, prompt to stop it first.
%   2. Ask the user to select the capture device (via hw.VlcRecorder.selectDevice).
%   3. Immediately start VLC showing the live webcam feed (no recording yet).
%   4. Show a file-save dialog to choose the recording output path.
%   5. If a file is chosen, begin recording; otherwise leave as preview-only.
%
% Menu item state is updated: "Webcam Preview / Record..." is disabled and
% "Stop Webcam" is enabled while any webcam session is active.

% --- Guard: stop existing session first --------------------------------
if ~isempty(self.vlcRecorder_) && isvalid(self.vlcRecorder_) && self.vlcRecorder_.IsConnected
    b = questdlg('A webcam session is already active. Stop it and start a new one?', ...
        'Webcam', 'Yes', 'Cancel', 'Cancel');
    if ~strcmp(b, 'Yes')
        return
    end
    self.WebcamStop();
end

% --- Create and connect recorder ---------------------------------------
rec = hw.VlcRecorder();
rec.connect();

% --- Device selection --------------------------------------------------
% selectDevice shows a listdlg and stores the chosen name on the object.
% If the user cancels, the current default ("Integrated Camera") is kept.
rec.selectDevice();

% Set MediaFile to the DirectShow URI so VLC knows the source protocol.
rec.set_parameter('MediaFile', 'dshow://');

% --- Launch VLC preview (no recording file yet) ------------------------
rec.trigger('Play');

% --- Ask for recording output file (while VLC is opening) --------------
[fname, fdir] = uiputfile( ...
    {'*.ts','MPEG-TS (*.ts)'; '*.mp4','MP4 (*.mp4)'; '*.*','All files'}, ...
    'Save Recording As (cancel for preview-only)', ...
    fullfile(self.dfltDataPath, 'webcam_recording.ts'));

if ~isequal(fname, 0)
    outFile = fullfile(fdir, fname);
    rec.set_parameter('RecordingFile', outFile);
    rec.trigger('StartRecord');
    vprintf(2, 'epsych.RunExpt: webcam recording started → %s', outFile);
    stopLabel = 'Stop Webcam (Recording)';
else
    vprintf(2, 'epsych.RunExpt: webcam preview started (no recording file selected)');
    stopLabel = 'Stop Webcam (Preview)';
end

% --- Store recorder and update menu state ------------------------------
self.vlcRecorder_ = rec;
self.H.mnu_webcam_record.Enable = 'off';
self.H.mnu_webcam_stop.Label    = stopLabel;
self.H.mnu_webcam_stop.Enable   = 'on';
