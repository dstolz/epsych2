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
    %   PersistPrefs  logical (default = true) Remember the window position
    %                                          and the settings (see
    %                                          PrefFields) between sessions,
    %                                          in getpref/setpref group
    %                                          'ep_VideoConverter'.
    %
    % Note: the GUI configures and drives the Converter you pass in, but does
    % not own its lifetime -- closing the GUI never cancels or deletes it.
    %
    % A remembered setting is applied only where the caller left the property
    % at its class default, so util.VideoConverter(MaxParallel=4) still gets 4.
    % Reset puts every setting back to util.VideoConverter's own defaults.
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
        ResetButton
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

        X264Presets = ["ultrafast","superfast","veryfast","faster","fast", ...
            "medium","slow","slower","veryslow"]

        % Converter properties remembered between sessions, under the
        % 'ep_VideoConverter' preference group. DeleteSource and DryRun are
        % deliberately absent: a destructive option and a preview mode are
        % decisions for the batch in front of the operator, never inherited
        % from whatever they happened to be doing last week.
        PrefFields = ["RootFolder","FilePattern","ExcludePattern","Recursive", ...
            "OutputFolder","MirrorTree","NameSuffix","OutputExtension", ...
            "VideoCodec","x264Crf","x264Preset","AudioCodec", ...
            "OutputFrameRate","VideoScale","Range","Overwrite","MaxParallel"]

        % Restored by Reset. The two folders are deliberately absent: they
        % are where this batch reads and writes, not a setting with a
        % recommended value, and losing a typed path to a Reset would be
        % worse than anything the button fixes.
        ResetFields = ["FilePattern","ExcludePattern","Recursive","MirrorTree", ...
            "NameSuffix","OutputExtension","VideoCodec","x264Crf","x264Preset", ...
            "AudioCodec","OutputFrameRate","VideoScale","Range","Overwrite", ...
            "MaxParallel","DeleteSource","DryRun"]

        % Side-column geometry. The panels are a fixed-height stack inside a
        % scrollable column, so each one's height is derived from its own row
        % count (panelHeight_) rather than hand-tuned: adding a row to a panel
        % can then never clip its last control.
        PanelRowHeight  = 24
        PanelRowSpacing = 6
        PanelPadding    = 8
        PanelTitleHeight = 24
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

            % Restore remembered settings into the Converter BEFORE the
            % widgets read it, so there is still exactly one path from
            % converter state to what is on screen.
            obj.applySavedPrefs_();

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
                % The saved Position is the user's own sizing, but a height
                % from an earlier layout can be too short for the panels;
                % ensureContentFits_ grows it once the panels are built.
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
            % 'Convert' over the tick column, 'Do' as its variable name: the
            % header has to say what ticking means, the way '%' already sits
            % over the variable named Percent.
            obj.FileTable.ColumnName = {'Convert','Source','Output','Dur','Size','Status','%'};
            % The right-hand columns hold short, bounded strings, so give them
            % exactly what they need and let the two path columns share the
            % rest: everything stays visible without a horizontal scroll.
            obj.FileTable.ColumnWidth = {60,'1x','1x',60,80,90,50};
            % Only the tick is editable -- a logical column renders as a
            % checkbox, which is the whole point of keeping it a table.
            obj.FileTable.ColumnEditable = [true false false false false false false];
            obj.FileTable.Data = table(true(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), strings(0,1), ...
                'VariableNames', {'Do','Source','Output','Dur','Size','Status','Percent'});
            obj.FileTable.SelectionType = 'row';
            obj.FileTable.CellEditCallback = @(s,e) obj.onFileTableEdit(s,e);
            obj.buildFileTableMenu_();

            % --- Side column (scrollable) ---
            obj.SideGrid = uigridlayout(obj.RootGrid, [4 1]);
            obj.SideGrid.Layout.Row = 1;
            obj.SideGrid.Layout.Column = 2;
            obj.SideGrid.Padding = [0 0 0 0];
            obj.SideGrid.RowSpacing = obj.PanelRowSpacing;
            % Each panel sets its own row height from its content; the column
            % stays scrollable for windows too short to show the whole stack.
            obj.SideGrid.RowHeight = repmat({0}, 1, 4);
            obj.SideGrid.Scrollable = 'on';

            obj.buildSourcePanel_();
            obj.buildEncodingPanel_();
            obj.buildOutputPanel_();
            obj.buildRunPanel_();

            % Now that the panels have declared their heights, size the window
            % to them. Done here rather than from a table of row counts so the
            % two can never fall out of step.
            if obj.OwnsParentFigure
                obj.ensureContentFits_();
            end

            % --- Bottom row: actions + overall progress ---
            bottomGrid = uigridlayout(obj.RootGrid, [1 5]);
            bottomGrid.Layout.Row = 2;
            bottomGrid.Layout.Column = [1 2];
            bottomGrid.ColumnWidth = {90, 90, 90, 90, '1x'};
            bottomGrid.Padding = [0 0 0 0];
            bottomGrid.ColumnSpacing = 8;

            obj.ScanButton = uibutton(bottomGrid, 'Text', 'Scan', 'Tag', 'VideoConverterSetup_ScanButton');
            obj.ConvertButton = uibutton(bottomGrid, 'Text', 'Convert', 'Tag', 'VideoConverterSetup_ConvertButton');
            obj.CancelButton = uibutton(bottomGrid, 'Text', 'Cancel', 'Tag', 'VideoConverterSetup_CancelButton', 'Enable', 'off');
            obj.ResetButton = uibutton(bottomGrid, 'Text', 'Reset', 'Tag', 'VideoConverterSetup_ResetButton');
            obj.OverallLabel = uilabel(bottomGrid, 'Text', '', 'HorizontalAlignment', 'right', 'Tag', 'VideoConverterSetup_OverallLabel');

            obj.ScanButton.Tooltip = 'Search the root folder for matching videos and plan an output path for each one. Re-scanning discards the current list.';
            obj.ConvertButton.Tooltip = 'Convert every file still listed as pending. Runs in the background -- the window stays usable.';
            obj.CancelButton.Tooltip = 'Stop the batch: running ffmpeg processes are killed and their partial files discarded. Files already finished are kept.';
            obj.ResetButton.Tooltip = 'Restore every setting to its recommended default. The root and output folders are left alone.';

            % --- Status line ---
            obj.StatusLabel = uilabel(obj.RootGrid, 'Text', '', 'FontColor', [0.20 0.20 0.20]);
            obj.StatusLabel.Layout.Row = 3;
            obj.StatusLabel.Layout.Column = [1 2];

            obj.ScanButton.ButtonPushedFcn = @(s,e) obj.onScan(s,e);
            obj.ConvertButton.ButtonPushedFcn = @(s,e) obj.onConvert(s,e);
            obj.CancelButton.ButtonPushedFcn = @(s,e) obj.onCancel(s,e);
            obj.ResetButton.ButtonPushedFcn = @(s,e) obj.onReset(s,e);
        end

        function g = panelGrid_(obj, p, nRows)
            % Build a side panel's nRows-by-2 grid and size the panel's row in
            % SideGrid to hold it. One place computes the height, so a panel
            % and its container can never disagree about how tall it is.
            g = uigridlayout(p, [nRows 2]);
            g.RowHeight = repmat({obj.PanelRowHeight}, 1, nRows);
            g.RowSpacing = obj.PanelRowSpacing;
            g.Padding = repmat(obj.PanelPadding, 1, 4);
            obj.SideGrid.RowHeight{p.Layout.Row} = obj.panelHeight_(nRows);
        end

        function ensureContentFits_(obj)
            % Grow the window until the whole panel stack is visible. Only
            % ever grows: the user's own sizing is kept, and a Position saved
            % under an earlier layout cannot strand controls out of view. The
            % side column stays scrollable for screens too short for even
            % this, which is the only case that still needs it.
            need = obj.sideColumnHeight_() + obj.rootChromeHeight_();
            screen = get(groot, 'ScreenSize');
            need = min(need, screen(4) - 100);   % leave room for title bar and taskbar
            if obj.Parent.Position(4) < need
                obj.Parent.Position(4) = need;
                movegui(obj.Parent, 'onscreen');
            end
        end

        function h = sideColumnHeight_(obj)
            % Height the panel stack needs to show every control at once.
            h = sum([obj.SideGrid.RowHeight{:}]) ...
                + (numel(obj.SideGrid.RowHeight) - 1)*obj.SideGrid.RowSpacing;
        end

        function h = rootChromeHeight_(obj)
            % Everything RootGrid spends outside the table/side row: its own
            % padding, the two row gaps, and the action and status rows.
            h = obj.RootGrid.Padding(2) + obj.RootGrid.Padding(4) ...
                + 2*obj.RootGrid.RowSpacing ...
                + obj.RootGrid.RowHeight{2} + obj.RootGrid.RowHeight{3};
        end

        function h = panelHeight_(obj, nRows)
            % Height of a panel whose grid holds nRows content rows, including
            % the grid's padding and the panel's own title bar.
            h = nRows*obj.PanelRowHeight + (nRows-1)*obj.PanelRowSpacing ...
                + 2*obj.PanelPadding + obj.PanelTitleHeight;
        end

        function buildSourcePanel_(obj)
            p = uipanel(obj.SideGrid, 'Title', 'Source');
            p.Layout.Row = 1;
            g = obj.panelGrid_(p, 4);
            g.ColumnWidth = {80, '1x'};

            rootLabel = uilabel(g, 'Text', 'Root folder');
            rootRow = uigridlayout(g, [1 2]);
            rootRow.ColumnWidth = {'1x', 70};
            rootRow.Padding = [0 0 0 0];
            obj.RootFolderField = uieditfield(rootRow, 'text', 'Tag', 'VideoConverterSetup_RootFolderField');
            obj.BrowseRootButton = uibutton(rootRow, 'Text', 'Browse', 'Tag', 'VideoConverterSetup_BrowseRootButton');

            patternLabel = uilabel(g, 'Text', 'Pattern');
            obj.PatternField = uieditfield(g, 'text', 'Tag', 'VideoConverterSetup_PatternField');

            excludeLabel = uilabel(g, 'Text', 'Exclude');
            obj.ExcludeField = uieditfield(g, 'text', 'Tag', 'VideoConverterSetup_ExcludeField');

            uilabel(g, 'Text', '');
            obj.RecursiveCheckBox = uicheckbox(g, 'Text', 'Recursive', 'Tag', 'VideoConverterSetup_RecursiveCheckBox');

            obj.tip_('Top of the folder tree to search for source videos.', ...
                rootLabel, obj.RootFolderField);
            obj.BrowseRootButton.Tooltip = 'Choose the folder to search.';
            obj.tip_(['Regular expression a file NAME must match to be included. ' ...
                'The default matches the common video extensions, case-insensitively.'], ...
                patternLabel, obj.PatternField);
            obj.tip_(['Regular expression that drops a file even when it matches Pattern. ' ...
                'The default keeps already-converted "_conv" outputs and leftover ".part" ' ...
                'sidecars out of a re-scan.'], ...
                excludeLabel, obj.ExcludeField);
            obj.RecursiveCheckBox.Tooltip = 'Search subfolders of the root folder as well.';

            obj.RootFolderField.ValueChangedFcn = @(s,e) obj.onSourceOptionChanged(s,e);
            obj.BrowseRootButton.ButtonPushedFcn = @(s,e) obj.onBrowseRoot(s,e);
            obj.PatternField.ValueChangedFcn = @(s,e) obj.onSourceOptionChanged(s,e);
            obj.ExcludeField.ValueChangedFcn = @(s,e) obj.onSourceOptionChanged(s,e);
            obj.RecursiveCheckBox.ValueChangedFcn = @(s,e) obj.onSourceOptionChanged(s,e);
        end

        function buildEncodingPanel_(obj)
            p = uipanel(obj.SideGrid, 'Title', 'Encoding');
            p.Layout.Row = 2;
            g = obj.panelGrid_(p, 8);
            g.ColumnWidth = {100, '1x'};

            presetLabel = uilabel(g, 'Text', 'Preset');
            obj.PresetDropDown = uidropdown(g, 'Items', cellstr(obj.PresetNames), 'Tag', 'VideoConverterSetup_PresetDropDown');

            codecLabel = uilabel(g, 'Text', 'Video codec');
            obj.VideoCodecDropDown = uidropdown(g, 'Items', {'x264','mpeg4','copy','none'}, 'Tag', 'VideoConverterSetup_VideoCodecDropDown');

            crfLabel = uilabel(g, 'Text', 'CRF');
            obj.CrfSpinner = uispinner(g, 'Limits', [1 51], 'RoundFractionalValues', 'on', 'Tag', 'VideoConverterSetup_CrfSpinner');

            x264Label = uilabel(g, 'Text', 'x264 preset');
            obj.X264PresetDropDown = uidropdown(g, ...
                'Items', cellstr(obj.X264Presets), ...
                'Tag', 'VideoConverterSetup_X264PresetDropDown');

            audioLabel = uilabel(g, 'Text', 'Audio codec');
            obj.AudioCodecDropDown = uidropdown(g, 'Items', {'aac','mp3','wav','copy','none'}, 'Tag', 'VideoConverterSetup_AudioCodecDropDown');

            fpsLabel = uilabel(g, 'Text', 'Frame rate');
            obj.FrameRateSpinner = uispinner(g, 'Limits', [0 240], 'RoundFractionalValues', 'on', ...
                'ValueDisplayFormat', '%d fps (0=source)', 'Tag', 'VideoConverterSetup_FrameRateSpinner');

            scaleLabel = uilabel(g, 'Text', 'Scale');
            obj.ScaleSpinner = uispinner(g, 'Limits', [0.05 4], 'Step', 0.05, ...
                'ValueDisplayFormat', '%.2fx', 'Tag', 'VideoConverterSetup_ScaleSpinner');

            rangeLabel = uilabel(g, 'Text', 'Range (s)');
            rangeRow = uigridlayout(g, [1 2]);
            rangeRow.Padding = [0 0 0 0];
            obj.RangeStartField = uieditfield(rangeRow, 'numeric', 'Limits', [0 Inf], 'Tag', 'VideoConverterSetup_RangeStartField');
            obj.RangeStopField = uieditfield(rangeRow, 'numeric', 'Limits', [0 Inf], 'Tag', 'VideoConverterSetup_RangeStopField');

            obj.tip_(['A named starting point for the settings below. Changing any one ' ...
                'of them switches this to "Custom"; the preset is not re-applied.'], ...
                presetLabel, obj.PresetDropDown);
            obj.tip_(['x264 = H.264 re-encode. mpeg4 = older MPEG-4 Part 2. ' ...
                'copy = keep the existing video stream untouched (fast and lossless, ' ...
                'but nothing can be scaled or re-encoded). none = drop the video.'], ...
                codecLabel, obj.VideoCodecDropDown);
            obj.tip_(['x264 constant rate factor: lower means better quality and a bigger ' ...
                'file. 18 is visually lossless, 23 is ffmpeg''s default, 28 is preview ' ...
                'quality. Applies to the x264 codec only.'], ...
                crfLabel, obj.CrfSpinner);
            obj.tip_(['Encoder speed against compression. A slower preset takes longer to ' ...
                'produce a smaller file at the same CRF -- it does not change quality. ' ...
                'Applies to the x264 codec only.'], ...
                x264Label, obj.X264PresetDropDown);
            obj.tip_(['aac / mp3 / wav re-encode the audio track. copy passes it through ' ...
                'untouched. none drops it.'], ...
                audioLabel, obj.AudioCodecDropDown);
            obj.tip_('Output frames per second. 0 keeps each source''s own rate.', ...
                fpsLabel, obj.FrameRateSpinner);
            obj.tip_(['Resize factor for both dimensions, so 0.50x is a quarter of the area. ' ...
                '1.00x leaves the size alone. Resizing needs a re-encode, so this is forced ' ...
                'back to 1.00x when the video codec is "copy".'], ...
                scaleLabel, obj.ScaleSpinner);
            obj.tip_(['Start and stop time in seconds, cut from every source video. ' ...
                'Leave both at 0 (or stop at or before start) to convert whole files.'], ...
                rangeLabel, obj.RangeStartField, obj.RangeStopField);

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
            g = obj.panelGrid_(p, 4);
            g.ColumnWidth = {80, '1x'};

            uilabel(g, 'Text', '');
            obj.AlongsideCheckBox = uicheckbox(g, 'Text', 'Alongside source', 'Tag', 'VideoConverterSetup_AlongsideCheckBox');

            folderLabel = uilabel(g, 'Text', 'Folder');
            outRow = uigridlayout(g, [1 2]);
            outRow.ColumnWidth = {'1x', 70};
            outRow.Padding = [0 0 0 0];
            obj.OutputFolderField = uieditfield(outRow, 'text', 'Tag', 'VideoConverterSetup_OutputFolderField');
            obj.BrowseOutputButton = uibutton(outRow, 'Text', 'Browse', 'Tag', 'VideoConverterSetup_BrowseOutputButton');

            uilabel(g, 'Text', '');
            obj.MirrorTreeCheckBox = uicheckbox(g, 'Text', 'Mirror folder tree', 'Tag', 'VideoConverterSetup_MirrorTreeCheckBox');

            suffixLabel = uilabel(g, 'Text', 'Suffix / Ext');
            sufRow = uigridlayout(g, [1 2]);
            sufRow.ColumnWidth = {'1x', 80};
            sufRow.Padding = [0 0 0 0];
            obj.NameSuffixField = uieditfield(sufRow, 'text', 'Tag', 'VideoConverterSetup_NameSuffixField');
            obj.OutputExtensionDropDown = uidropdown(sufRow, 'Items', {'.mp4','.avi','.mkv','.ts'}, 'Tag', 'VideoConverterSetup_OutputExtensionDropDown');

            obj.AlongsideCheckBox.Tooltip = ['Write each converted file next to its source ' ...
                'instead of into an output folder.'];
            obj.tip_('Destination root for the converted files.', folderLabel, obj.OutputFolderField);
            obj.BrowseOutputButton.Tooltip = 'Choose the output folder.';
            obj.MirrorTreeCheckBox.Tooltip = ['Recreate the source subfolder structure under ' ...
                'the output folder. Without it every output lands in that one folder, where ' ...
                'same-named files from different subfolders would collide.'];
            obj.tip_(['Text appended to each output file name, and the container the output ' ...
                'is written in. A non-empty suffix is what stops an output overwriting its ' ...
                'own source when the two share a folder and an extension.'], ...
                suffixLabel, obj.NameSuffixField, obj.OutputExtensionDropDown);

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
            g = obj.panelGrid_(p, 4);
            g.ColumnWidth = {100, '1x'};

            conflictLabel = uilabel(g, 'Text', 'On conflict');
            obj.OverwriteDropDown = uidropdown(g, 'Items', {'skip','overwrite','error'}, 'Tag', 'VideoConverterSetup_OverwriteDropDown');

            parallelLabel = uilabel(g, 'Text', 'Parallel jobs');
            obj.MaxParallelSpinner = uispinner(g, 'Limits', [1 8], 'RoundFractionalValues', 'on', 'Tag', 'VideoConverterSetup_MaxParallelSpinner');

            uilabel(g, 'Text', '');
            obj.DeleteSourceCheckBox = uicheckbox(g, 'Text', 'Delete source after conversion', ...
                'FontColor', [0.70 0.10 0.10], 'Tag', 'VideoConverterSetup_DeleteSourceCheckBox');

            uilabel(g, 'Text', '');
            obj.DryRunCheckBox = uicheckbox(g, 'Text', 'Dry run (preview only)', 'Tag', 'VideoConverterSetup_DryRunCheckBox');

            obj.tip_(['What to do when the planned output file already exists: leave it and ' ...
                'skip that source, overwrite it, or stop with an error.'], ...
                conflictLabel, obj.OverwriteDropDown);
            obj.tip_(['How many files are converted at once. More is faster only until the ' ...
                'CPU saturates -- each x264 encode is already multithreaded.'], ...
                parallelLabel, obj.MaxParallelSpinner);
            obj.DeleteSourceCheckBox.Tooltip = ['Delete each source file once its output has ' ...
                'been written and verified. There is no undo, and this is never remembered ' ...
                'between sessions.'];
            obj.DryRunCheckBox.Tooltip = ['List every conversion and its output path without ' ...
                'running ffmpeg. Use it to check the file list before committing to a batch.'];

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
            obj.setDropDownValue_(obj.X264PresetDropDown, c.x264Preset);
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
            obj.setDropDownValue_(obj.OutputExtensionDropDown, c.OutputExtension);
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

        function tip_(~, txt, varargin)
            % Put one explanation on a form row's label AND on the controls it
            % names. A 80-100 px label is a poor hover target, and the control
            % is what an operator actually points at, so neither alone is
            % enough -- but they must never say two different things.
            for k = 1:numel(varargin)
                varargin{k}.Tooltip = txt;
            end
        end

        function setDropDownValue_(~, dd, v)
            % Show a value the Items list does not offer rather than erroring
            % on it: a remembered or scripted setting (an unusual container, a
            % newer x264 preset) is legitimate even though this GUI only lists
            % the common ones.
            v = char(v);
            if ~any(strcmp(dd.Items, v))
                dd.Items = [dd.Items, {v}];
            end
            dd.Value = v;
        end

        function d = classDefault_(~, name)
            % The recommended value for a converter property IS the default
            % util.VideoConverter declares for it. Read it from the class so
            % this GUI cannot drift from the class it configures.
            persistent props
            if isempty(props)
                mc = ?util.VideoConverter;
                props = mc.PropertyList;
            end
            p = props(strcmp({props.Name}, name));
            if isempty(p) || ~p.HasDefault
                error('gui:VideoConverterSetup:NoDefault', ...
                    'util.VideoConverter.%s declares no default value.', name);
            end
            d = p.DefaultValue;
        end

        function applySavedPrefs_(obj)
            % Restore the settings this operator last used -- but only where
            % the caller left the property at its class default. A converter
            % constructed with MaxParallel=4 meant 4, and a value remembered
            % from last week must not quietly override code that asked for
            % something.
            if ~obj.PersistPrefs_
                return
            end
            s = getpref('ep_VideoConverter', 'Settings', struct());
            for f = obj.PrefFields
                if ~isfield(s, f)
                    continue
                end
                try
                    if isequal(obj.Converter.(f), obj.classDefault_(f))
                        obj.Converter.(f) = s.(f);
                    end
                catch ME
                    % A stale or hand-edited preference must cost one setting,
                    % not the window.
                    vprintf(1, 'VideoConverterSetup: ignoring remembered %s -- %s', f, ME.message);
                end
            end
        end

        function savePrefs_(obj)
            % Remember the current settings for the next session. Called from
            % every path that writes to the Converter, so what is remembered
            % is always what the operator last saw.
            if ~obj.PersistPrefs_
                return
            end
            s = struct();
            for f = obj.PrefFields
                s.(f) = obj.Converter.(f);
            end
            setpref('ep_VideoConverter', 'Settings', s);
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
            obj.savePrefs_();
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
            obj.savePrefs_();
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
            obj.savePrefs_();
        end

        function onOutputOptionChanged(obj, ~, ~)
            if ~obj.AlongsideCheckBox.Value
                obj.Converter.OutputFolder = string(obj.OutputFolderField.Value);
            end
            obj.Converter.MirrorTree = obj.MirrorTreeCheckBox.Value;
            obj.Converter.NameSuffix = string(obj.NameSuffixField.Value);
            obj.Converter.OutputExtension = string(obj.OutputExtensionDropDown.Value);
            obj.savePrefs_();
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
            obj.savePrefs_();
        end

        function onReset(obj, ~, ~)
            % Put every setting back to util.VideoConverter's own defaults.
            % The folders are left alone: they are this batch's addresses, not
            % settings, and losing a typed path here would be worse than
            % anything the button fixes.
            for f = obj.ResetFields
                obj.Converter.(f) = obj.classDefault_(f);
            end
            obj.initFromConverter();   % widgets follow the converter, one path only
            obj.savePrefs_();
            obj.setStatus('Settings restored to their recommended defaults; folders kept.');
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
            % Checked before the controls are disabled: convert() returns
            % without starting a batch, so no 'finished' event would ever
            % arrive to enable them again.
            if ~any(obj.Converter.Results.Selected)
                obj.setStatus('No files are ticked for conversion.', true);
                return
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
            % Whole percent as text: a double column renders as "42.5000" in
            % a uitable, which needs a wide column to say very little.
            pct = double(T.Percent);
            pctS = compose("%.0f", pct);
            pctS(isnan(pct)) = "-";

            data = table(logical(T.Selected), src, out, durS, sizeS, statusS, pctS, ...
                'VariableNames', {'Do','Source','Output','Dur','Size','Status','Percent'});
            obj.FileTable.Data = data;
        end

        function buildFileTableMenu_(obj)
            % Right-click menu on the file list: what to convert, and a way to
            % look at a file before deciding.
            m = uicontextmenu(ancestor(obj.Parent, 'figure'));
            uimenu(m, 'Text', 'Open Video', 'MenuSelectedFcn', @(s,e) obj.onOpenFile('source'));
            uimenu(m, 'Text', 'Open Converted Video', 'MenuSelectedFcn', @(s,e) obj.onOpenFile('output'));
            uimenu(m, 'Text', 'Open Containing Folder', 'MenuSelectedFcn', @(s,e) obj.onOpenFile('folder'));
            uimenu(m, 'Text', 'Include Highlighted Rows', 'Separator', 'on', ...
                'MenuSelectedFcn', @(s,e) obj.onSelectRows('rows', true));
            uimenu(m, 'Text', 'Exclude Highlighted Rows', 'MenuSelectedFcn', @(s,e) obj.onSelectRows('rows', false));
            uimenu(m, 'Text', 'Include All Files', 'Separator', 'on', ...
                'MenuSelectedFcn', @(s,e) obj.onSelectRows('all', true));
            uimenu(m, 'Text', 'Exclude All Files', 'MenuSelectedFcn', @(s,e) obj.onSelectRows('all', false));
            obj.FileTable.ContextMenu = m;
            obj.FileTable.Tooltip = ['Tick a file to include it in the next Convert. ' ...
                'Right-click to open a file, or to tick and untick whole blocks.'];
        end

        function onFileTableEdit(obj, ~, evt)
            % The tick column is the only editable one, so any edit is a
            % selection change. The Converter owns the state; the table is
            % refreshed from it so a refused edit visibly snaps back.
            row = evt.Indices(1);
            obj.Converter.select(row, logical(evt.NewData));
            obj.refreshFileTable_();
        end

        function onSelectRows(obj, scope, tf)
            n = height(obj.Converter.Results);
            if n == 0
                return
            end
            if strcmp(scope, 'all')
                rows = (1:n)';
            else
                rows = obj.FileTable.Selection;
                if isempty(rows)
                    obj.setStatus('Highlight one or more rows first.', true);
                    return
                end
            end
            obj.Converter.select(rows, tf);
            obj.refreshFileTable_();
            obj.setStatus(sprintf('%d of %d file(s) will be converted.', ...
                nnz(obj.Converter.Results.Selected), n));
        end

        function onOpenFile(obj, what)
            % Hand one file (or its folder) to the operating system. Limited
            % to a single highlighted row on purpose: "open" means a player
            % window or an Explorer window, and a careless right-click on 200
            % highlighted rows should not open 200 of them.
            rows = obj.FileTable.Selection;
            if numel(rows) ~= 1
                obj.setStatus('Highlight exactly one row to open it.', true);
                return
            end
            T = obj.Converter.Results;
            switch what
                case 'source'
                    target = T.SourceFile(rows);
                case 'output'
                    target = T.OutputFile(rows);
                case 'folder'
                    target = fileparts(T.SourceFile(rows));
            end
            if target == "" || ~(isfile(target) || isfolder(target))
                obj.setStatus(sprintf('Not on disk yet: %s', target), true);
                return
            end
            obj.openInShell_(target);
        end

        function openInShell_(obj, target)
            % winopen hands a file to whatever the operator has associated
            % with it, and a folder to Explorer -- the same thing a
            % double-click would do, which is what "open" has to mean here.
            try
                if ispc
                    winopen(char(target));
                elseif ismac
                    system(sprintf('open "%s" &', target));
                else
                    system(sprintf('xdg-open "%s" &', target));
                end
                obj.setStatus(sprintf('Opened %s', target));
            catch ME
                vprintf(0, 1, ME);
                obj.setStatus(sprintf('Could not open %s', target), true);
            end
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
            obj.ResetButton.Enable = state;
            % The queue is built once at convert(), so a tick changed mid-run
            % would be a lie: the Converter refuses it and the table would
            % snap back. Better not to offer it.
            obj.FileTable.ColumnEditable = [tf false false false false false false];
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
