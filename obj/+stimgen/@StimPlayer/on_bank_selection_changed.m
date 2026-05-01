function on_bank_selection_changed(obj, src, ~)
% on_bank_selection_changed(obj, src) - Rebuild the parameter panel when listbox selection changes.
% Clears existing contents and builds labeled sections (Waveform, Level,
% Timing, Info) inside a single scrollable grid layout.

if isempty(src.ItemsData) || isempty(src.Value)
    obj.clear_tabs_;
    return
end

idx = src.Value;
if idx < 1 || idx > numel(obj.StimPlayObjs)
    obj.clear_tabs_;
    return
end

sp      = obj.StimPlayObjs(idx);
stimObj = sp.CurrentStimObj;

% Sync Reps field
obj.handles.RepsField.Value = sp.Reps;

% Clear param panel
pnl = obj.handles.ParamPanel;
delete(pnl.Children);

% --- Gather parameter metadata ---
meta       = stimObj.get_prop_meta();
allProps   = fieldnames(meta);
baseLevelP = obj.LEVEL_PROPS;
baseTimeP  = obj.TIMING_PROPS;
baseAll    = [baseLevelP, baseTimeP];
waveProps  = allProps(~ismember(allProps, baseAll));

% Level meta: base level props + ApplyCalibration
levelMeta = struct();
for k = 1:numel(baseLevelP)
    p = baseLevelP{k};
    if isfield(meta, p), levelMeta.(p) = meta.(p); end
end
levelMeta.ApplyCalibration = struct('label', 'Apply Calibration');

% Timing meta: base timing props present in meta
timeMeta = struct();
for k = 1:numel(baseTimeP)
    p = baseTimeP{k};
    if isfield(meta, p), timeMeta.(p) = meta.(p); end
end

% Section definitions: {title, metaStruct, propNames}
sections = {};
if ~isempty(waveProps)
    waveMeta = struct();
    for k = 1:numel(waveProps)
        waveMeta.(waveProps{k}) = meta.(waveProps{k});
    end
    sections{end+1} = {'Waveform', waveMeta, waveProps};
end
sections{end+1} = {'Level',   levelMeta, fieldnames(levelMeta)};
sections{end+1} = {'Timing',  timeMeta,  fieldnames(timeMeta)};
sections{end+1} = {'Info',    struct('Name', struct('label','Name')), {'Name'}};

% --- Compute row heights ---
ROW_HDR  = 28;   % section header
ROW_PROP = 28;   % per-property row
ROW_SEP  = 10;   % gap after each section
rowHeights = {};
for s = 1:numel(sections)
    rowHeights{end+1} = ROW_HDR;
    for p = 1:numel(sections{s}{3})
        rowHeights{end+1} = ROW_PROP;
    end
    rowHeights{end+1} = ROW_SEP;
end

% --- Build scrollable grid ---
g = uigridlayout(pnl, 'Scrollable', 'on');
g.ColumnWidth = {'1x', '2x'};
g.RowHeight   = rowHeights;
g.Padding     = [6 6 6 6];
g.RowSpacing  = 2;

mc = metaclass(stimObj);
pl = mc.PropertyList;

row = 1;
for s = 1:numel(sections)
    sTitle    = sections{s}{1};
    sMeta     = sections{s}{2};
    sPropList = sections{s}{3};

    % Section header
    hdr = uilabel(g, 'Text', ['  ' sTitle], ...
        'FontWeight', 'bold', 'FontSize', 11, ...
        'BackgroundColor', [0.88 0.88 0.92]);
    hdr.Layout.Row    = row;
    hdr.Layout.Column = [1 2];
    row = row + 1;

    % Property rows
    for p = 1:numel(sPropList)
        propName = sPropList{p};
        pm       = sMeta.(propName);

        lbl = uilabel(g, 'Text', [pm.label ':'], ...
            'HorizontalAlignment', 'right');
        lbl.Layout.Row    = row;
        lbl.Layout.Column = 1;

        if strcmp(propName, 'Name')
            x = uieditfield(g, 'Tag', propName, 'Value', char(sp.Name));
            x.ValueChangedFcn = @(s,~) update_name_(obj, idx, s.Value);
        else
            wt = resolve_wt_(propName, pm, pl);
            switch wt
                case 'numeric'
                    x = uieditfield(g, 'numeric', 'Tag', propName);
                    x.Value = stimObj.(propName);
                    if isfield(pm, 'format'), x.ValueDisplayFormat = pm.format; end
                    if isfield(pm, 'limits'), x.Limits = pm.limits; end
                case 'checkbox'
                    x = uicheckbox(g, 'Tag', propName, 'Text', '');
                    x.Value = stimObj.(propName);
                case 'dropdown'
                    x = uidropdown(g, 'Tag', propName);
                    x.Items = pm.items;
                    if isfield(pm, 'itemsData'), x.ItemsData = pm.itemsData; end
                    x.Value = stimObj.(propName);
                otherwise
                    x = uieditfield(g, 'Tag', propName);
                    x.Value = char(stimObj.(propName));
            end
            x.ValueChangedFcn = @(s, e) set_prop_(obj, stimObj, s.Tag, e.Value);
        end

        x.Layout.Row    = row;
        x.Layout.Column = 2;
        row = row + 1;
    end

    row = row + 1; % skip separator row
end

obj.update_signal_plot;
end


% =========================================================================

function set_prop_(obj, stimObj, propName, value)
% set_prop_(obj, stimObj, propName, value) - Set a property on stimObj then refresh the plot.
try
    stimObj.(propName) = value;
    stimObj.update_signal();
    obj.update_signal_plot();
catch ME
    vprintf(0, 1, ME);
end
end


function update_name_(obj, idx, newName)
% update_name_(obj, idx, newName) - Update the Name of bank item idx.
obj.StimPlayObjs(idx).Name = string(newName);
obj.refresh_listbox_;
end


function wt = resolve_wt_(propName, pm, pl)
% resolve_wt_(propName, pm, pl) - Determine widget type for a property.
if isfield(pm, 'widget')
    wt = pm.widget;
    return
end
idx = strcmp({pl.Name}, propName);
if ~any(idx) || isempty(pl(idx).Validation) || isempty(pl(idx).Validation.Class)
    wt = 'text';
    return
end
switch pl(idx).Validation.Class.Name
    case 'double'
        wt = 'numeric';
    case 'logical'
        wt = 'checkbox';
    otherwise
        wt = 'text';
end
end
