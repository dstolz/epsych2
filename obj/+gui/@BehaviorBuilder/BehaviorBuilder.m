classdef BehaviorBuilder < handle
    % gui.BehaviorBuilder  Design-time builder for gui.BehaviorGUI subclasses.
    %
    %   gui.BehaviorBuilder            % open an empty builder
    %   gui.BehaviorBuilder(specFile)  % open an existing .eblt layout spec
    %
    %   Load a protocol (.eprot) to enumerate its parameters, pick components
    %   from the palette, drag rectangles on the snap-to-grid canvas to place
    %   them, and configure each region in its dialog. The design round-trips
    %   through an .eblt layout-spec file (JSON) that the builder can re-open,
    %   and exports a readable gui.BehaviorGUI subclass whose build() targets
    %   only the documented helper API (addControl, addButton, controlColumn,
    %   addMonitor, ...), so the generated GUI survives the SelfTest I6
    %   empty-runtime launch like a hand-written one.
    %
    %   The spec model and the code generator are usable headlessly:
    %       spec = gui.BehaviorBuilder.specNew;
    %       ... fill spec.Regions ...
    %       gui.BehaviorBuilder.saveSpecFile(spec, 'MyTask.eblt');
    %       gui.BehaviorBuilder.writeCode(spec, 'MyTask.eblt', 'MyTaskGUI.m');
    %
    % See also gui.BehaviorGUI, documentation/gui/gui_BehaviorBuilder.md

    properties (SetAccess = private)
        Spec        struct              % layout spec (schema: specNew)
        SpecFile    (1,:) char = ''     % path of the open .eblt ('' = unsaved)
        Protocol    = []                % epsych.Protocol or []
        Parameters  = []                % flattened hw.Parameter array or []
        Dirty       (1,1) logical = false
        SelectedId  (1,:) char = ''     % Id of the selected region ('' = none)
    end

    properties (Access = private, Transient)
        Fig                             % main uifigure
        Axes                            % canvas uiaxes
        ROIs                            % containers.Map Id -> images.roi.Rectangle
        PlaceholderTexts                % containers.Map Id -> text (label fallback)
        ArmedType   (1,:) char = ''     % palette-armed component type
        PreDrag_    = []                % struct Row/Col captured at MovingROI start

        % ui handles (created in buildUI)
        Palette; PaletteDescription; ProtocolLabel; ProtocolSummary
        InspectorPanel; InspectorGrid
        ClassNameField; WindowNameField; SizeWField; SizeHField
        RowsSpinner; ColsSpinner; PsychTypeDD; PsychParamDD; PsychTargetDD
        DegradedBanner; RecentMenu
    end

    properties (Constant, Hidden)
        PREF_TAG       = 'gui_BehaviorBuilder'
        SPEC_EXT       = '.eblt'
        FORMAT_VERSION = 1
        MAX_GRID       = 20
        ROI_INSET      = 0.05  % cells; gap between region ROIs so adjacent
                               % borders stay visibly separate on the canvas
        PALETTE_HINT   = 'Select a component to see its description, then drag a rectangle on the canvas to place it.'
        WIKI_URL       = 'https://github.com/dstolz/epsych2/wiki/Behavior-GUI-Builder'
    end

    methods
        function obj = BehaviorBuilder(specFile)
            arguments
                specFile (1,:) char = ''
            end
            obj.Spec = gui.BehaviorBuilder.specNew;
            obj.ROIs = containers.Map('KeyType','char','ValueType','any');
            obj.PlaceholderTexts = containers.Map('KeyType','char','ValueType','any');

            obj.buildUI;
            if ~isempty(specFile)
                obj.openSpec(specFile);
            else
                obj.refreshAll_;
            end
            if nargout == 0, clear obj; end % figure UserData keeps the object alive
        end

        function delete(obj)
            try %#ok<TRYNC>
                if ~isempty(obj.Fig) && isvalid(obj.Fig)
                    gui.BehaviorGUI.saveFigurePosition(obj.PREF_TAG, obj.Fig.Position);
                    obj.Fig.CloseRequestFcn = '';
                    delete(obj.Fig);
                end
            end
        end

        % method files ----------------------------------------------------
        buildUI(obj)
        drawCanvas(obj)
        ok = configureRegion(obj, id, isNew)
        exportCode(obj)

        function openSpec(obj, filename)
            % Load an .eblt file into the builder; reloads its protocol.
            try
                spec = gui.BehaviorBuilder.loadSpecFile(filename);
            catch ME
                vprintf(0,1,ME)
                uialert(obj.Fig, sprintf('Could not open layout spec:\n%s', ME.message), ...
                    'Open failed');
                return
            end
            obj.Spec = spec;
            obj.SpecFile = char(filename);
            obj.SelectedId = '';
            obj.Dirty = false;
            obj.Protocol = [];
            obj.Parameters = [];
            if ~isempty(spec.ProtocolPath) && isfile(spec.ProtocolPath)
                obj.loadProtocol(spec.ProtocolPath);
            end
            obj.rememberRecent_(char(filename));
            obj.refreshAll_;
        end

        function tf = saveSpec(obj, saveAs)
            % Save the current spec; prompts for a filename when unnamed.
            arguments
                obj
                saveAs (1,1) logical = false
            end
            tf = false;
            fn = obj.SpecFile;
            if saveAs || isempty(fn)
                seed = [char(obj.Spec.ClassName) obj.SPEC_EXT];
                if ~isempty(fn), seed = fn; end
                [f,p] = uiputfile({['*' obj.SPEC_EXT], 'Behavior layout spec (*.eblt)'}, ...
                    'Save Layout Spec', seed);
                if isequal(f,0), return, end
                fn = fullfile(p,f);
            end
            try
                gui.BehaviorBuilder.saveSpecFile(obj.Spec, fn);
            catch ME
                vprintf(0,1,ME)
                uialert(obj.Fig, sprintf('Could not save layout spec:\n%s', ME.message), ...
                    'Save failed');
                return
            end
            obj.SpecFile = fn;
            obj.Dirty = false;
            obj.rememberRecent_(fn);
            obj.updateTitle_;
            tf = true;
        end

        function loadProtocol(obj, filename)
            % Load a protocol and refresh the parameter snapshot from it.
            arguments
                obj
                filename (1,:) char = ''
            end
            if isempty(filename)
                filt = {'*.eprot', 'Protocol Files (*.eprot)'};
                [f,p] = uigetfile(filt, 'Load Protocol');
                if isequal(f,0), return, end
                filename = fullfile(p,f);
            end
            try
                P = epsych.Protocol.load(filename);
                params = hw.Parameter.empty(1,0);
                for iface = P.Interfaces
                    params = [params, iface.all_parameters(includeTriggers=true)]; %#ok<AGROW>
                end
            catch ME
                vprintf(0,1,ME)
                if ~isempty(obj.Fig) && isvalid(obj.Fig)
                    uialert(obj.Fig, sprintf('Could not load protocol:\n%s', ME.message), ...
                        'Protocol load failed');
                end
                return
            end
            obj.Protocol = P;
            obj.Parameters = params;
            obj.Spec.ProtocolPath = char(filename);
            obj.Spec.ParameterSnapshot = gui.BehaviorBuilder.snapshotFromParameters(params);
            obj.markDirty_;
            obj.refreshAll_;
        end

        function addRegion(obj, type, rowSpan, colSpan)
            % Add a region programmatically (canvas draw callbacks land here).
            spec = obj.Spec;
            id = obj.nextRegionId_;
            r = struct('Id',id, 'Type',char(type), ...
                'Label',gui.BehaviorBuilder.catalogEntry(type).Display, ...
                'Row',rowSpan, 'Col',colSpan, 'PopOut',false, ...
                'Options',gui.BehaviorBuilder.defaultOptions(type));
            spec.Regions(end+1) = r;
            % validate placement (span bounds + overlap); revert on failure
            try
                spec = gui.BehaviorBuilder.specValidate(spec);
            catch ME
                vprintf(2,'Region placement rejected: %s', ME.message)
                return
            end
            obj.Spec = spec;
            obj.SelectedId = id;
            obj.markDirty_;
            ok = obj.configureRegion(id, true);
            if ~ok
                obj.removeRegion(id);
                return
            end
            obj.refreshAll_;
        end

        function removeRegion(obj, id)
            ix = strcmp({obj.Spec.Regions.Id}, id);
            if ~any(ix), return, end
            obj.Spec.Regions(ix) = [];
            if strcmp(obj.SelectedId, id), obj.SelectedId = ''; end
            obj.markDirty_;
            obj.refreshAll_;
        end

        function resetSpec_(obj)
            obj.Spec = gui.BehaviorBuilder.specNew;
            obj.SpecFile = '';
            obj.SelectedId = '';
            obj.Dirty = false;
            obj.Protocol = [];
            obj.Parameters = [];
            obj.refreshAll_;
        end

        function setSpecField_(obj, field, value)
            obj.Spec.(field) = value;
            obj.markDirty_;
        end

        function armType_(obj, type)
            obj.ArmedType = char(type);
        end

        function tf = resizeGrid_(obj, field, n)
            % Growing is always safe; shrinking is refused while any region
            % would fall outside, naming the offenders.
            candidate = obj.Spec;
            candidate.Grid.(field) = n;
            if strcmp(field, 'Rows')
                sizes = candidate.Grid.RowHeight;
            else
                sizes = candidate.Grid.ColumnWidth;
            end
            if n > numel(sizes)
                sizes(end+1:n) = {'1x'};
            else
                sizes = sizes(1:n);
            end
            if strcmp(field, 'Rows')
                candidate.Grid.RowHeight = sizes;
            else
                candidate.Grid.ColumnWidth = sizes;
            end
            try
                candidate = gui.BehaviorBuilder.specValidate(candidate);
            catch ME
                vprintf(2, 'Grid resize refused: %s', ME.message)
                if ~isempty(obj.Fig) && isvalid(obj.Fig)
                    uialert(obj.Fig, sprintf('Cannot shrink the grid:\n%s', ME.message), ...
                        'Grid resize refused', 'Icon','warning');
                end
                tf = false;
                return
            end
            obj.Spec = candidate;
            obj.markDirty_;
            obj.refreshAll_;
            tf = true;
        end

        function tf = setPsychType_(obj, newType)
            % Switching to 'none' (or an analysis a placed region cannot use)
            % is refused while dependent regions exist - simpler and safer
            % than cascading deletes.
            candidate = obj.Spec;
            candidate.Psych.Type = char(newType);
            if ~strcmp(candidate.Psych.Type,'none') && isempty(candidate.Psych.Parameter)
                snap = candidate.ParameterSnapshot;
                writable = snap(~[snap.isTrigger] & ~strcmp({snap.Access},'Read'));
                if isempty(writable)
                    if ~isempty(obj.Fig) && isvalid(obj.Fig)
                        uialert(obj.Fig, ...
                            'Load a protocol with writable parameters first - the analysis needs one to track.', ...
                            'No parameters', 'Icon','info');
                    end
                    tf = false;
                    return
                end
                candidate.Psych.Parameter = writable(1).Name;
            end
            try
                candidate = gui.BehaviorBuilder.specValidate(candidate);
            catch ME
                vprintf(2, 'Psych change refused: %s', ME.message)
                if ~isempty(obj.Fig) && isvalid(obj.Fig)
                    uialert(obj.Fig, sprintf('Cannot change the analysis:\n%s', ME.message), ...
                        'Psych analysis in use', 'Icon','warning');
                end
                tf = false;
                return
            end
            obj.Spec = candidate;
            obj.markDirty_;
            obj.refreshSettings_;
            obj.refreshPalette_;
            tf = true;
        end
    end

    methods (Access = {?gui.BehaviorBuilder})
        function markDirty_(obj)
            obj.Dirty = true;
            obj.updateTitle_;
        end

        function updateTitle_(obj)
            if isempty(obj.Fig) || ~isvalid(obj.Fig), return, end
            name = 'Behavior GUI Builder';
            if ~isempty(obj.SpecFile)
                [~,f,e] = fileparts(obj.SpecFile);
                name = sprintf('%s - %s%s', name, f, e);
            end
            if obj.Dirty, name = [name ' *']; end
            obj.Fig.Name = name;
        end

        function id = nextRegionId_(obj)
            n = 1;
            existing = {obj.Spec.Regions.Id};
            while any(strcmp(sprintf('R%d',n), existing)), n = n + 1; end
            id = sprintf('R%d', n);
        end

        function r = selectedRegion_(obj)
            r = [];
            if isempty(obj.SelectedId), return, end
            ix = strcmp({obj.Spec.Regions.Id}, obj.SelectedId);
            if any(ix), r = obj.Spec.Regions(ix); end
        end

        function setRegionField_(obj, id, field, value)
            ix = strcmp({obj.Spec.Regions.Id}, id);
            if ~any(ix), return, end
            obj.Spec.Regions(ix).(field) = value;
            obj.markDirty_;
        end

        function refreshAll_(obj)
            if isempty(obj.Fig) || ~isvalid(obj.Fig), return, end
            obj.updateTitle_;
            obj.refreshProtocolPanel_;
            obj.refreshSettings_;
            obj.refreshPalette_;
            obj.drawCanvas;
            obj.refreshInspector_;
        end

        function rememberRecent_(obj, fn)
            mru = getpref(obj.PREF_TAG, 'RecentSpecs', {});
            mru = [{fn}, mru(~strcmpi(mru, fn))];
            setpref(obj.PREF_TAG, 'RecentSpecs', mru(1:min(end,8)));
            obj.refreshRecentMenu_;
        end

        function refreshRecentMenu_(obj)
            if isempty(obj.RecentMenu) || ~isvalid(obj.RecentMenu), return, end
            delete(obj.RecentMenu.Children);
            mru = getpref(obj.PREF_TAG, 'RecentSpecs', {});
            mru = mru(cellfun(@isfile, mru));
            obj.RecentMenu.Enable = matlab.lang.OnOffSwitchState(~isempty(mru));
            for i = 1:numel(mru)
                uimenu(obj.RecentMenu, 'Text', mru{i}, ...
                    'MenuSelectedFcn', @(~,~) obj.openSpec(mru{i}));
            end
        end

        function refreshProtocolPanel_(obj)
            if isempty(obj.Spec.ProtocolPath)
                obj.ProtocolLabel.Text = '(no protocol loaded)';
                obj.ProtocolLabel.Tooltip = '';
            else
                [~,f,e] = fileparts(obj.Spec.ProtocolPath);
                obj.ProtocolLabel.Text = [f e];
                obj.ProtocolLabel.Tooltip = obj.Spec.ProtocolPath;
            end
            snap = obj.Spec.ParameterSnapshot;
            if isempty(snap)
                obj.ProtocolSummary.Text = 'Load a protocol to list its parameters.';
            else
                nTrig = nnz([snap.isTrigger]);
                nRead = nnz(strcmp({snap.Access},'Read') & ~[snap.isTrigger]);
                nCtrl = numel(snap) - nTrig - nRead;
                obj.ProtocolSummary.Text = sprintf('%d parameters (%d triggers / %d controls / %d monitors)', ...
                    numel(snap), nTrig, nCtrl, nRead);
            end
            % degraded mode: a spec whose protocol file has moved still edits,
            % but parameter pickers work off the snapshot only. Text doubles
            % as the visibility switch so the 'fit' row collapses when hidden.
            degraded = ~isempty(obj.Spec.ProtocolPath) && ~isfile(obj.Spec.ProtocolPath);
            if degraded
                obj.DegradedBanner.Text = ['Protocol file not found - pickers use the ' ...
                    'saved snapshot. Use Load Protocol... to relocate it.'];
            else
                obj.DegradedBanner.Text = '';
            end
            obj.DegradedBanner.Visible = matlab.lang.OnOffSwitchState(degraded);
        end

        function refreshSettings_(obj)
            obj.ClassNameField.Value  = obj.Spec.ClassName;
            obj.WindowNameField.Value = obj.Spec.WindowName;
            obj.SizeWField.Value      = obj.Spec.DefaultSize(1);
            obj.SizeHField.Value      = obj.Spec.DefaultSize(2);
            obj.RowsSpinner.Value     = obj.Spec.Grid.Rows;
            obj.ColsSpinner.Value     = obj.Spec.Grid.Cols;
            obj.PsychTypeDD.Value     = obj.Spec.Psych.Type;

            snap = obj.Spec.ParameterSnapshot;
            writable = snap(~[snap.isTrigger] & ~strcmp({snap.Access},'Read'));
            items = [{'(choose parameter)'}, {writable.Name}];
            obj.PsychParamDD.Items = items;
            if ismember(obj.Spec.Psych.Parameter, items)
                obj.PsychParamDD.Value = obj.Spec.Psych.Parameter;
            else
                obj.PsychParamDD.Value = items{1};
            end
            showPsych = ~strcmp(obj.Spec.Psych.Type,'none');
            obj.PsychParamDD.Enable = matlab.lang.OnOffSwitchState(showPsych);
            obj.PsychTargetDD.Enable = matlab.lang.OnOffSwitchState( ...
                strcmp(obj.Spec.Psych.Type,'Detection'));
            if ismember(obj.Spec.Psych.TargetTrialType, obj.PsychTargetDD.Items)
                obj.PsychTargetDD.Value = obj.Spec.Psych.TargetTrialType;
            end
        end

        function refreshPalette_(obj)
            % Rebuild the palette tree: one node per category, one child per
            % component type (NodeData = the type). Psych-dependent entries
            % are greyed and annotated until an analysis is chosen.
            t = obj.Palette;
            if isempty(t) || ~isvalid(t), return, end
            delete(t.Children);
            removeStyle(t);
            cat = gui.BehaviorBuilder.componentCatalog;
            cats = unique({cat.Category}, 'stable');
            gated = matlab.ui.container.TreeNode.empty;
            for c = cats
                cn = uitreenode(t, 'Text', c{1});
                for e = cat(strcmp({cat.Category}, c{1}))
                    node = uitreenode(cn, 'Text', e.Display, 'NodeData', e.Type);
                    if e.NeedsPsych && ~obj.psychSatisfies_(e)
                        node.Text = [e.Display '  (needs psych analysis)'];
                        gated(end+1) = node; %#ok<AGROW>
                    end
                end
            end
            expand(t);
            if ~isempty(gated)
                addStyle(t, uistyle('FontColor',[0.62 0.62 0.62]), 'node', gated);
            end
            t.SelectedNodes = [];
            obj.ArmedType = '';
            if ~isempty(obj.PaletteDescription) && isvalid(obj.PaletteDescription)
                obj.PaletteDescription.Text = obj.PALETTE_HINT;
            end
        end

        function tf = psychSatisfies_(obj, e)
            tf = ~strcmp(obj.Spec.Psych.Type,'none') && ...
                (isempty(e.PsychTypes) || ismember(obj.Spec.Psych.Type, e.PsychTypes));
        end

        function refreshInspector_(obj)
            delete(obj.InspectorGrid.Children);
            r = obj.selectedRegion_;
            if isempty(r)
                lbl = uilabel(obj.InspectorGrid, 'Text', ...
                    sprintf('No region selected.\n\nPick a component in the palette,\nthen drag a rectangle on the canvas\nto place it.'), ...
                    'WordWrap','on', 'VerticalAlignment','top');
                lbl.Layout.Row = 1; lbl.Layout.Column = [1 2];
                return
            end
            e = gui.BehaviorBuilder.catalogEntry(r.Type);
            g = obj.InspectorGrid;

            h = uilabel(g, 'Text', sprintf('%s  (%s)', e.Display, r.Id), ...
                'FontWeight','bold');
            h.Layout.Row = 1; h.Layout.Column = [1 2];

            h = uilabel(g, 'Text','Label:');
            h.Layout.Row = 2; h.Layout.Column = 1;
            f = uieditfield(g, 'Value', r.Label, ...
                'ValueChangedFcn', @(s,~) obj.onInspectorLabel_(r.Id, s.Value));
            f.Layout.Row = 2; f.Layout.Column = 2;

            spans = {'Row', 3, obj.Spec.Grid.Rows; 'Col', 4, obj.Spec.Grid.Cols};
            for k = 1:size(spans,1)
                fld = spans{k,1}; gRow = spans{k,2}; mx = spans{k,3};
                h = uilabel(g, 'Text',[fld ' span:']);
                h.Layout.Row = gRow; h.Layout.Column = 1;
                sg = uigridlayout(g, [1 2], 'Padding',[0 0 0 0], 'ColumnSpacing',4);
                sg.Layout.Row = gRow; sg.Layout.Column = 2;
                for m = 1:2
                    uispinner(sg, 'Limits',[1 mx], 'Value', r.(fld)(m), 'Step',1, ...
                        'RoundFractionalValues','on', ...
                        'ValueChangedFcn', @(s,~) obj.onInspectorSpan_(r.Id, fld, m, s.Value));
                end
            end

            gRow = 5;
            if e.Poppable
                cb = uicheckbox(g, 'Text','Add pop-out button', 'Value', r.PopOut, ...
                    'ValueChangedFcn', @(s,~) obj.onInspectorPopOut_(r.Id, s.Value));
                cb.Layout.Row = gRow; cb.Layout.Column = [1 2];
                gRow = gRow + 1;
            end
            if e.HasOptions
                b = uibutton(g, 'Text','Configure...', ...
                    'ButtonPushedFcn', @(~,~) obj.onInspectorConfigure_(r.Id));
                b.Layout.Row = gRow; b.Layout.Column = [1 2];
                gRow = gRow + 1;
            end
            b = uibutton(g, 'Text','Delete Region', ...
                'ButtonPushedFcn', @(~,~) obj.removeRegion(r.Id));
            b.Layout.Row = gRow; b.Layout.Column = [1 2];
        end

        function onInspectorLabel_(obj, id, value)
            obj.setRegionField_(id, 'Label', char(value));
            obj.drawCanvas;
        end

        function onInspectorSpan_(obj, id, fld, m, value)
            ix = strcmp({obj.Spec.Regions.Id}, id);
            r = obj.Spec.Regions(ix);
            v = r.(fld); v(m) = round(value); v = sort(v);
            candidate = obj.Spec;
            candidate.Regions(ix).(fld) = v;
            try
                gui.BehaviorBuilder.specValidate(candidate);
            catch ME
                vprintf(2,'Span change rejected: %s', ME.message)
                obj.refreshInspector_; % snap the spinner back
                return
            end
            obj.Spec = candidate;
            obj.markDirty_;
            obj.drawCanvas;
            obj.refreshInspector_;
        end

        function onInspectorPopOut_(obj, id, value)
            obj.setRegionField_(id, 'PopOut', logical(value));
        end

        function onInspectorConfigure_(obj, id)
            if obj.configureRegion(id, false)
                obj.drawCanvas;
            end
        end

        function selectRegion_(obj, id)
            obj.SelectedId = char(id);
            % restyle in place: a full drawCanvas would delete the ROI whose
            % click callback is executing
            ks = obj.ROIs.keys;
            for k = 1:numel(ks)
                roi = obj.ROIs(ks{k});
                if ~isvalid(roi), continue, end
                if strcmp(ks{k}, obj.SelectedId)
                    roi.LineWidth = 3;
                else
                    roi.LineWidth = 0.5;
                end
            end
            obj.refreshInspector_;
        end
    end

    % ---------------------------------------------------------------------
    % Spec model + code generation (headless-usable statics)
    % ---------------------------------------------------------------------
    methods (Static)
        cat  = componentCatalog()
        code = generateCode(spec, specFile)
        mFile = writeCode(spec, specFile, mFile)

        function spec = specNew()
            % A fresh spec in the canonical ExampleBehaviorGUI shape:
            % 4x4 grid, 60 px button row on top, 300 px control column left.
            spec = struct( ...
                'FormatVersion',  gui.BehaviorBuilder.FORMAT_VERSION, ...
                'GeneratedBy',    'gui.BehaviorBuilder', ...
                'ClassName',      'MyBehaviorGUI', ...
                'WindowName',     'Behavior Box', ...
                'DefaultSize',    [1100 680], ...
                'ProtocolPath',   '', ...
                'ParameterSnapshot', gui.BehaviorBuilder.emptySnapshot_, ...
                'Grid', struct('Rows',4, 'Cols',4, ...
                    'RowHeight',    {{'60','1x','1x','1x'}}, ...
                    'ColumnWidth',  {{'300','1x','1x','1x'}}), ...
                'Psych', struct('Type','none', 'Parameter','', 'TargetTrialType',''), ...
                'Regions', gui.BehaviorBuilder.emptyRegions_);
        end

        function spec = specValidate(spec)
            % Normalize (jsondecode shapes, missing fields) then validate.
            % Throws epsych:BehaviorBuilder:* on anything codegen could not
            % emit safely. NaN is forbidden everywhere: jsonencode would turn
            % it into null and the round trip would no longer be exact.
            spec = gui.BehaviorBuilder.normalizeSpec_(spec);

            assert(isvarname(spec.ClassName), 'epsych:BehaviorBuilder:BadClassName', ...
                '"%s" is not a valid MATLAB class name', spec.ClassName)
            g = spec.Grid;
            mustBeInteger(g.Rows); mustBeInteger(g.Cols);
            assert(g.Rows >= 1 && g.Rows <= gui.BehaviorBuilder.MAX_GRID && ...
                   g.Cols >= 1 && g.Cols <= gui.BehaviorBuilder.MAX_GRID, ...
                'epsych:BehaviorBuilder:BadGrid', 'Grid must be 1..%d cells per side', ...
                gui.BehaviorBuilder.MAX_GRID)
            assert(numel(g.RowHeight) == g.Rows && numel(g.ColumnWidth) == g.Cols, ...
                'epsych:BehaviorBuilder:BadGrid', ...
                'RowHeight/ColumnWidth must match Rows/Cols')
            for s = [g.RowHeight(:); g.ColumnWidth(:)]'
                assert(~isempty(regexp(s{1}, '^(\d+(\.\d+)?|\d*\.?\d+x)$', 'once')), ...
                    'epsych:BehaviorBuilder:BadGrid', ...
                    'Grid size "%s" must be a pixel count or a weight like ''1x''', s{1})
            end
            assert(isnumeric(spec.DefaultSize) && numel(spec.DefaultSize) == 2 && ...
                   all(spec.DefaultSize > 0) && ~any(isnan(spec.DefaultSize)), ...
                'epsych:BehaviorBuilder:BadSize', 'DefaultSize must be [width height]')

            cat = gui.BehaviorBuilder.componentCatalog;
            assert(ismember(spec.Psych.Type, {'none','Staircase','Detection'}), ...
                'epsych:BehaviorBuilder:BadPsych', 'Unknown psych type "%s"', spec.Psych.Type)
            if ~strcmp(spec.Psych.Type,'none')
                assert(~isempty(spec.Psych.Parameter), 'epsych:BehaviorBuilder:BadPsych', ...
                    'A %s analysis needs a parameter', spec.Psych.Type)
            end

            R = spec.Regions;
            ids = {R.Id};
            assert(numel(unique(ids)) == numel(ids), ...
                'epsych:BehaviorBuilder:DuplicateId', 'Region Ids must be unique')
            for i = 1:numel(R)
                r = R(i);
                cix = strcmp({cat.Type}, r.Type);
                assert(any(cix), 'epsych:BehaviorBuilder:BadRegion', ...
                    'Unknown component type "%s"', r.Type)
                e = cat(cix);
                assert(all(r.Row >= 1) && r.Row(2) <= g.Rows && ...
                       all(r.Col >= 1) && r.Col(2) <= g.Cols, ...
                    'epsych:BehaviorBuilder:BadRegion', ...
                    'Region %s (%s) falls outside the %dx%d grid', r.Id, r.Type, g.Rows, g.Cols)
                if e.NeedsPsych
                    assert(~strcmp(spec.Psych.Type,'none'), ...
                        'epsych:BehaviorBuilder:NeedsPsych', ...
                        '%s requires a psych analysis (set one in the builder)', e.Display)
                    if ~isempty(e.PsychTypes)
                        assert(ismember(spec.Psych.Type, e.PsychTypes), ...
                            'epsych:BehaviorBuilder:NeedsPsych', ...
                            '%s requires a %s analysis', e.Display, strjoin(e.PsychTypes,'/'))
                    end
                end
                if r.PopOut
                    assert(e.Poppable, 'epsych:BehaviorBuilder:BadRegion', ...
                        '%s cannot have a pop-out button', e.Display)
                end
                % overlap: uigridlayout stacks overlapping children, which is
                % never what a generated GUI should do
                for j = i+1:numel(R)
                    o = R(j);
                    sep = r.Row(2) < o.Row(1) || o.Row(2) < r.Row(1) || ...
                          r.Col(2) < o.Col(1) || o.Col(2) < r.Col(1);
                    assert(sep, 'epsych:BehaviorBuilder:Overlap', ...
                        'Regions %s and %s overlap', r.Id, o.Id)
                end
            end
        end

        function spec = loadSpecFile(filename)
            arguments
                filename (1,:) char
            end
            assert(isfile(filename), 'epsych:BehaviorBuilder:FileNotFound', ...
                'No such file: %s', filename)
            txt = fileread(filename);
            spec = jsondecode(txt);
            spec = gui.BehaviorBuilder.specValidate(spec);
        end

        function saveSpecFile(spec, filename)
            arguments
                spec struct
                filename (1,:) char
            end
            spec = gui.BehaviorBuilder.specValidate(spec);
            [p,f,e] = fileparts(filename);
            if isempty(e), e = gui.BehaviorBuilder.SPEC_EXT; end
            filename = fullfile(p, [f e]);
            fid = fopen(filename, 'w');
            assert(fid > 0, 'epsych:BehaviorBuilder:CannotWrite', ...
                'Could not open %s for writing', filename)
            cl = onCleanup(@() fclose(fid));
            fprintf(fid, '%s', jsonencode(spec, PrettyPrint=true));
            vprintf(1, 'Saved behavior layout spec: %s', filename)
        end

        function snap = snapshotFromParameters(params)
            % Reduce hw.Parameter objects to the fields the builder needs so
            % a spec re-opens meaningfully even when the protocol file has
            % moved (degraded mode). Never serialize the objects themselves.
            snap = gui.BehaviorBuilder.emptySnapshot_;
            for i = 1:numel(params)
                p = params(i);
                if ~p.Visible, continue, end
                snap(end+1) = struct( ...
                    'Name',          char(p.Name), ...
                    'validName',     char(p.validName), ...
                    'Access',        char(p.Access), ...
                    'isTrigger',     logical(p.isTrigger), ...
                    'Type',          char(p.Type), ...
                    'Unit',          char(p.Unit), ...
                    'hasValues',     numel(p.Values) > 1, ...
                    'hasExpression', strlength(p.Expression) > 0); %#ok<AGROW>
            end
        end

        function t = defaultControlType(snapRow)
            % Mirror of gui.Parameter_Control's 'auto' scoring, decidable
            % from the snapshot alone (design time, protocol may be absent).
            if snapRow.isTrigger
                t = 'momentary';
            elseif strcmp(snapRow.Access,'Read') || snapRow.hasExpression
                t = 'readonly';
            elseif strcmp(snapRow.Type,'Boolean')
                t = 'checkbox';
            elseif snapRow.hasValues
                t = 'dropdown';
            else
                t = 'editfield';
            end
        end

        function out = promptFields(host, title, fields)
            % out = gui.BehaviorBuilder.promptFields(host, title, fields)
            % Small modal form (the TrialDesigner promptFields_ pattern, kept
            % local to avoid a cross-package private dependency). fields is a
            % struct array with Name, Label, Kind ('text'|'numeric'|'logical'|
            % 'choice'), Items (choice only), Value. Returns a struct keyed by
            % Name, or [] on cancel/close.
            out = promptFieldsImpl_(host, title, fields);
        end

        function e = catalogEntry(type)
            cat = gui.BehaviorBuilder.componentCatalog;
            ix = strcmp({cat.Type}, char(type));
            assert(any(ix), 'epsych:BehaviorBuilder:BadRegion', ...
                'Unknown component type "%s"', char(type))
            e = cat(ix);
        end

        function o = defaultOptions(type)
            switch char(type)
                case 'ControlColumn'
                    o = struct('Controls', gui.BehaviorBuilder.emptyControls_);
                case 'ButtonRow'
                    o = struct('Buttons', gui.BehaviorBuilder.emptyButtons_, ...
                        'IncludeScreenCapture', false);
                case 'Monitor'
                    o = struct('Params', {{}}, 'PollPeriod', 1, 'Style', 'table');
                case 'Scatter'
                    o = struct('XParameter','Trial Number', 'YParameter','', ...
                        'ColorParameter','');
                case 'Notes'
                    o = struct('TimeStamp','elapsed', 'Editable',false, ...
                        'ButtonOnly',false, 'Text','Notes');
                case 'SyringePump'
                    o = struct('Sections', {{}});
                case 'OnlinePlot'
                    % Empty would send gui.OnlinePlot to a listdlg at
                    % construction, which a generated build must never do.
                    o = struct('Source', {{}});
                case 'BufferPlot'
                    % Empty Buffers is legal and useful: gui.BufferPlot then
                    % takes the session's own 'Buffer' parameters, so a region
                    % nobody configured still plots something.
                    o = struct('Buffers', {{}}, 'SampleRate', 0, ...
                        'Layout','overlay', 'NumTrialsShown', 1);
                case 'SessionGate'
                    o = struct('Text','Begin Experiment');
                case 'PhaseSelector'
                    o = struct('PhasePath','');
                case 'StatusBar'
                    o = struct('InitialText','Ready');
                case 'FilenameField'
                    o = struct('DefaultFilename','data.mat');
                otherwise
                    o = struct;
            end
        end
    end

    methods (Static, Access = private)
        function spec = normalizeSpec_(spec)
            % Coerce jsondecode's shapes and fill defaults for fields added
            % in later FormatVersions (SubjectRoster.normalize_ discipline).
            base = gui.BehaviorBuilder.specNew;
            for f = fieldnames(base)'
                if ~isfield(spec, f{1}), spec.(f{1}) = base.(f{1}); end
            end
            spec.ClassName  = char(string(spec.ClassName));
            spec.WindowName = char(string(spec.WindowName));
            spec.ProtocolPath = char(string(spec.ProtocolPath));
            spec.GeneratedBy  = 'gui.BehaviorBuilder';
            spec.DefaultSize  = double(spec.DefaultSize(:)');

            for f = {'Rows','Cols'}
                spec.Grid.(f{1}) = double(spec.Grid.(f{1}));
            end
            spec.Grid.RowHeight   = gui.BehaviorBuilder.asRowCellstr_(spec.Grid.RowHeight);
            spec.Grid.ColumnWidth = gui.BehaviorBuilder.asRowCellstr_(spec.Grid.ColumnWidth);

            for f = fieldnames(base.Psych)'
                if ~isfield(spec.Psych, f{1}), spec.Psych.(f{1}) = base.Psych.(f{1}); end
            end
            spec.Psych.Type = char(string(spec.Psych.Type));
            spec.Psych.Parameter = char(string(spec.Psych.Parameter));
            spec.Psych.TargetTrialType = char(string(spec.Psych.TargetTrialType));

            % ParameterSnapshot: [] (decoded empty array) -> typed empty
            snap = spec.ParameterSnapshot;
            if isempty(snap)
                spec.ParameterSnapshot = gui.BehaviorBuilder.emptySnapshot_;
            else
                if iscell(snap), snap = [snap{:}]; end
                out = gui.BehaviorBuilder.emptySnapshot_;
                proto = struct('Name','','validName','','Access','','isTrigger',false, ...
                    'Type','','Unit','','hasValues',false,'hasExpression',false);
                for i = 1:numel(snap)
                    s = proto;
                    for f = fieldnames(proto)'
                        if isfield(snap(i), f{1}), s.(f{1}) = snap(i).(f{1}); end
                    end
                    s.Name = char(string(s.Name)); s.validName = char(string(s.validName));
                    s.Access = char(string(s.Access)); s.Type = char(string(s.Type));
                    s.Unit = char(string(s.Unit));
                    s.isTrigger = logical(s.isTrigger);
                    s.hasValues = logical(s.hasValues);
                    s.hasExpression = logical(s.hasExpression);
                    out(end+1) = s; %#ok<AGROW>
                end
                spec.ParameterSnapshot = reshape(out,1,[]);
            end

            % Regions: [] -> typed empty; cell-of-structs -> struct array;
            % spans -> sorted 1x2 rows; Options normalized per type
            R = spec.Regions;
            if isempty(R)
                spec.Regions = gui.BehaviorBuilder.emptyRegions_;
            else
                if iscell(R)
                    tmp = gui.BehaviorBuilder.emptyRegions_;
                    for i = 1:numel(R), tmp(end+1) = gui.BehaviorBuilder.normalizeRegion_(R{i}); end %#ok<AGROW>
                    R = tmp;
                else
                    tmp = gui.BehaviorBuilder.emptyRegions_;
                    for i = 1:numel(R), tmp(end+1) = gui.BehaviorBuilder.normalizeRegion_(R(i)); end %#ok<AGROW>
                    R = tmp;
                end
                spec.Regions = reshape(R,1,[]);
            end
        end

        function r = normalizeRegion_(rin)
            r = struct('Id','','Type','','Label','','Row',[1 1],'Col',[1 1], ...
                'PopOut',false,'Options',struct);
            for f = {'Id','Type','Label'}
                if isfield(rin, f{1}), r.(f{1}) = char(string(rin.(f{1}))); end
            end
            for f = {'Row','Col'}
                if isfield(rin, f{1})
                    v = double(rin.(f{1})); v = v(:)';
                    if isscalar(v), v = [v v]; end
                    r.(f{1}) = sort(round(v(1:2)));
                    assert(~any(isnan(r.(f{1}))), 'epsych:BehaviorBuilder:BadRegion', ...
                        'Region %s has a NaN span', r.Id)
                end
            end
            if isfield(rin,'PopOut'), r.PopOut = logical(rin.PopOut); end

            o = gui.BehaviorBuilder.defaultOptions(r.Type);
            if isfield(rin,'Options') && isstruct(rin.Options)
                for f = fieldnames(rin.Options)'
                    o.(f{1}) = rin.Options.(f{1});
                end
            end
            switch r.Type
                case 'ControlColumn'
                    o.Controls = gui.BehaviorBuilder.normalizeRows_(o.Controls, ...
                        gui.BehaviorBuilder.emptyControls_, ...
                        struct('Param','','Type','auto','autoCommit',false,'Text',''));
                case 'ButtonRow'
                    o.Buttons = gui.BehaviorBuilder.normalizeRows_(o.Buttons, ...
                        gui.BehaviorBuilder.emptyButtons_, ...
                        struct('Param','','Text',''));
                    o.IncludeScreenCapture = logical(o.IncludeScreenCapture);
                case 'Monitor'
                    o.Params = gui.BehaviorBuilder.asRowCellstr_(o.Params);
                    o.PollPeriod = double(o.PollPeriod);
                    assert(~isnan(o.PollPeriod) && o.PollPeriod > 0, ...
                        'epsych:BehaviorBuilder:BadRegion', ...
                        'Monitor poll period must be a positive number')
                    o.Style = char(string(o.Style));
                    assert(ismember(o.Style, {'table','text'}), ...
                        'epsych:BehaviorBuilder:BadRegion', ...
                        'Monitor style must be table or text')
                case 'Scatter'
                    for f = {'XParameter','YParameter','ColorParameter'}
                        o.(f{1}) = char(string(o.(f{1})));
                    end
                case 'Notes'
                    o.TimeStamp = char(string(o.TimeStamp));
                    assert(ismember(o.TimeStamp, {'elapsed','clock','none'}), ...
                        'epsych:BehaviorBuilder:BadRegion', ...
                        'Notes stamp must be elapsed, clock or none')
                    o.Editable   = logical(o.Editable);
                    o.ButtonOnly = logical(o.ButtonOnly);
                    o.Text       = char(string(o.Text));
                    if o.ButtonOnly
                        % The button IS the pop-out opener, so a pop-out
                        % button beside it would be a second control doing
                        % the same thing to the same window.
                        r.PopOut = false;
                    end
                case 'SyringePump'
                    o.Sections = gui.BehaviorBuilder.asRowCellstr_(o.Sections);
                case 'OnlinePlot'
                    o.Source = gui.BehaviorBuilder.asRowCellstr_(o.Source);
                    assert(~isempty(o.Source), 'epsych:BehaviorBuilder:BadRegion', ...
                        'Online Plot needs at least one parameter or bitmask bank name')
                case 'BufferPlot'
                    o.Buffers = gui.BehaviorBuilder.asRowCellstr_(o.Buffers);
                    o.SampleRate = double(o.SampleRate);
                    if ~isfinite(o.SampleRate) || o.SampleRate < 0, o.SampleRate = 0; end
                    o.Layout = lower(char(string(o.Layout)));
                    % Refused here, not at run time: a bad value in a
                    % hand-edited spec otherwise passes specValidate and then
                    % throws mustBeMember inside the GENERATED build(), which
                    % kills the behavior GUI at session start -- and the
                    % config dialog too, since uidropdown rejects a Value not
                    % in Items.
                    assert(ismember(o.Layout, {'overlay','stacked'}), ...
                        'epsych:BehaviorBuilder:BadRegion', ...
                        'Buffer Plot Layout must be ''overlay'' or ''stacked'', not "%s"', o.Layout)
                    o.NumTrialsShown = max(1, round(double(o.NumTrialsShown)));
                case 'SessionGate'
                    o.Text = char(string(o.Text));
                case 'PhaseSelector'
                    o.PhasePath = char(string(o.PhasePath));
                case 'StatusBar'
                    o.InitialText = char(string(o.InitialText));
                case 'FilenameField'
                    o.DefaultFilename = char(string(o.DefaultFilename));
                    assert(endsWith(o.DefaultFilename, '.mat', 'IgnoreCase', true), ...
                        'epsych:BehaviorBuilder:BadRegion', ...
                        'Filename Field default must end in .mat, which is what the field enforces')
            end
            r.Options = o;
        end

        function rows = normalizeRows_(rin, empty, proto)
            % Normalize a decoded struct-array-ish (struct array, cell of
            % structs, or []) onto a prototype row.
            rows = empty;
            if isempty(rin), return, end
            if isstruct(rin), rin = num2cell(rin); end
            for i = 1:numel(rin)
                s = proto;
                for f = fieldnames(proto)'
                    if isfield(rin{i}, f{1}), s.(f{1}) = rin{i}.(f{1}); end
                end
                for f = fieldnames(s)'
                    if ischar(proto.(f{1})) || isstring(proto.(f{1}))
                        s.(f{1}) = char(string(s.(f{1})));
                    elseif islogical(proto.(f{1}))
                        s.(f{1}) = logical(s.(f{1}));
                    end
                end
                rows(end+1) = s; %#ok<AGROW>
            end
            rows = reshape(rows,1,[]);
        end

        function c = asRowCellstr_(v)
            % jsondecode turns a JSON string array into a column cell (or a
            % scalar into a char); grid sizes may also arrive numeric.
            if isnumeric(v), v = arrayfun(@(x) num2str(x), v, 'uni', 0); end
            c = cellstr(string(v));
            c = reshape(c,1,[]);
        end

        function r = emptyRegions_()
            r = repmat(struct('Id','','Type','','Label','','Row',[1 1], ...
                'Col',[1 1],'PopOut',false,'Options',struct), 1, 0);
        end

        function s = emptySnapshot_()
            s = repmat(struct('Name','','validName','','Access','','isTrigger',false, ...
                'Type','','Unit','','hasValues',false,'hasExpression',false), 1, 0);
        end

        function c = emptyControls_()
            c = repmat(struct('Param','','Type','auto','autoCommit',false,'Text',''), 1, 0);
        end

        function b = emptyButtons_()
            b = repmat(struct('Param','','Text',''), 1, 0);
        end
    end
end


% =========================================================================
% Local functions (below classdef end): modal form machinery for promptFields
% =========================================================================
function out = promptFieldsImpl_(host, title, fields)
n = numel(fields);
W = 440; H = 76 + 32*n;
fpos = [200 200 W H];
if ~isempty(host) && isvalid(host)
    hp = host.Position;
    fpos = [hp(1)+(hp(3)-W)/2, hp(2)+(hp(4)-H)/2, W, H];
end
dlg = uifigure('Name',title, 'Position',fpos, 'WindowStyle','modal', ...
    'CloseRequestFcn', @(s,~) uiresume(s));
g = uigridlayout(dlg, [n+1 2]);
g.RowHeight = [repmat({28},1,n), {34}];
g.ColumnWidth = {185, '1x'};

hCtl = cell(1,n);
for i = 1:n
    f = fields(i);
    lbl = uilabel(g, 'Text',[f.Label ':'], 'WordWrap','on');
    lbl.Layout.Row = i; lbl.Layout.Column = 1;
    switch f.Kind
        case 'numeric'
            hCtl{i} = uieditfield(g, 'numeric', 'Value', double(f.Value));
        case 'logical'
            hCtl{i} = uicheckbox(g, 'Text','', 'Value', logical(f.Value));
        case 'choice'
            items = cellstr(f.Items);
            v = char(string(f.Value));
            if ~ismember(v, items), v = items{1}; end
            hCtl{i} = uidropdown(g, 'Items',items, 'Value',v);
        otherwise % text
            hCtl{i} = uieditfield(g, 'Value', char(string(f.Value)));
    end
    hCtl{i}.Layout.Row = i; hCtl{i}.Layout.Column = 2;
end

br = uigridlayout(g, [1 3]);
br.Padding = [0 0 0 0];
br.ColumnWidth = {'1x', 90, 90};
br.Layout.Row = n+1; br.Layout.Column = [1 2];
uilabel(br, 'Text','');
uibutton(br, 'Text','OK', 'FontWeight','bold', ...
    'ButtonPushedFcn', @(~,~) acceptDialog_(dlg));
uibutton(br, 'Text','Cancel', 'ButtonPushedFcn', @(~,~) uiresume(dlg));

uiwait(dlg);
out = [];
if isvalid(dlg) && isequal(dlg.UserData, true)
    for i = 1:n
        out.(fields(i).Name) = hCtl{i}.Value;
    end
end
if isvalid(dlg)
    dlg.CloseRequestFcn = '';
    delete(dlg);
end
end

function acceptDialog_(dlg)
dlg.UserData = true;
uiresume(dlg);
end
