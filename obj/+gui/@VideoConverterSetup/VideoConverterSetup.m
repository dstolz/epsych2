classdef VideoConverterSetup < handle
    % g = gui.VideoConverterSetup(Converter, Name=Value,...)
    % Simple GUI for util.VideoConverter: pick a root folder and a filename
    % regular expression, preview the matched files, choose an encoding
    % preset (or customize codec/quality/scale/range/output options), then
    % Scan and Convert. Progress (including true per-file percent) is
    % driven by the Progress event -- the GUI never polls.
    %
    % CONSTRUCTOR
    %   g = gui.VideoConverterSetup(Converter)
    %   g = gui.VideoConverterSetup(Converter, Name=Value,...)
    %
    % NAME-VALUE OPTIONS
    %   Parent        handle  (default = [])  Embed in an existing container;
    %                                         otherwise a new uifigure is owned.
    %   WindowStyle   string  "normal"|"alwaysontop"|"modal" (Parent=[] only)
    %   PersistPrefs  logical (default = true) Persist window position (and
    %                                          nothing else) to getpref/setpref
    %                                          group 'ep_VideoConverter'.
    %
    % Note: the GUI configures and drives the Converter you pass in, but does
    % not own its lifetime -- closing the GUI never cancels or deletes it.
    %
    % Documentation: documentation/util/VideoConverter.md
    % See also util.VideoConverter, uifigure

    properties (SetAccess = private, GetAccess = public)
        Converter   % util.VideoConverter instance being configured/driven
        Parent      % parent container handle (user-supplied or owned figure)
    end

    properties (Access = protected)
        RootGrid
        FileTable
        SideGrid

        RootFolderField
        BrowseRootButton
        PatternField
        ExcludeField
        RecursiveCheckBox

        PresetDropDown
        VideoCodecDropDown
        CrfSpinner
        X264PresetDropDown
        AudioCodecDropDown
        FrameRateSpinner
        ScaleSpinner
        RangeStartField
        RangeStopField

        AlongsideCheckBox
        OutputFolderField
        BrowseOutputButton
        MirrorTreeCheckBox
        NameSuffixField
        OutputExtensionDropDown

        OverwriteDropDown
        MaxParallelSpinner
        DeleteSourceCheckBox
        DryRunCheckBox

        ScanButton
        ConvertButton
        CancelButton
        OverallLabel
        StatusLabel

        OwnsParentFigure (1,1) logical = false
        ParentDestroyedListener event.listener = event.listener.empty
        ProgressListener event.listener = event.listener.empty

        PersistPrefs_ (1,1) logical = true
        ApplyingPreset_ (1,1) logical = false
    end

    properties (Constant, Access = private)
        PresetNames = ["H.264 archive (CRF 18, medium)", "H.264 compact (CRF 23, faster)", ...
            "H.264 preview (CRF 28, veryfast, 0.5x)", "Remux (stream copy)", ...
            "Strip audio (H.264)", "Custom"]
    end

    methods
        function obj = VideoConverterSetup(Converter, options)
            arguments
                Converter (1,1) util.VideoConverter
                options.Parent = []
                options.WindowStyle (1,1) string {mustBeMember(options.WindowStyle, ["normal","alwaysontop","modal"])} = "normal"
                options.PersistPrefs (1,1) logical = true
            end

            obj.Converter = Converter;
            obj.Parent = options.Parent;
            obj.PersistPrefs_ = options.PersistPrefs;

            obj.createUI(options.WindowStyle);
            obj.initFromConverter();

            obj.ProgressListener = listener(obj.Converter, 'Progress', @(s,e) obj.onProgress(s,e));
            obj.setStatus('Ready. Set a root folder and click Scan.');
        end

        function delete(obj)
            % Destructor: detach listeners, then owned UI, in order. Never
            % touches the Converter's lifetime (not owned by this GUI).
            if ~isempty(obj.ProgressListener)
                delete(obj.ProgressListener);
            end
            if ~isempty(obj.ParentDestroyedListener)
                delete(obj.ParentDestroyedListener);
            end
            if ~isempty(obj.RootGrid) && isvalid(obj.RootGrid)
                delete(obj.RootGrid);
            end
            if obj.OwnsParentFigure && ~isempty(obj.Parent) && isvalid(obj.Parent)
                if obj.PersistPrefs_
                    setpref('ep_VideoConverter', 'Position', obj.Parent.Position);
                end
                delete(obj.Parent);
            end
        end
    end

    methods (Access = private)
        function createUI(obj, windowStyle)
            if isempty(obj.Parent)
                fpos = getpref('ep_VideoConverter', 'Position', [300 200 1040 640]);
                fig = uifigure('Name', 'Video Converter', 'Position', fpos);
                movegui(fig, 'onscreen');
                fig.WindowStyle = char(windowStyle);
                fig.CloseRequestFcn = @(~,~) delete(obj);
                obj.Parent = fig;
                obj.OwnsParentFigure = true;
            else
                if ~isvalid(obj.Parent)
                    vprintf(0, 1, 'VideoConverterSetup: Parent is not valid.');
                end
                obj.ParentDestroyedListener = listener(obj.Parent, 'ObjectBeingDestroyed', @(~,~) delete(obj));
            end

            obj.RootGrid = uigridlayout(obj.Parent, [3 2]);
            obj.RootGrid.RowHeight = {'1x', 30, 22};
            obj.RootGrid.ColumnWidth = {'1x', 340};
            obj.RootGrid.Padding = [8 8 8 8];
            obj.RootGrid.RowSpacing = 6;
            obj.RootGrid.ColumnSpacing = 8;

            % --- File table ---
            obj.FileTable = uitable(obj.RootGrid, 'Tag', 'VideoConverterSetup_FileTable');
            obj.FileTable.Layout.Row = 1;
            obj.FileTable.Layout.Column = 1;
            obj.FileTable.ColumnName = {'Source','Output','Dur','Size','Status','%'};
            obj.FileTable.ColumnEditable = [false false false false false false];
            obj.FileTable.Data = table(strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), zeros(0,1), ...
                'VariableNames', {'Source','Output','Dur','Size','Status','Percent'});

            % --- Side column (scrollable) ---
            obj.SideGrid = uigridlayout(obj.RootGrid, [4 1]);
            obj.SideGrid.Layout.Row = 1;
            obj.SideGrid.Layout.Column = 2;
            obj.SideGrid.Padding = [0 0 0 0];
            obj.SideGrid.RowSpacing = 6;
            obj.SideGrid.RowHeight = {150, 250, 130, 130};
            obj.SideGrid.Scrollable = 'on';

            obj.buildSourcePanel_();
            obj.buildEncodingPanel_();
            obj.buildOutputPanel_();
            obj.buildRunPanel_();

            % --- Bottom row: actions + overall progress ---
            bottomGrid = uigridlayout(obj.RootGrid, [1 4]);
            bottomGrid.Layout.Row = 2;
            bottomGrid.Layout.Column = [1 2];
            bottomGrid.ColumnWidth = {90, 90, 90, '1x'};
            bottomGrid.Padding = [0 0 0 0];
            bottomGrid.ColumnSpacing = 8;

            obj.ScanButton = uibutton(bottomGrid, 'Text', 'Scan', 'Tag', 'VideoConverterSetup_ScanButton');
            obj.ConvertButton = uibutton(bottomGrid, 'Text', 'Convert', 'Tag', 'VideoConverterSetup_ConvertButton');
            obj.CancelButton = uibutton(bottomGrid, 'Text', 'Cancel', 'Tag', 'VideoConverterSetup_CancelButton', 'Enable', 'off');
            obj.OverallLabel = uilabel(bottomGrid, 'Text', '', 'HorizontalAlignment', 'right', 'Tag', 'VideoConverterSetup_OverallLabel');

            % --- Status line ---
            obj.StatusLabel = uilabel(obj.RootGrid, 'Text', '', 'FontColor', [0.20 0.20 0.20]);
            obj.StatusLabel.Layout.Row = 3;
            obj.StatusLabel.Layout.Column = [1 2];

            obj.ScanButton.ButtonPushedFcn = @(s,e) obj.onScan(s,e);
            obj.ConvertButton.ButtonPushedFcn = @(s,e) obj.onConvert(s,e);
            obj.CancelButton.ButtonPushedFcn = @(s,e) obj.onCancel(s,e);
        end

        function buildSourcePanel_(obj)
            p = uipanel(obj.SideGrid, 'Title', 'Source');
            p.Layout.Row = 1;
            g = uigridlayout(p, [4 2]);
            g.ColumnWidth = {80, '1x'};
            g.RowHeight = {24, 24, 24, 24};

            uilabel(g, 'Text', 'Root folder');
            rootRow = uigridlayout(g, [1 2]);
            rootRow.ColumnWidth = {'1x', 70};
            rootRow.Padding = [0 0 0 0];
            obj.RootFolderField = uieditfield(rootRow, 'text', 'Tag', 'VideoConverterSetup_RootFolderField');
            obj.BrowseRootButton = uibutton(rootRow, 'Text', 'Browse', 'Tag', 'VideoConverterSetup_BrowseRootButton');

            uilabel(g, 'Text', 'Pattern');
            obj.PatternField = uieditfield(g, 'text', 'Tag', 'VideoConverterSetup_PatternField');

            uilabel(g, 'Text', 'Exclude');
            obj.ExcludeField = uieditfield(g, 'text', 'Tag', 'VideoConverterSetup_ExcludeField');

            uilabel(g, 'Text', '');
            obj.RecursiveCheckBox = uicheckbox(g, 'Text', 'Recursive', 'Tag', 'VideoConverterSetup_RecursiveCheckBox');

            obj.RootFolderField.ValueChangedFcn = @(s,e) obj.onSourceOptionChanged(s,e);
            obj.BrowseRootButton.ButtonPushedFcn = @(s,e) obj.onBrowseRoot(s,e);
            obj.PatternField.ValueChangedFcn = @(s,e) obj.onSourceOptionChanged(s,e);
            obj.ExcludeField.ValueChangedFcn = @(s,e) obj.onSourceOptionChanged(s,e);
            obj.RecursiveCheckBox.ValueChangedFcn = @(s,e) obj.onSourceOptionChanged(s,e);
        end

        function buildEncodingPanel_(obj)
            p = uipanel(obj.SideGrid, 'Title', 'Encoding');
            p.Layout.Row = 2;
            g = uigridlayout(p, [8 2]);
            g.ColumnWidth = {100, '1x'};
            g.RowHeight = repmat({24}, 1, 8);

            uilabel(g, 'Text', 'Preset');
            obj.PresetDropDown = uidropdown(g, 'Items', cellstr(obj.PresetNames), 'Tag', 'VideoConverterSetup_PresetDropDown');

            uilabel(g, 'Text', 'Video codec');
            obj.VideoCodecDropDown = uidropdown(g, 'Items', {'x264','mpeg4','copy','none'}, 'Tag', 'VideoConverterSetup_VideoCodecDropDown');

            uilabel(g, 'Text', 'CRF');
            obj.CrfSpinner = uispinner(g, 'Limits', [1 51], 'RoundFractionalValues', 'on', 'Tag', 'VideoConverterSetup_CrfSpinner');

            uilabel(g, 'Text', 'x264 preset');
            obj.X264PresetDropDown = uidropdown(g, ...
                'Items', {'ultrafast','superfast','veryfast','faster','fast','medium','slow','slower','veryslow'}, ...
                'Tag', 'VideoConverterSetup_X264PresetDropDown');

            uilabel(g, 'Text', 'Audio codec');
            obj.AudioCodecDropDown = uidropdown(g, 'Items', {'aac','mp3','wav','copy','none'}, 'Tag', 'VideoConverterSetup_AudioCodecDropDown');

            uilabel(g, 'Text', 'Frame rate');
            obj.FrameRateSpinner = uispinner(g, 'Limits', [0 240], 'RoundFractionalValues', 'on', ...
                'ValueDisplayFormat', '%d fps (0=source)', 'Tag', 'VideoConverterSetup_FrameRateSpinner');

            uilabel(g, 'Text', 'Scale');
            obj.ScaleSpinner = uispinner(g, 'Limits', [0.05 4], 'Step', 0.05, ...
                'ValueDisplayFormat', '%.2fx', 'Tag', 'VideoConverterSetup_ScaleSpinner');

            uilabel(g, 'Text', 'Range (s)');
            rangeRow = uigridlayout(g, [1 2]);
            rangeRow.Padding = [0 0 0 0];
            obj.RangeStartField = uieditfield(rangeRow, 'numeric', 'Limits', [0 Inf], 'Tag', 'VideoConverterSetup_RangeStartField');
            obj.RangeStopField = uieditfield(rangeRow, 'numeric', 'Limits', [0 Inf], 'Tag', 'VideoConverterSetup_RangeStopField');

            obj.PresetDropDown.ValueChangedFcn = @(s,e) obj.onPresetChanged(s,e);
            obj.VideoCodecDropDown.ValueChangedFcn = @(s,e) obj.onVideoCodecChanged(s,e);
            obj.CrfSpinner.ValueChangedFcn = @(s,e) obj.onEncodingOptionChanged(s,e);
            obj.X264PresetDropDown.ValueChangedFcn = @(s,e) obj.onEncodingOptionChanged(s,e);
            obj.AudioCodecDropDown.ValueChangedFcn = @(s,e) obj.onEncodingOptionChanged(s,e);
            obj.FrameRateSpinner.ValueChangedFcn = @(s,e) obj.onEncodingOptionChanged(s,e);
            obj.ScaleSpinner.ValueChangedFcn = @(s,e) obj.onEncodingOptionChanged(s,e);
            obj.RangeStartField.ValueChangedFcn = @(s,e) obj.onEncodingOptionChanged(s,e);
            obj.RangeStopField.ValueChangedFcn = @(s,e) obj.onEncodingOptionChanged(s,e);
        end

        function buildOutputPanel_(obj)
            p = uipanel(obj.SideGrid, 'Title', 'Output');
            p.Layout.Row = 3;
            g = uigridlayout(p, [4 2]);
            g.ColumnWidth = {80, '1x'};
            g.RowHeight = repmat({24}, 1, 4);

            uilabel(g, 'Text', '');
            obj.AlongsideCheckBox = uicheckbox(g, 'Text', 'Alongside source', 'Tag', 'VideoConverterSetup_AlongsideCheckBox');

            uilabel(g, 'Text', 'Folder');
            outRow = uigridlayout(g, [1 2]);
            outRow.ColumnWidth = {'1x', 70};
            outRow.Padding = [0 0 0 0];
            obj.OutputFolderField = uieditfield(outRow, 'text', 'Tag', 'VideoConverterSetup_OutputFolderField');
            obj.BrowseOutputButton = uibutton(outRow, 'Text', 'Browse', 'Tag', 'VideoConverterSetup_BrowseOutputButton');

            uilabel(g, 'Text', '');
            obj.MirrorTreeCheckBox = uicheckbox(g, 'Text', 'Mirror folder tree', 'Tag', 'VideoConverterSetup_MirrorTreeCheckBox');

            uilabel(g, 'Text', 'Suffix / Ext');
            sufRow = uigridlayout(g, [1 2]);
            sufRow.ColumnWidth = {'1x', 80};
            sufRow.Padding = [0 0 0 0];
            obj.NameSuffixField = uieditfield(sufRow, 'text', 'Tag', 'VideoConverterSetup_NameSuffixField');
            obj.OutputExtensionDropDown = uidropdown(sufRow, 'Items', {'.mp4','.avi','.mkv','.ts'}, 'Tag', 'VideoConverterSetup_OutputExtensionDropDown');

            obj.AlongsideCheckBox.ValueChangedFcn = @(s,e) obj.onAlongsideToggled(s,e);
            obj.OutputFolderField.ValueChangedFcn = @(s,e) obj.onOutputOptionChanged(s,e);
            obj.BrowseOutputButton.ButtonPushedFcn = @(s,e) obj.onBrowseOutput(s,e);
            obj.MirrorTreeCheckBox.ValueChangedFcn = @(s,e) obj.onOutputOptionChanged(s,e);
            obj.NameSuffixField.ValueChangedFcn = @(s,e) obj.onOutputOptionChanged(s,e);
            obj.OutputExtensionDropDown.ValueChangedFcn = @(s,e) obj.onOutputOptionChanged(s,e);
        end

        function buildRunPanel_(obj)
            p = uipanel(obj.SideGrid, 'Title', 'Run');
            p.Layout.Row = 4;
            g = uigridlayout(p, [4 2]);
            g.ColumnWidth = {100, '1x'};
            g.RowHeight = repmat({24}, 1, 4);

            uilabel(g, 'Text', 'On conflict');
            obj.OverwriteDropDown = uidropdown(g, 'Items', {'skip','overwrite','error'}, 'Tag', 'VideoConverterSetup_OverwriteDropDown');

            uilabel(g, 'Text', 'Parallel jobs');
            obj.MaxParallelSpinner = uispinner(g, 'Limits', [1 8], 'RoundFractionalValues', 'on', 'Tag', 'VideoConverterSetup_MaxParallelSpinner');

            uilabel(g, 'Text', '');
            obj.DeleteSourceCheckBox = uicheckbox(g, 'Text', 'Delete source after conversion', ...
                'FontColor', [0.70 0.10 0.10], 'Tag', 'VideoConverterSetup_DeleteSourceCheckBox');

            uilabel(g, 'Text', '');
            obj.DryRunCheckBox = uicheckbox(g, 'Text', 'Dry run (preview only)', 'Tag', 'VideoConverterSetup_DryRunCheckBox');

            obj.OverwriteDropDown.ValueChangedFcn = @(s,e) obj.onRunOptionChanged(s,e);
            obj.MaxParallelSpinner.ValueChangedFcn = @(s,e) obj.onRunOptionChanged(s,e);
            obj.DeleteSourceCheckBox.ValueChangedFcn = @(s,e) obj.onRunOptionChanged(s,e);
            obj.DryRunCheckBox.ValueChangedFcn = @(s,e) obj.onRunOptionChanged(s,e);
        end

        function initFromConverter(obj)
            c = obj.Converter;

            obj.RootFolderField.Value = char(c.RootFolder);
            obj.PatternField.Value = char(c.FilePattern);
            obj.ExcludeField.Value = char(c.ExcludePattern);
            obj.RecursiveCheckBox.Value = c.Recursive;

            obj.VideoCodecDropDown.Value = char(c.VideoCodec);
            obj.CrfSpinner.Value = c.x264Crf;
            obj.X264PresetDropDown.Value = char(c.x264Preset);
            obj.AudioCodecDropDown.Value = char(c.AudioCodec);
            obj.FrameRateSpinner.Value = obj.scalarOrZero_(c.OutputFrameRate);
            obj.ScaleSpinner.Value = obj.scalarOrDefault_(c.VideoScale, 1);
            if numel(c.Range) == 2
                obj.RangeStartField.Value = c.Range(1);
                obj.RangeStopField.Value = c.Range(2);
            else
                obj.RangeStartField.Value = 0;
                obj.RangeStopField.Value = 0;
            end
            obj.PresetDropDown.Value = char(obj.PresetNames(1));   % class defaults == preset 1
            obj.updateEncodingEnable_();

            obj.AlongsideCheckBox.Value = (c.OutputFolder == "");
            obj.OutputFolderField.Value = char(c.OutputFolder);
            obj.MirrorTreeCheckBox.Value = c.MirrorTree;
            obj.NameSuffixField.Value = char(c.NameSuffix);
            ext = char(c.OutputExtension);
            if ~any(strcmp(obj.OutputExtensionDropDown.Items, ext))
                obj.OutputExtensionDropDown.Items = [obj.OutputExtensionDropDown.Items, {ext}];
            end
            obj.OutputExtensionDropDown.Value = ext;
            obj.updateOutputEnable_();

            obj.OverwriteDropDown.Value = char(c.Overwrite);
            obj.MaxParallelSpinner.Value = c.MaxParallel;
            obj.DeleteSourceCheckBox.Value = c.DeleteSource;
            obj.DryRunCheckBox.Value = c.DryRun;
        end

        function v = scalarOrZero_(~, v)
            if isempty(v)
                v = 0;
            else
                v = v(1);
            end
        end

        function v = scalarOrDefault_(~, v, dflt)
            if isempty(v)
                v = dflt;
            else
                v = v(1);
            end
        end

        % ---------------- callbacks ----------------

        function onBrowseRoot(obj, ~, ~)
            start = char(obj.RootFolderField.Value);
            if isempty(start) || ~isfolder(start)
                start = pwd;
            end
            d = uigetdir(start, 'Select root folder to scan');
            if isequal(d, 0)
                return
            end
            obj.RootFolderField.Value = d;
            obj.onSourceOptionChanged();
        end

        function onBrowseOutput(obj, ~, ~)
            start = char(obj.OutputFolderField.Value);
            if isempty(start) || ~isfolder(start)
                start = pwd;
            end
            d = uigetdir(start, 'Select output folder');
            if isequal(d, 0)
                return
            end
            obj.OutputFolderField.Value = d;
            obj.onOutputOptionChanged();
        end

        function onSourceOptionChanged(obj, ~, ~)
            obj.Converter.RootFolder = string(obj.RootFolderField.Value);
            obj.Converter.FilePattern = string(obj.PatternField.Value);
            obj.Converter.ExcludePattern = string(obj.ExcludeField.Value);
            obj.Converter.Recursive = obj.RecursiveCheckBox.Value;
        end

        function onPresetChanged(obj, ~, ~)
            name = string(obj.PresetDropDown.Value);
            if name == "Custom"
                return
            end
            obj.ApplyingPreset_ = true;
            switch name
                case "H.264 archive (CRF 18, medium)"
                    obj.setEncoding_("x264", 18, "medium", "aac", 1);
                case "H.264 compact (CRF 23, faster)"
                    obj.setEncoding_("x264", 23, "faster", "aac", 1);
                case "H.264 preview (CRF 28, veryfast, 0.5x)"
                    obj.setEncoding_("x264", 28, "veryfast", "aac", 0.5);
                case "Remux (stream copy)"
                    obj.setEncoding_("copy", obj.CrfSpinner.Value, char(obj.X264PresetDropDown.Value), "copy", 1);
                case "Strip audio (H.264)"
                    obj.setEncoding_("x264", 18, "medium", "none", 1);
            end
            obj.ApplyingPreset_ = false;
        end

        function setEncoding_(obj, codec, crf, preset, audio, scale)
            obj.VideoCodecDropDown.Value = char(codec);
            obj.CrfSpinner.Value = crf;
            obj.X264PresetDropDown.Value = char(preset);
            obj.AudioCodecDropDown.Value = char(audio);
            obj.ScaleSpinner.Value = scale;
            obj.applyEncodingToConverter_();
            obj.updateEncodingEnable_();
        end

        function onVideoCodecChanged(obj, ~, ~)
            if strcmp(obj.VideoCodecDropDown.Value, 'copy') && obj.ScaleSpinner.Value ~= 1
                obj.ScaleSpinner.Value = 1;
                obj.setStatus('Scale reset to 1.0x: VideoCodec="copy" cannot be filtered.');
            end
            obj.applyEncodingToConverter_();
            obj.updateEncodingEnable_();
            obj.markCustom_();
        end

        function onEncodingOptionChanged(obj, ~, ~)
            obj.applyEncodingToConverter_();
            obj.markCustom_();
        end

        function applyEncodingToConverter_(obj)
            c = obj.Converter;
            c.VideoCodec = string(obj.VideoCodecDropDown.Value);
            c.x264Crf = obj.CrfSpinner.Value;
            c.x264Preset = string(obj.X264PresetDropDown.Value);
            c.AudioCodec = string(obj.AudioCodecDropDown.Value);
            if obj.FrameRateSpinner.Value <= 0
                c.OutputFrameRate = [];
            else
                c.OutputFrameRate = obj.FrameRateSpinner.Value;
            end
            if abs(obj.ScaleSpinner.Value - 1) < 1e-9
                c.VideoScale = [];
            else
                c.VideoScale = obj.ScaleSpinner.Value;
            end
            rs = obj.RangeStartField.Value;
            re = obj.RangeStopField.Value;
            if re > rs && re > 0
                c.Range = [rs re];
            else
                c.Range = [];
            end
        end

        function updateEncodingEnable_(obj)
            isX264 = strcmp(obj.VideoCodecDropDown.Value, 'x264');
            state = matlab.lang.OnOffSwitchState(isX264);
            obj.CrfSpinner.Enable = state;
            obj.X264PresetDropDown.Enable = state;
        end

        function markCustom_(obj)
            if ~obj.ApplyingPreset_
                obj.PresetDropDown.Value = 'Custom';
            end
        end

        function onAlongsideToggled(obj, ~, ~)
            if obj.AlongsideCheckBox.Value
                obj.Converter.OutputFolder = "";
            else
                obj.Converter.OutputFolder = string(obj.OutputFolderField.Value);
            end
            obj.updateOutputEnable_();
        end

        function onOutputOptionChanged(obj, ~, ~)
            if ~obj.AlongsideCheckBox.Value
                obj.Converter.OutputFolder = string(obj.OutputFolderField.Value);
            end
            obj.Converter.MirrorTree = obj.MirrorTreeCheckBox.Value;
            obj.Converter.NameSuffix = string(obj.NameSuffixField.Value);
            obj.Converter.OutputExtension = string(obj.OutputExtensionDropDown.Value);
        end

        function updateOutputEnable_(obj)
            state = matlab.lang.OnOffSwitchState(~obj.AlongsideCheckBox.Value);
            obj.OutputFolderField.Enable = state;
            obj.BrowseOutputButton.Enable = state;
            obj.MirrorTreeCheckBox.Enable = state;
        end

        function onRunOptionChanged(obj, ~, ~)
            obj.Converter.Overwrite = string(obj.OverwriteDropDown.Value);
            obj.Converter.MaxParallel = obj.MaxParallelSpinner.Value;
            obj.Converter.DeleteSource = obj.DeleteSourceCheckBox.Value;
            obj.Converter.DryRun = obj.DryRunCheckBox.Value;
        end

        function onScan(obj, ~, ~)
            if obj.Converter.RootFolder == ""
                obj.setStatus('Set a root folder first.', true);
                return
            end
            obj.setStatus('Scanning...');
            drawnow;
            files = obj.Converter.scan(); %#ok<NASGU> -- Results is the source of truth
            obj.refreshFileTable_();
            n = height(obj.Converter.Results);
            obj.setStatus(sprintf('Found %d file(s).', n));
        end

        function onConvert(obj, ~, ~)
            if height(obj.Converter.Results) == 0
                obj.onScan();
                if height(obj.Converter.Results) == 0
                    obj.setStatus('No files matched; nothing to convert.', true);
                    return
                end
            end
            obj.setControlsEnabled_(false);
            obj.Converter.convert();
        end

        function onCancel(obj, ~, ~)
            obj.Converter.cancel();
        end

        function onProgress(obj, ~, evt)
            switch evt.Stage
                case "scanned"
                    % handled synchronously by onScan; nothing to do here
                case "started"
                    obj.setStatus('Converting...');
                case {"progress","jobdone"}
                    obj.refreshFileTable_();
                    obj.updateOverallLabel_(evt);
                case {"finished","cancelled"}
                    obj.refreshFileTable_();
                    obj.updateOverallLabel_(evt);
                    obj.setControlsEnabled_(true);
                    if evt.Stage == "cancelled"
                        obj.setStatus('Cancelled.');
                    else
                        obj.setStatus(sprintf('Done: %d succeeded, %d failed.', evt.NumDone, evt.NumFailed));
                    end
            end
            drawnow limitrate;
        end

        function updateOverallLabel_(obj, evt)
            if isnan(evt.OverallPercent)
                txt = sprintf('%d/%d done', evt.NumDone, evt.NumJobs);
            else
                etaStr = '--:--';
                if isfinite(evt.EtaSeconds)
                    etaStr = datestr(seconds(evt.EtaSeconds), 'HH:MM:SS'); %#ok<DATST>
                end
                txt = sprintf('Overall %.0f%%  |  %d/%d done  |  %d failed  |  ETA %s', ...
                    evt.OverallPercent, evt.NumDone, evt.NumJobs, evt.NumFailed, etaStr);
            end
            obj.OverallLabel.Text = txt;
        end

        function refreshFileTable_(obj)
            T = obj.Converter.Results;
            root = obj.Converter.RootFolder;
            n = height(T);
            src = strings(n,1);
            out = strings(n,1);
            durS = strings(n,1);
            sizeS = strings(n,1);
            for k = 1:n
                src(k) = obj.relPath_(root, T.SourceFile(k));
                out(k) = obj.relPath_(root, T.OutputFile(k));
                if isfinite(T.DurationSec(k))
                    durS(k) = string(datestr(seconds(T.DurationSec(k)), 'MM:SS')); %#ok<DATST>
                else
                    durS(k) = "-";
                end
                sizeS(k) = obj.humanBytes_(T.BytesIn(k));
            end
            statusS = string(T.Status);
            pct = double(T.Percent);
            pct(isnan(pct)) = 0;

            data = table(src, out, durS, sizeS, statusS, pct, ...
                'VariableNames', {'Source','Output','Dur','Size','Status','Percent'});
            obj.FileTable.Data = data;
        end

        function setControlsEnabled_(obj, tf)
            state = matlab.lang.OnOffSwitchState(tf);
            obj.ScanButton.Enable = state;
            obj.RootFolderField.Enable = state;
            obj.BrowseRootButton.Enable = state;
            obj.PatternField.Enable = state;
            obj.ExcludeField.Enable = state;
            obj.RecursiveCheckBox.Enable = state;
            obj.PresetDropDown.Enable = state;
            obj.VideoCodecDropDown.Enable = state;
            obj.AudioCodecDropDown.Enable = state;
            obj.FrameRateSpinner.Enable = state;
            obj.ScaleSpinner.Enable = state;
            obj.RangeStartField.Enable = state;
            obj.RangeStopField.Enable = state;
            obj.AlongsideCheckBox.Enable = state;
            obj.MirrorTreeCheckBox.Enable = state;
            obj.NameSuffixField.Enable = state;
            obj.OutputExtensionDropDown.Enable = state;
            obj.OverwriteDropDown.Enable = state;
            obj.MaxParallelSpinner.Enable = state;
            obj.DeleteSourceCheckBox.Enable = state;
            obj.DryRunCheckBox.Enable = state;
            if tf
                obj.updateEncodingEnable_();
                obj.updateOutputEnable_();
            end
            obj.ConvertButton.Enable = state;
            obj.CancelButton.Enable = matlab.lang.OnOffSwitchState(~tf);
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

    methods (Static, Access = private)
        function r = relPath_(root, p)
            root = string(root);
            p = string(p);
            if root == ""
                r = p;
                return
            end
            rr = root;
            if ~endsWith(rr, filesep)
                rr = rr + filesep;
            end
            if startsWith(p, rr, 'IgnoreCase', ispc)
                r = extractAfter(p, strlength(rr));
            else
                r = p;
            end
        end

        function s = humanBytes_(b)
            if isnan(b)
                s = "-";
            elseif b >= 1024^3
                s = string(sprintf('%.2f GB', b/1024^3));
            elseif b >= 1024^2
                s = string(sprintf('%.1f MB', b/1024^2));
            elseif b >= 1024
                s = string(sprintf('%.1f KB', b/1024));
            else
                s = string(sprintf('%d B', b));
            end
        end
    end

end
