function drawCanvas(obj)
% drawCanvas(obj)
% Redraw the design surface from the spec: grid lines, clickable row/column
% size headers, and one images.roi.Rectangle per region (drag to move,
% handles to resize, snap-to-grid on release with overlap refusal). The ROI
% pattern - Position write-back inside ROIMoved - is the proven one from
% gui.VlcRecorderSetup. Region creation is a rubber-band drag on empty
% canvas after arming a palette entry; presses arrive via the axes
% ButtonDownFcn, and the figure's Motion/Up callbacks are borrowed only for
% the duration of a drag (teensy.TrialDesigner rule).

ax = obj.Axes;

% wipe previous drawing (ROIs are axes children and go with allchild)
ks = obj.ROIs.keys;
for k = 1:numel(ks)
    roi = obj.ROIs(ks{k});
    if isvalid(roi), delete(roi); end
end
obj.ROIs = containers.Map('KeyType','char','ValueType','any');
obj.PlaceholderTexts = containers.Map('KeyType','char','ValueType','any');
delete(allchild(ax));
obj.PreDrag_ = [];

nR = obj.Spec.Grid.Rows;
nC = obj.Spec.Grid.Cols;

ax.XLim = [-0.7, nC + 0.15];
ax.YLim = [-0.7, nR + 0.15];
ax.YDir = 'reverse';           % row 1 at the top, like uigridlayout
ax.XTick = []; ax.YTick = [];
ax.XColor = 'none'; ax.YColor = 'none';
ax.Box = 'off';
ax.ButtonDownFcn = @(~,~) localCanvasDown(obj);
ax.PickableParts = 'all';
ax.HitTest = 'on';

gridColor = [0.75 0.75 0.78];
for c = 0:nC
    line(ax, [c c], [0 nR], 'Color',gridColor, 'HitTest','off', 'PickableParts','none');
end
for r = 0:nR
    line(ax, [0 nC], [r r], 'Color',gridColor, 'HitTest','off', 'PickableParts','none');
end

% size headers: click one to change that row/column's height/width
for c = 1:nC
    text(ax, c-0.5, -0.35, obj.Spec.Grid.ColumnWidth{c}, ...
        'HorizontalAlignment','center', 'FontSize',9, 'Color',[0.35 0.35 0.4], ...
        'Interpreter','none', ...
        'ButtonDownFcn', @(~,~) localEditSize(obj, 'ColumnWidth', c));
end
for r = 1:nR
    text(ax, -0.35, r-0.5, obj.Spec.Grid.RowHeight{r}, ...
        'HorizontalAlignment','center', 'FontSize',9, 'Color',[0.35 0.35 0.4], ...
        'Interpreter','none', ...
        'ButtonDownFcn', @(~,~) localEditSize(obj, 'RowHeight', r));
end

for i = 1:numel(obj.Spec.Regions)
    localMakeRoi(obj, obj.Spec.Regions(i), nR, nC);
end
end


% =========================================================================
function localMakeRoi(obj, r, nR, nC)
e = gui.BehaviorBuilder.catalogEntry(r.Type);
clr = localRegionColor(e);
if isempty(r.Label) || strcmp(r.Label, e.Display)
    lbl = e.Display;
else
    lbl = sprintf('%s: %s', e.Display, r.Label);
end
% inset the ROI inside its cells so adjacent regions keep separate borders
m = gui.BehaviorBuilder.ROI_INSET;
pos = [r.Col(1)-1+m, r.Row(1)-1+m, ...
       r.Col(2)-r.Col(1)+1-2*m, r.Row(2)-r.Row(1)+1-2*m];

roi = images.roi.Rectangle(obj.Axes, ...
    'Position', pos, ...
    'DrawingArea', [0 0 nC nR], ...
    'Color', clr, ...
    'FaceAlpha', 0.25, ...
    'Label', lbl, ...
    'LabelVisible', 'on', ...
    'Deletable', false, ...        % deletion goes through the builder, not the ROI menu
    'Tag', r.Id);
if strcmp(r.Id, obj.SelectedId)
    roi.LineWidth = 3;
else
    roi.LineWidth = 0.5;
end

addlistener(roi, 'MovingROI', @(s,evt) localMoving(obj, evt));
addlistener(roi, 'ROIMoved',  @(s,evt) localMoved(obj, s));
addlistener(roi, 'ROIClicked',@(s,~)   obj.selectRegion_(s.Tag));

cm = uicontextmenu(obj.Fig);
if e.HasOptions
    uimenu(cm, 'Text','Configure...', ...
        'MenuSelectedFcn', @(~,~) localConfigure(obj, r.Id));
end
uimenu(cm, 'Text','Delete Region', ...
    'MenuSelectedFcn', @(~,~) obj.removeRegion(r.Id));
roi.ContextMenu = cm;

obj.ROIs(r.Id) = roi;
end

function localConfigure(obj, id)
obj.selectRegion_(id);
if obj.configureRegion(id, false)
    obj.drawCanvas;
end
end

function localMoving(obj, evt)
% first Moving event of a gesture carries the pre-drag position
if isempty(obj.PreDrag_)
    obj.PreDrag_ = evt.PreviousPosition;
end
end

function localMoved(obj, roi)
% Snap on release: round to whole cells (accounting for the visual inset),
% clamp into the grid, then accept only if the spec still validates (no
% overlap); otherwise revert the drag.
nR = obj.Spec.Grid.Rows;
nC = obj.Spec.Grid.Cols;
m = gui.BehaviorBuilder.ROI_INSET;
pos = roi.Position;
w = min(max(1, round(pos(3) + 2*m)), nC);
h = min(max(1, round(pos(4) + 2*m)), nR);
x = min(max(0, round(pos(1) - m)), nC - w);
y = min(max(0, round(pos(2) - m)), nR - h);
rowSpan = [y+1, y+h];
colSpan = [x+1, x+w];

id = roi.Tag;
ix = strcmp({obj.Spec.Regions.Id}, id);
candidate = obj.Spec;
candidate.Regions(ix).Row = rowSpan;
candidate.Regions(ix).Col = colSpan;
try
    candidate = gui.BehaviorBuilder.specValidate(candidate);
    obj.Spec = candidate;
    obj.markDirty_;
    roi.Position = [x+m, y+m, w-2*m, h-2*m];
    obj.selectRegion_(id); % restyle + refresh the inspector's span spinners
catch ME
    vprintf(2, 'Region move rejected: %s', ME.message)
    if ~isempty(obj.PreDrag_)
        roi.Position = obj.PreDrag_;
    end
end
obj.PreDrag_ = [];
end

function localCanvasDown(obj)
% Empty-canvas press: with an armed palette type, rubber-band a new region;
% otherwise just deselect. Only Motion/Up are borrowed, and restored on Up.
if isempty(obj.ArmedType)
    obj.selectRegion_('');
    return
end
ax = obj.Axes;
p0 = ax.CurrentPoint(1,1:2);
hRect = rectangle(ax, 'Position',[p0 0.05 0.05], ...
    'EdgeColor',[0.25 0.25 0.3], 'LineStyle','--', ...
    'HitTest','off', 'PickableParts','none');
fig = obj.Fig;
prevMotion = fig.WindowButtonMotionFcn;
prevUp     = fig.WindowButtonUpFcn;
fig.WindowButtonMotionFcn = @(~,~) localCreateMotion(ax, hRect, p0);
fig.WindowButtonUpFcn     = @(~,~) localCreateUp(obj, hRect, p0, prevMotion, prevUp);
end

function localCreateMotion(ax, hRect, p0)
if ~isvalid(hRect), return, end
p = ax.CurrentPoint(1,1:2);
hRect.Position = [min(p, p0), max(abs(p - p0), 0.05)];
end

function localCreateUp(obj, hRect, p0, prevMotion, prevUp)
fig = obj.Fig;
fig.WindowButtonMotionFcn = prevMotion;
fig.WindowButtonUpFcn     = prevUp;
if isvalid(hRect), delete(hRect); end

ax = obj.Axes;
p1 = ax.CurrentPoint(1,1:2);
nR = obj.Spec.Grid.Rows;
nC = obj.Spec.Grid.Cols;
% cells touched by the drag; a bare click covers one cell
c1 = max(1, min(nC, floor(min(p0(1), p1(1))) + 1));
c2 = max(1, min(nC, ceil( max(p0(1), p1(1)))));
r1 = max(1, min(nR, floor(min(p0(2), p1(2))) + 1));
r2 = max(1, min(nR, ceil( max(p0(2), p1(2)))));

type = obj.ArmedType;
obj.armType_('');
obj.Palette.SelectedNodes = [];
obj.addRegion(type, [r1 max(r1,r2)], [c1 max(c1,c2)]);
end

function clr = localRegionColor(e)
% One hue per category, saturation ramped across the category's types so
% every component type reads as its own shade of the family color.
cat = gui.BehaviorBuilder.componentCatalog;
peers = cat(strcmp({cat.Category}, e.Category));
k = find(strcmp({peers.Type}, e.Type), 1);
n = numel(peers);
switch e.Category
    case 'Controls', hue = 0.58; % blues
    case 'Displays', hue = 0.34; % greens
    otherwise,       hue = 0.07; % oranges (Add-ons)
end
if n > 1
    sat = 0.30 + 0.55 * (k-1)/(n-1);
else
    sat = 0.60;
end
clr = hsv2rgb([hue, sat, 0.78]);
end

function localEditSize(obj, field, ix)
if strcmp(field, 'ColumnWidth')
    what = sprintf('Column %d width', ix);
else
    what = sprintf('Row %d height', ix);
end
cur = obj.Spec.Grid.(field){ix};
fields = struct('Name','Size', ...
    'Label', sprintf('%s (pixels, or a weight like ''1x'')', what), ...
    'Kind','text', 'Value',cur);
fields.Items = {};
out = gui.BehaviorBuilder.promptFields(obj.Fig, 'Grid Size', fields);
if isempty(out), return, end
v = strtrim(out.Size);
if isempty(regexp(v, '^(\d+(\.\d+)?|\d*\.?\d+x)$', 'once'))
    uialert(obj.Fig, sprintf('"%s" is not a pixel count or a weight like ''1x''.', v), ...
        'Invalid size');
    return
end
obj.Spec.Grid.(field){ix} = v;
obj.markDirty_;
obj.drawCanvas;
end
