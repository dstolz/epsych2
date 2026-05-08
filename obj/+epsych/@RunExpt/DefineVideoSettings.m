function DefineVideoSettings(self)
% obj.DefineVideoSettings
% Allow the user to configure VLC and webcam/video defaults.
fig = findall(groot,'Type','figure','-and','Tag','RunExptVideoSettings');
if ~isempty(fig) && isgraphics(fig(1))
    fig = fig(1);
    fig.Visible = 'on';
    movegui(fig,'onscreen');
    return
end

cfg = struct();
cfg.VlcExePath   = getpref('ep_RunExpt_Video','VlcExePath', 'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe');
cfg.DeviceName   = getpref('ep_RunExpt_Video','DeviceName', 'Integrated Camera');
cfg.MediaFile    = getpref('ep_RunExpt_Video','MediaFile', 'dshow://');
cfg.RecordingDir = getpref('ep_RunExpt_Video','RecordingDir', self.dfltDataPath);

fig = uifigure('Name','EPsych Video Settings', ...
    'Tag','RunExptVideoSettings', ...
    'Position',[200 200 640 340], ...
    'Resize','off');
movegui(fig,'center');

grid = uigridlayout(fig,[5 4]);
grid.RowHeight = repmat({'fit'},1,5);
grid.ColumnWidth = {150,'1x',80,80};
grid.Padding = [16 16 16 16];
grid.RowSpacing = 14;
grid.ColumnSpacing = 10;

uilabel(grid,'Text','VLC executable path:','HorizontalAlignment','right', ...
    'Layout',[1 1]);
txtVlc = uieditfield(grid,'text', ...
    'Value',cfg.VlcExePath, ...
    'Layout',[1 2 1 2]);
btnBrowseVlc = uibutton(grid,'push', ...
    'Text','Browse...', ...
    'Layout',[1 4], ...
    'ButtonPushedFcn', @(~,~) browseVlc());

uilabel(grid,'Text','Preferred capture device:','HorizontalAlignment','right', ...
    'Layout',[2 1]);
txtDevice = uieditfield(grid,'text', ...
    'Value',cfg.DeviceName, ...
    'Layout',[2 2 1 2]);
btnSelectDevice = uibutton(grid,'push', ...
    'Text','Select...', ...
    'Layout',[2 4], ...
    'ButtonPushedFcn', @(~,~) selectDevice());

uilabel(grid,'Text','Default recording directory:','HorizontalAlignment','right', ...
    'Layout',[3 1]);
txtDir = uieditfield(grid,'text', ...
    'Value',cfg.RecordingDir, ...
    'Layout',[3 2 1 2]);
btnBrowseDir = uibutton(grid,'push', ...
    'Text','Browse...', ...
    'Layout',[3 4], ...
    'ButtonPushedFcn', @(~,~) browseDir());

uilabel(grid,'Text','VLC media URI:','HorizontalAlignment','right', ...
    'Layout',[4 1]);
txtMedia = uieditfield(grid,'text', ...
    'Value',cfg.MediaFile, ...
    'Layout',[4 2 1 3]);

btnSave = uibutton(grid,'push', ...
    'Text','Save', ...
    'Layout',[5 3], ...
    'ButtonPushedFcn', @(~,~) saveAndClose());
uibutton(grid,'push', ...
    'Text','Cancel', ...
    'Layout',[5 4], ...
    'ButtonPushedFcn', @(~,~) delete(fig));

    function browseVlc()
        [fname, fdir] = uigetfile({'vlc.exe','VLC Executable (vlc.exe)'; '*.*','All files'}, 'Locate vlc.exe', char(txtVlc.Value));
        if isequal(fname,0), return; end
        txtVlc.Value = string(fullfile(fdir,fname));
    end

    function selectDevice()
        rec = hw.VlcRecorder();
        if strlength(txtDevice.Value) > 0
            rec.set_parameter('DeviceName', txtDevice.Value);
        end
        selected = rec.selectDevice();
        if strlength(selected) > 0
            txtDevice.Value = selected;
        end
    end

    function browseDir()
        ontop = self.AlwaysOnTop(false);
        pth = uigetdir(char(txtDir.Value), 'Select Default Webcam Recording Directory');
        self.AlwaysOnTop(ontop);
        if isequal(pth,0), return; end
        txtDir.Value = string(pth);
    end

    function saveAndClose()
        vlcPath = string(txtVlc.Value);
        deviceName = string(txtDevice.Value);
        mediaFile = string(txtMedia.Value);
        recordingDir = string(txtDir.Value);

        if strlength(vlcPath) == 0 || ~isfile(vlcPath)
            uialert(fig, 'Please choose a valid vlc.exe path.', 'Invalid VLC path', 'Icon','warning');
            return
        end
        if strlength(deviceName) == 0
            uialert(fig, 'Please enter a preferred capture device name.', 'Invalid Device', 'Icon','warning');
            return
        end
        if strlength(mediaFile) == 0
            uialert(fig, 'Please enter a valid VLC media URI.', 'Invalid URI', 'Icon','warning');
            return
        end
        if strlength(recordingDir) == 0 || ~isfolder(recordingDir)
            uialert(fig, 'Please choose a valid default recording directory.', 'Invalid Directory', 'Icon','warning');
            return
        end

        setpref('ep_RunExpt_Video','VlcExePath', vlcPath);
        setpref('ep_RunExpt_Video','DeviceName', deviceName);
        setpref('ep_RunExpt_Video','MediaFile', mediaFile);
        setpref('ep_RunExpt_Video','RecordingDir', recordingDir);
        delete(fig);
    end
end
