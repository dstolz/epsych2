classdef VlcRecorderSetup < handle
    % g = gui.VlcRecorderSetup(Recorder, Name=Value,...)
    % Configure hw.VlcRecorder capture parameters (device, frame rate,
    % resolution, crop) and VLC window options (minimal interface, always on
    % top) against a live MATLAB webcam preview.
    %
    % A MATLAB `webcam` feed is shown in an axes with an interactive
    % `images.roi.Rectangle` overlay defining the crop region. Device,
    % resolution, frame rate, and crop fields stay in sync with the ROI.
    % Changes are staged locally; click Apply (or OK) to push them to the
    % recorder via its public set_parameter API.
    %
    % VLC holds the DirectShow camera exclusively, so this GUI stops the
    % recorder (trigger('Stop')) before opening the MATLAB webcam, and
    % releases the webcam before any "Preview in VLC" verification.
    %
    % CONSTRUCTOR
    %   g = gui.VlcRecorderSetup(Recorder)
    %   g = gui.VlcRecorderSetup(Recorder, Name=Value,...)
    %
    % NAME-VALUE OPTIONS
    %   Parent         handle   (default = [])  Embed in an existing container;
    %                                           otherwise a new uifigure is owned.
    %   WindowStyle    string   "normal"|"alwaysontop"|"modal" (Parent=[] only)
    %   EnablePreview  logical  (default = true) Set false for headless/
    %                                            numeric-only operation.
    %   PersistPrefs   logical  (default = true) Mirror applied values to
    %                                            getpref/setpref group
    %                                            'ep_RunExpt_Video'.
    %
    % CROP COORDINATE CONVENTION
    %   The ROI Position is [x y w h] in image data coordinates, where the
    %   frame occupies the data range [0.5, W+0.5] x [0.5, H+0.5] (pixel
    %   centers at integers). CropLeft/Top/Right/Bottom are pixels-from-edge,
    %   matching hw.VlcRecorder's parameters directly (no even-rounding is
    %   applied here; hw.VlcRecorder.cropFilterSpec_ already rounds up to
    %   even for x264 and logs when it does).
    %
    % Documentation: documentation/gui/VlcRecorderSetup.md
    % See also hw.VlcRecorder, webcam, images.roi.Rectangle, uifigure

    properties (SetAccess = private, GetAccess = public)
        Recorder  % hw.VlcRecorder instance being configured
        Parent    % parent container handle (user-supplied or owned figure)
    end

    properties (Access = protected)
        RootGrid
        ControlGrid
        CropGrid

        PreviewAxes
        PreviewImage

        CropROI            % images.roi.Rectangle
        RoiMovingListener  event.listener = event.listener.empty
        RoiMovedListener   event.listener = event.listener.empty

        DeviceDropDown
        RefreshDeviceButton
        ResolutionDropDown
        FrameRateSpinner
        CropTopField
        CropBottomField
        CropLeftField
        CropRightField
        ResetCropButton
        MinimalViewCheckBox
        AlwaysOnTopCheckBox
        VlcPreviewButton
        ApplyButton
        OkButton
        StatusLabel

        Camera = []                        % webcam object, or [] when preview unavailable
        PreviewTimer = []                  % timer driving the live preview
        PreviewSize (1,2) double = [0 0]   % [W H] of the current preview frame

        OwnsParentFigure (1,1) logical = false
        ParentDestroyedListener event.listener = event.listener.empty

        InVlcPreview (1,1) logical = false
        Dirty (1,1) logical = false

        EnablePreview_ (1,1) logical = true
        PersistPrefs_  (1,1) logical = true
        DeviceListInitialized_ (1,1) logical = false
    end

    properties (Constant, Access = private)
        DefaultResLabel = '(camera default)'
        MinRoiPx = 16   % smallest allowed crop-region width/height, in pixels
    end

    methods
        function obj = VlcRecorderSetup(Recorder, options)
            arguments
                Recorder (1,1) hw.VlcRecorder
                options.Parent = []
                options.WindowStyle (1,1) string {mustBeMember(options.WindowStyle, ["normal","alwaysontop","modal"])} = "normal"
                options.EnablePreview (1,1) logical = true
                options.PersistPrefs  (1,1) logical = true
            end

            obj.Recorder = Recorder;
            obj.Parent = options.Parent;
            obj.EnablePreview_ = options.EnablePreview;
            obj.PersistPrefs_  = options.PersistPrefs;

            % VLC holds the DirectShow device exclusively; release it before
            % the MATLAB webcam preview can open the same camera.
            if isvalid(obj.Recorder)
                try
                    obj.Recorder.trigger('Stop');
                catch ME
                    vprintf(0, 1, ME);
                end
            end

            obj.createUI(options.WindowStyle);
            obj.initFromRecorder();

            if obj.EnablePreview_
                obj.startPreview();
            else
                obj.setStatus('Preview disabled.');
            end
        end

        function delete(obj)
            % Destructor: release the webcam/timer, then owned UI, in order.
            obj.stopPreview();

            if ~isempty(obj.RoiMovingListener)
                delete(obj.RoiMovingListener);
            end
            if ~isempty(obj.RoiMovedListener)
                delete(obj.RoiMovedListener);
            end
            if ~isempty(obj.ParentDestroyedListener)
                delete(obj.ParentDestroyedListener);
            end

            if ~isempty(obj.CropROI) && isvalid(obj.CropROI)
                delete(obj.CropROI);
            end

            if ~isempty(obj.RootGrid) && isvalid(obj.RootGrid)
                delete(obj.RootGrid);
            end

            if obj.OwnsParentFigure && ~isempty(obj.Parent) && isvalid(obj.Parent)
                setpref('VlcRecorderSetup', 'Position', obj.Parent.Position);
                delete(obj.Parent);
            end
        end
    end

    methods (Access = private)
        function createUI(obj, windowStyle)
            % Build UI under Parent (embedded) or inside a new owned figure.
            if isempty(obj.Parent)
                fpos = getpref('VlcRecorderSetup', 'Position', [400 300 780 480]);
                fig = uifigure('Name', 'VLC Recorder Setup', ...
                    'Position', gui.fitPositionToMonitor(fpos));
                fig.WindowStyle = char(windowStyle);
                fig.CloseRequestFcn = @(~,~) delete(obj);
                obj.Parent = fig;
                obj.OwnsParentFigure = true;
            else
                if ~isvalid(obj.Parent)
                    vprintf(0, 1, 'VlcRecorderSetup: Parent is not valid.');
                end
                obj.ParentDestroyedListener = listener(obj.Parent, 'ObjectBeingDestroyed', @(~,~) delete(obj));
            end

            obj.RootGrid = uigridlayout(obj.Parent, [2 2]);
            obj.RootGrid.RowHeight = {'1x', 22};
            obj.RootGrid.ColumnWidth = {'1x', 260};
            obj.RootGrid.Padding = [8 8 8 8];
            obj.RootGrid.RowSpacing = 6;
            obj.RootGrid.ColumnSpacing = 8;

            % --- Preview axes ---
            obj.PreviewAxes = uiaxes(obj.RootGrid);
            obj.PreviewAxes.Layout.Row = 1;
            obj.PreviewAxes.Layout.Column = 1;
            obj.PreviewAxes.XTick = [];
            obj.PreviewAxes.YTick = [];
            obj.PreviewAxes.XLim = [0.5 1.5];
            obj.PreviewAxes.YLim = [0.5 1.5];
            obj.PreviewAxes.YDir = 'reverse';
            obj.PreviewAxes.DataAspectRatio = [1 1 1];
            obj.PreviewAxes.Toolbar.Visible = 'off';
            disableDefaultInteractivity(obj.PreviewAxes);
            title(obj.PreviewAxes, 'No preview', 'Color', [0.5 0.5 0.5]);

            % --- Controls column ---
            obj.ControlGrid = uigridlayout(obj.RootGrid, [16 1]);
            obj.ControlGrid.Layout.Row = 1;
            obj.ControlGrid.Layout.Column = 2;
            obj.ControlGrid.Padding = [0 0 0 0];
            obj.ControlGrid.RowSpacing = 4;
            obj.ControlGrid.RowHeight = {18,26,18,26,18,26,18,100,26,18,22,22,26,'1x',26,26};
            % The fixed rows exceed the height of a window saved before the VLC
            % window section existed, so let the column scroll rather than clip
            % Apply/OK off the bottom.
            obj.ControlGrid.Scrollable = 'on';

            uilabel(obj.ControlGrid, 'Text', 'Device', 'FontWeight', 'bold');

            deviceRow = uigridlayout(obj.ControlGrid, [1 2]);
            deviceRow.ColumnWidth = {'1x', 70};
            deviceRow.Padding = [0 0 0 0];
            deviceRow.ColumnSpacing = 4;
            obj.DeviceDropDown = uidropdown(deviceRow, 'Editable', 'on', 'Tag', 'VlcRecorderSetup_DeviceDropDown');
            obj.RefreshDeviceButton = uibutton(deviceRow, 'Text', 'Refresh', 'Tag', 'VlcRecorderSetup_RefreshDeviceButton');

            uilabel(obj.ControlGrid, 'Text', 'Resolution', 'FontWeight', 'bold');
            obj.ResolutionDropDown = uidropdown(obj.ControlGrid, 'Items', {obj.DefaultResLabel}, 'Tag', 'VlcRecorderSetup_ResolutionDropDown');

            uilabel(obj.ControlGrid, 'Text', 'Frame rate (fps)', 'FontWeight', 'bold');
            obj.FrameRateSpinner = uispinner(obj.ControlGrid, ...
                'Limits', [0 240], 'Step', 1, 'RoundFractionalValues', 'on', ...
                'ValueDisplayFormat', '%d fps', 'Tag', 'VlcRecorderSetup_FrameRateSpinner');

            uilabel(obj.ControlGrid, 'Text', 'Crop (pixels from edge)', 'FontWeight', 'bold');

            obj.CropGrid = uigridlayout(obj.ControlGrid, [4 2]);
            obj.CropGrid.ColumnWidth = {50, '1x'};
            obj.CropGrid.RowHeight = {22,22,22,22};
            obj.CropGrid.Padding = [0 0 0 0];
            obj.CropGrid.RowSpacing = 2;

            uilabel(obj.CropGrid, 'Text', 'Top:');
            obj.CropTopField = uispinner(obj.CropGrid, ...
                'Limits', [0 Inf], 'Step', 2, 'RoundFractionalValues', 'on', 'ValueDisplayFormat', '%d px', ...
                'Tag', 'VlcRecorderSetup_CropTopField');
            uilabel(obj.CropGrid, 'Text', 'Bottom:');
            obj.CropBottomField = uispinner(obj.CropGrid, ...
                'Limits', [0 Inf], 'Step', 2, 'RoundFractionalValues', 'on', 'ValueDisplayFormat', '%d px', ...
                'Tag', 'VlcRecorderSetup_CropBottomField');
            uilabel(obj.CropGrid, 'Text', 'Left:');
            obj.CropLeftField = uispinner(obj.CropGrid, ...
                'Limits', [0 Inf], 'Step', 2, 'RoundFractionalValues', 'on', 'ValueDisplayFormat', '%d px', ...
                'Tag', 'VlcRecorderSetup_CropLeftField');
            uilabel(obj.CropGrid, 'Text', 'Right:');
            obj.CropRightField = uispinner(obj.CropGrid, ...
                'Limits', [0 Inf], 'Step', 2, 'RoundFractionalValues', 'on', 'ValueDisplayFormat', '%d px', ...
                'Tag', 'VlcRecorderSetup_CropRightField');

            obj.ResetCropButton = uibutton(obj.ControlGrid, 'Text', 'Reset Crop', 'Tag', 'VlcRecorderSetup_ResetCropButton');

            uilabel(obj.ControlGrid, 'Text', 'VLC window', 'FontWeight', 'bold');
            obj.MinimalViewCheckBox = uicheckbox(obj.ControlGrid, ...
                'Text', 'Minimal interface (no menus)', ...
                'Tooltip', 'Start VLC in minimal view: video and playback controls only, no menu bar, playlist, or status bar.', ...
                'Tag', 'VlcRecorderSetup_MinimalViewCheckBox');
            obj.AlwaysOnTopCheckBox = uicheckbox(obj.ControlGrid, ...
                'Text', 'Always on top', ...
                'Tooltip', 'Keep the VLC window above other windows.', ...
                'Tag', 'VlcRecorderSetup_AlwaysOnTopCheckBox');

            obj.VlcPreviewButton = uibutton(obj.ControlGrid, 'Text', 'Preview in VLC', 'Tag', 'VlcRecorderSetup_VlcPreviewButton');

            obj.ApplyButton = uibutton(obj.ControlGrid, 'Text', 'Apply', 'Tag', 'VlcRecorderSetup_ApplyButton');
            obj.ApplyButton.Layout.Row = 15;
            obj.OkButton = uibutton(obj.ControlGrid, 'Text', 'OK', 'Tag', 'VlcRecorderSetup_OkButton');
            obj.OkButton.Layout.Row = 16;

            obj.StatusLabel = uilabel(obj.RootGrid, 'Text', '', 'FontColor', [0.20 0.20 0.20]);
            obj.StatusLabel.Layout.Row = 2;
            obj.StatusLabel.Layout.Column = [1 2];

            obj.DeviceDropDown.ValueChangedFcn      = @(s,e) obj.onDeviceChanged(s,e);
            obj.RefreshDeviceButton.ButtonPushedFcn = @(s,e) obj.onRefreshDevices(s,e);
            obj.ResolutionDropDown.ValueChangedFcn  = @(s,e) obj.onResolutionChanged(s,e);
            obj.FrameRateSpinner.ValueChangedFcn    = @(s,e) obj.onFrameRateChanged(s,e);
            obj.CropTopField.ValueChangedFcn        = @(s,e) obj.onCropFieldChanged(s,e);
            obj.CropBottomField.ValueChangedFcn     = @(s,e) obj.onCropFieldChanged(s,e);
            obj.CropLeftField.ValueChangedFcn       = @(s,e) obj.onCropFieldChanged(s,e);
            obj.CropRightField.ValueChangedFcn      = @(s,e) obj.onCropFieldChanged(s,e);
            obj.ResetCropButton.ButtonPushedFcn     = @(s,e) obj.onResetCrop(s,e);
            obj.MinimalViewCheckBox.ValueChangedFcn = @(s,e) obj.markDirty_();
            obj.AlwaysOnTopCheckBox.ValueChangedFcn = @(s,e) obj.markDirty_();
            obj.VlcPreviewButton.ButtonPushedFcn    = @(s,e) obj.onVlcPreviewToggle(s,e);
            obj.ApplyButton.ButtonPushedFcn         = @(s,e) obj.onApply(s,e);
            obj.OkButton.ButtonPushedFcn            = @(s,e) obj.onOk(s,e);
        end

        function initFromRecorder(obj)
            % Seed all controls from the recorder's current parameter values.
            obj.refreshDeviceList();

            fr = obj.numOrZero_(obj.Recorder.get_parameter('FrameRate'));
            if fr <= 0
                fr = 30;
            end
            obj.FrameRateSpinner.Value = fr;

            res = obj.Recorder.get_parameter('Resolution');
            if ~(isnumeric(res) && numel(res) == 2)
                res = [0 0];
            end
            if all(res > 0)
                resItem = sprintf('%dx%d', res(1), res(2));
                obj.ResolutionDropDown.Items = {obj.DefaultResLabel, resItem};
            else
                resItem = obj.DefaultResLabel;
                obj.ResolutionDropDown.Items = {obj.DefaultResLabel};
            end
            obj.ResolutionDropDown.Value = resItem;

            ct = obj.numOrZero_(obj.Recorder.get_parameter('CropTop'));
            cb = obj.numOrZero_(obj.Recorder.get_parameter('CropBottom'));
            cl = obj.numOrZero_(obj.Recorder.get_parameter('CropLeft'));
            cr = obj.numOrZero_(obj.Recorder.get_parameter('CropRight'));
            obj.setCropFields_([ct cb cl cr]);

            obj.MinimalViewCheckBox.Value = obj.logicalOrDefault_(obj.Recorder.get_parameter('MinimalView'), true);
            obj.AlwaysOnTopCheckBox.Value = obj.logicalOrDefault_(obj.Recorder.get_parameter('AlwaysOnTop'), false);

            obj.Dirty = false;
            obj.setStatus('Ready.');
        end

        function v = numOrZero_(~, v)
            if ~isnumeric(v) || isempty(v) || isnan(v)
                v = 0;
            end
        end

        function tf = logicalOrDefault_(~, v, dflt)
            % get_parameter returns NaN for names it does not recognise, which
            % is what an older recorder reports for these two.
            if isempty(v) || (isnumeric(v) && any(isnan(v)))
                tf = dflt;
            else
                tf = logical(v(1));
            end
        end

        function refreshDeviceList(obj)
            % Populate the device dropdown from PnP FriendlyNames (what VLC's
            % --dshow-vdev matches) unioned with webcamlist (what the MATLAB
            % preview can open). Preserves the current selection across
            % manual refreshes; seeds from the recorder on first call.
            pnp = hw.VlcRecorder.listDevices();
            obj.ensureWebcamAvailable_();
            try
                cams = webcamlist;
            catch
                cams = {};
            end
            names = [pnp(:); cams(:)];
            names = names(~cellfun('isempty', names));

            if obj.DeviceListInitialized_
                wanted = char(obj.DeviceDropDown.Value);
            else
                wanted = char(obj.Recorder.get_parameter('DeviceName'));
                obj.DeviceListInitialized_ = true;
            end

            if ~any(strcmp(names, wanted))
                names = [{wanted}; names];
            end
            names = unique(names, 'stable');

            obj.DeviceDropDown.Items = names;
            obj.DeviceDropDown.Value = wanted;
        end

        function tf = ensureWebcamAvailable_(~)
            % Make the MATLAB `webcam`/`webcamlist` functions callable, adding
            % the USB Webcams support package folder to the path if needed.
            % The add-on can be installed yet absent from the path (e.g. after
            % a path reset), so `webcam` is not found even though the package
            % is present -- self-heal instead of reporting it as missing.
            tf = exist('webcam', 'file') == 2;
            if tf, return; end
            try
                root = matlabshared.supportpkg.getSupportPackageRoot;
            catch
                return  % support package infrastructure unavailable
            end
            wcdir = fullfile(root, 'toolbox', 'matlab', 'webcam', 'supportpackages');
            if ~isfolder(wcdir)
                hits = dir(fullfile(root, 'toolbox', 'matlab', 'webcam', '**', 'webcam.m'));
                if isempty(hits), return; end
                wcdir = hits(1).folder;
            end
            addpath(wcdir);
            tf = exist('webcam', 'file') == 2;
        end

        function startPreview(obj)
            % Open the MATLAB webcam preview and start the refresh timer.
            % Degrades to numeric-only editing (with a status message) when
            % the support package, a camera, or a snapshot is unavailable.
            if ~obj.ensureWebcamAvailable_()
                obj.setStatus('MATLAB USB Webcams support package unavailable; live preview disabled.', true);
                return
            end
            try
                camList = webcamlist;
            catch
                camList = {};
            end
            if isempty(camList)
                obj.setStatus('No webcams detected; live preview disabled.', true);
                return
            end

            camName = obj.resolvePreviewDeviceName_(camList);

            try
                cam = webcam(camName);
            catch ME
                vprintf(0, 1, ME);
                obj.setStatus(sprintf('Could not open webcam "%s".', camName), true);
                return
            end
            obj.Camera = cam;

            resItem = char(obj.ResolutionDropDown.Value);
            if ~strcmp(resItem, obj.DefaultResLabel)
                try
                    obj.Camera.Resolution = resItem;
                catch ME
                    vprintf(1, 'VlcRecorderSetup: could not set camera resolution "%s" (%s); using camera default.', resItem, ME.message);
                end
            end

            try
                frame = snapshot(obj.Camera);
            catch ME
                vprintf(0, 1, ME);
                obj.setStatus('Failed to capture from webcam.', true);
                obj.stopPreview();
                return
            end

            obj.mergeAvailableResolutions_();
            obj.updatePreviewFrame_(frame, true);
            obj.startTimer_();
            obj.setStatus('Live preview running.');
        end

        function stopPreview(obj)
            % Stop the refresh timer and release the webcam (frees the
            % DirectShow device so VLC or another app can open it).
            obj.stopTimer_();
            try
                if ~isempty(obj.Camera)
                    delete(obj.Camera);
                end
            catch ME
                vprintf(1, 'VlcRecorderSetup: error releasing webcam (%s).', ME.message);
            end
            obj.Camera = [];
        end

        function name = resolvePreviewDeviceName_(obj, camList)
            wanted = char(obj.DeviceDropDown.Value);
            idx = find(strcmp(camList, wanted), 1);
            if isempty(idx)
                idx = find(contains(lower(camList), lower(wanted)) | contains(lower(wanted), lower(camList)), 1);
            end
            if isempty(idx)
                name = camList{1};
                if ~strcmp(name, wanted)
                    obj.setStatus('Preview camera differs from configured recording device.', true);
                end
            else
                name = camList{idx};
            end
        end

        function mergeAvailableResolutions_(obj)
            if isempty(obj.Camera)
                return
            end
            try
                avail = obj.Camera.AvailableResolutions;
            catch
                avail = {};
            end
            current = char(obj.ResolutionDropDown.Value);
            items = unique([obj.ResolutionDropDown.Items(:); avail(:)], 'stable');
            obj.ResolutionDropDown.Items = items;
            if any(strcmp(items, current))
                obj.ResolutionDropDown.Value = current;
            end
        end

        function startTimer_(obj)
            obj.stopTimer_();
            obj.PreviewTimer = timer( ...
                'Name', 'gui_VlcRecorderSetup_preview', ...
                'Tag', 'gui_VlcRecorderSetup', ...
                'ExecutionMode', 'fixedSpacing', ...
                'Period', 0.1, ...
                'BusyMode', 'drop', ...
                'TimerFcn', @(~,~) obj.onTimer(), ...
                'ErrorFcn', @(~,~) obj.stopPreview());
            start(obj.PreviewTimer);
        end

        function stopTimer_(obj)
            if ~isempty(obj.PreviewTimer) && isvalid(obj.PreviewTimer)
                try
                    stop(obj.PreviewTimer);
                catch
                end
                delete(obj.PreviewTimer);
            end
            obj.PreviewTimer = [];
        end

        function onTimer(obj)
            try
                if isempty(obj.Camera) || isempty(obj.PreviewImage) || ~isvalid(obj.PreviewImage)
                    obj.stopPreview();
                    return
                end
                frame = snapshot(obj.Camera);
                obj.updatePreviewFrame_(frame, false);
                drawnow limitrate;
            catch ME
                vprintf(0, 1, ME);
                obj.stopPreview();
            end
        end

        function updatePreviewFrame_(obj, frame, resetView)
            sz = size(frame);
            W = sz(2); H = sz(1);

            if isempty(obj.PreviewImage) || ~isvalid(obj.PreviewImage)
                obj.PreviewImage = image(obj.PreviewAxes, frame);
                title(obj.PreviewAxes, '');
            else
                obj.PreviewImage.CData = frame;
            end

            if resetView || ~isequal(obj.PreviewSize, [W H])
                obj.PreviewSize = [W H];
                obj.PreviewAxes.XLim = [0.5, W + 0.5];
                obj.PreviewAxes.YLim = [0.5, H + 0.5];
                obj.rebuildRoi_();
            end
        end

        function rebuildRoi_(obj)
            % (Re)create the crop ROI sized to the current crop fields,
            % clamped to the current preview frame size.
            W = obj.PreviewSize(1); H = obj.PreviewSize(2);
            if W <= 0 || H <= 0
                return
            end

            crops = [obj.CropTopField.Value, obj.CropBottomField.Value, obj.CropLeftField.Value, obj.CropRightField.Value];
            [pos, crops] = obj.cropsToRoi(crops, [W H], obj.MinRoiPx);
            obj.setCropFields_(crops);

            if ~isempty(obj.RoiMovingListener)
                delete(obj.RoiMovingListener);
                obj.RoiMovingListener = event.listener.empty;
            end
            if ~isempty(obj.RoiMovedListener)
                delete(obj.RoiMovedListener);
                obj.RoiMovedListener = event.listener.empty;
            end
            if ~isempty(obj.CropROI) && isvalid(obj.CropROI)
                delete(obj.CropROI);
            end

            obj.CropROI = images.roi.Rectangle(obj.PreviewAxes, ...
                'Position', pos, ...
                'DrawingArea', [0.5 0.5 W H], ...
                'FaceAlpha', 0.1, ...
                'Color', [1 0 0]);

            obj.RoiMovingListener = addlistener(obj.CropROI, 'MovingROI', @(~,evt) obj.onRoiMoving(evt));
            obj.RoiMovedListener  = addlistener(obj.CropROI, 'ROIMoved',  @(~,evt) obj.onRoiMoved(evt));
        end

        function setCropFields_(obj, crops)
            % crops = [Top Bottom Left Right]. Programmatic Value sets do
            % not trigger ValueChangedFcn, so this cannot loop back.
            obj.CropTopField.Value    = crops(1);
            obj.CropBottomField.Value = crops(2);
            obj.CropLeftField.Value   = crops(3);
            obj.CropRightField.Value  = crops(4);
        end

        function applyCropFieldsToRoi_(obj)
            if isempty(obj.CropROI) || ~isvalid(obj.CropROI)
                return
            end
            crops = [obj.CropTopField.Value, obj.CropBottomField.Value, obj.CropLeftField.Value, obj.CropRightField.Value];
            [pos, crops] = obj.cropsToRoi(crops, obj.PreviewSize, obj.MinRoiPx);
            obj.CropROI.Position = pos;
            obj.setCropFields_(crops);
        end

        function onRoiMoving(obj, evt)
            % Live update while dragging; no commit until the gesture ends.
            crops = obj.roiToCrops(evt.CurrentPosition, obj.PreviewSize);
            obj.setCropFields_(crops);
        end

        function onRoiMoved(obj, evt)
            crops = obj.roiToCrops(evt.CurrentPosition, obj.PreviewSize);
            obj.setCropFields_(crops);
            obj.markDirty_();
        end

        function onCropFieldChanged(obj, ~, ~)
            obj.applyCropFieldsToRoi_();
            obj.markDirty_();
        end

        function onResetCrop(obj, ~, ~)
            obj.setCropFields_([0 0 0 0]);
            obj.applyCropFieldsToRoi_();
            obj.markDirty_();
        end

        function onDeviceChanged(obj, ~, ~)
            obj.markDirty_();
            if obj.EnablePreview_ && ~obj.InVlcPreview
                obj.stopPreview();
                obj.startPreview();
            end
        end

        function onResolutionChanged(obj, ~, ~)
            obj.markDirty_();
            if isempty(obj.Camera) || obj.InVlcPreview
                return
            end
            obj.stopTimer_();
            resItem = char(obj.ResolutionDropDown.Value);
            if ~strcmp(resItem, obj.DefaultResLabel)
                try
                    obj.Camera.Resolution = resItem;
                catch ME
                    vprintf(0, 1, sprintf('VlcRecorderSetup: could not set resolution "%s" (%s).', resItem, ME.message));
                    obj.setStatus(sprintf('Could not set resolution "%s".', resItem), true);
                end
            end
            try
                frame = snapshot(obj.Camera);
                obj.updatePreviewFrame_(frame, true);
            catch ME
                vprintf(0, 1, ME);
            end
            obj.startTimer_();
        end

        function onFrameRateChanged(obj, ~, ~)
            % Frame rate only affects VLC capture, not the MATLAB preview.
            obj.markDirty_();
        end

        function onRefreshDevices(obj, ~, ~)
            obj.refreshDeviceList();
        end

        function onVlcPreviewToggle(obj, ~, ~)
            if obj.InVlcPreview
                obj.backToSetup_();
            else
                obj.previewInVlc_();
            end
        end

        function previewInVlc_(obj)
            if ~obj.commitToRecorder()
                return
            end
            obj.stopPreview();
            if ~obj.recorderValid_()
                obj.setStatus('Recorder is no longer valid.', true);
                return
            end
            result = obj.Recorder.trigger('Play');
            if ~result
                obj.setStatus('Failed to launch VLC preview.', true);
                if obj.EnablePreview_
                    obj.startPreview();
                end
                return
            end
            obj.setControlsEnabled_(false);
            obj.VlcPreviewButton.Text = 'Back to Setup';
            obj.InVlcPreview = true;
            obj.setStatus('Previewing in VLC (crop/fps/resolution as configured).');
        end

        function backToSetup_(obj)
            if obj.recorderValid_()
                obj.Recorder.trigger('Stop');
            end
            obj.setControlsEnabled_(true);
            obj.VlcPreviewButton.Text = 'Preview in VLC';
            obj.InVlcPreview = false;
            if obj.EnablePreview_
                obj.startPreview();
            end
        end

        function setControlsEnabled_(obj, tf)
            state = matlab.lang.OnOffSwitchState(tf);
            obj.DeviceDropDown.Enable = state;
            obj.RefreshDeviceButton.Enable = state;
            obj.ResolutionDropDown.Enable = state;
            obj.FrameRateSpinner.Enable = state;
            obj.CropTopField.Enable = state;
            obj.CropBottomField.Enable = state;
            obj.CropLeftField.Enable = state;
            obj.CropRightField.Enable = state;
            obj.ResetCropButton.Enable = state;
            obj.MinimalViewCheckBox.Enable = state;
            obj.AlwaysOnTopCheckBox.Enable = state;
        end

        function onApply(obj, ~, ~)
            obj.commitToRecorder();
        end

        function onOk(obj, ~, ~)
            obj.commitToRecorder();
            delete(obj);
        end

        function tf = recorderValid_(obj)
            tf = ~isempty(obj.Recorder) && isvalid(obj.Recorder);
        end

        function ok = commitToRecorder(obj)
            % Push all staged control values to the recorder via its public
            % set_parameter API, and optionally mirror them to the
            % 'ep_RunExpt_Video' preference group.
            ok = false;
            if ~obj.recorderValid_()
                obj.setStatus('Recorder is no longer valid; cannot apply changes.', true);
                return
            end

            device = char(obj.DeviceDropDown.Value);
            obj.Recorder.set_parameter('DeviceName', device);
            obj.Recorder.set_parameter('FrameRate', obj.FrameRateSpinner.Value);

            % An explicit dropdown selection always wins: the MATLAB preview
            % may not have honored it (driver rejected the switch, or the
            % preview camera differs from the recording device), and VLC's
            % --dshow-size lets the driver negotiate the nearest size anyway.
            % PreviewSize is only committed for '(camera default)' so the
            % crop values stay pinned to a known frame size.
            resItem = char(obj.ResolutionDropDown.Value);
            if ~strcmp(resItem, obj.DefaultResLabel)
                resVal = sscanf(resItem, '%dx%d')';
            elseif obj.EnablePreview_ && all(obj.PreviewSize > 0)
                resVal = obj.PreviewSize;
            else
                resVal = [0 0];
            end
            obj.Recorder.set_parameter('Resolution', resVal);

            cropTop    = obj.CropTopField.Value;
            cropBottom = obj.CropBottomField.Value;
            cropLeft   = obj.CropLeftField.Value;
            cropRight  = obj.CropRightField.Value;
            obj.Recorder.set_parameter('CropTop',    cropTop);
            obj.Recorder.set_parameter('CropBottom', cropBottom);
            obj.Recorder.set_parameter('CropLeft',   cropLeft);
            obj.Recorder.set_parameter('CropRight',  cropRight);

            minimalView = obj.MinimalViewCheckBox.Value;
            alwaysOnTop = obj.AlwaysOnTopCheckBox.Value;
            obj.Recorder.set_parameter('MinimalView', minimalView);
            obj.Recorder.set_parameter('AlwaysOnTop', alwaysOnTop);

            if obj.PersistPrefs_
                setpref('ep_RunExpt_Video', 'DeviceName',   device);
                setpref('ep_RunExpt_Video', 'FrameRate',    obj.FrameRateSpinner.Value);
                setpref('ep_RunExpt_Video', 'Resolution',   resVal);
                setpref('ep_RunExpt_Video', 'CropTop',      cropTop);
                setpref('ep_RunExpt_Video', 'CropBottom',   cropBottom);
                setpref('ep_RunExpt_Video', 'CropLeft',     cropLeft);
                setpref('ep_RunExpt_Video', 'CropRight',    cropRight);
                setpref('ep_RunExpt_Video', 'MinimalView',  minimalView);
                setpref('ep_RunExpt_Video', 'AlwaysOnTop',  alwaysOnTop);
            end

            obj.Dirty = false;
            obj.setStatus('Applied.');
            ok = true;
        end

        function markDirty_(obj)
            obj.Dirty = true;
            obj.setStatus('Unapplied changes - click Apply to update the recorder.');
        end

        function setStatus(obj, msg, isError)
            if nargin < 3
                isError = false;
            end
            if isempty(obj.StatusLabel) || ~isvalid(obj.StatusLabel)
                return
            end
            obj.StatusLabel.Text = msg;
            if isError
                obj.StatusLabel.FontColor = [0.70 0.10 0.10];
                vprintf(1, msg);
            else
                obj.StatusLabel.FontColor = [0.20 0.20 0.20];
            end
        end
    end

    methods (Static)
        function crops = roiToCrops(pos, imgSize)
            % crops = gui.VlcRecorderSetup.roiToCrops(pos, imgSize)
            % pos     - ROI Position [x y w h] in image data coordinates.
            % imgSize - [W H] image size in pixels.
            % crops   - [CropTop CropBottom CropLeft CropRight], each >= 0.
            W = imgSize(1); H = imgSize(2);
            x = pos(1); y = pos(2); w = pos(3); h = pos(4);

            cropLeft   = max(0, round(x - 0.5));
            cropTop    = max(0, round(y - 0.5));
            cropRight  = max(0, round(W + 0.5 - (x + w)));
            cropBottom = max(0, round(H + 0.5 - (y + h)));

            crops = [cropTop, cropBottom, cropLeft, cropRight];
        end

        function [pos, crops] = cropsToRoi(crops, imgSize, minRoiPx)
            % [pos, crops] = gui.VlcRecorderSetup.cropsToRoi(crops, imgSize, minRoiPx)
            % crops    - [CropTop CropBottom CropLeft CropRight].
            % imgSize  - [W H].
            % minRoiPx - smallest allowed ROI width/height (default 16); excess
            %            crop is shrunk proportionally and the corrected
            %            crops are returned as the second output.
            if nargin < 3 || isempty(minRoiPx)
                minRoiPx = 16;
            end
            W = imgSize(1); H = imgSize(2);
            crops = max(0, round(crops));
            top = crops(1); bottom = crops(2); left = crops(3); right = crops(4);

            w = W - left - right;
            if w < minRoiPx
                excess = minRoiPx - w;
                total = left + right;
                if total <= 0
                    left = 0; right = max(0, W - minRoiPx);
                else
                    left  = max(0, left  - ceil(excess * left  / total));
                    right = max(0, right - ceil(excess * right / total));
                end
                w = W - left - right;
            end

            h = H - top - bottom;
            if h < minRoiPx
                excess = minRoiPx - h;
                total = top + bottom;
                if total <= 0
                    top = 0; bottom = max(0, H - minRoiPx);
                else
                    top    = max(0, top    - ceil(excess * top    / total));
                    bottom = max(0, bottom - ceil(excess * bottom / total));
                end
                h = H - top - bottom;
            end

            x = left + 0.5;
            y = top + 0.5;
            pos = [x, y, w, h];
            crops = [top, bottom, left, right];
        end
    end

end
