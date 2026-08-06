function UpdateVideoLiveViewUI_(self)
% UpdateVideoLiveViewUI_(self)
% Sync the View menu item and the bottom-bar banner with
% VideoLiveViewActive_, so the session window always states whether a
% displayed webcam stream is also being written to disk.
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
    self.H.setup_btn_liveview.Text = 'Close Live View';
    self.H.setup_btn_liveview.BackgroundColor = [0.85 0.45 0.00];
    self.H.setup_btn_liveview.FontColor = 'w';
else
    self.H.mnu_vlc_liveview.Text    = 'Live Webcam View (No Recording)';
    self.H.mnu_vlc_liveview.Checked = 'off';
    self.H.video_liveview_banner.Text = '';
    self.H.setup_btn_liveview.Text = 'Live View';
    self.H.setup_btn_liveview.BackgroundColor = self.H.liveviewBtnDefaultColor;
    self.H.setup_btn_liveview.FontColor = 'k';
end
