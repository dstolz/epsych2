function UpdateVideoLiveViewUI_(self)
% UpdateVideoLiveViewUI_(self)
% Sync the menu item, the toolbar toggle, and the status-row banner with
% VideoLiveViewActive_, so the session window always states whether a
% displayed webcam stream is also being written to disk.
%
% The toggle's State is always reset here rather than trusted from the
% click: ToggleVideoLiveView can refuse (recording active, setup dialog
% open) or fail, and the pressed look must track the actual view.
%
% The banner collapses by emptying its text rather than by toggling Visible:
% an invisible label still claims its 'fit' column and would leave a gap.
arguments
    self
end

if ~isfield(self.H,'mnu_vlc_liveview') || ~isgraphics(self.H.mnu_vlc_liveview), return, end

if self.VideoLiveViewActive_
    self.H.mnu_vlc_liveview.Text    = 'Close Live Webcam View';
    self.H.mnu_vlc_liveview.Checked = 'on';
    self.H.video_liveview_banner.Text = 'LIVE VIEW - NOT RECORDING';
    self.H.tb_liveview.State   = 'on';
    self.H.tb_liveview.Tooltip = 'Close the live webcam view. Nothing is being recorded.';
else
    self.H.mnu_vlc_liveview.Text    = 'Live Webcam View (No Recording)';
    self.H.mnu_vlc_liveview.Checked = 'off';
    self.H.video_liveview_banner.Text = '';
    self.H.tb_liveview.State   = 'off';
    self.H.tb_liveview.Tooltip = 'Open a display-only webcam view (nothing is recorded). Same as Utilities > Video > Live Webcam View.';
end
