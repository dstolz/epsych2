function drawDiagram(obj)
% drawDiagram(obj)
% Render the state machine as a node-and-arrow diagram.
%
% Redraws by clearing the axes and rebuilding. Updating in place would mean
% tracking which graphics belong to which state across edits, and a diagram
% this size redraws faster than that bookkeeping would cost.
%
% Node geometry is cached in obj.HStates.NodeMap so mouse hit-testing does
% not have to re-derive it, and so a drag can move a node without a layout
% pass.
%
% See also: teensy.TrialDesigner.onDiagram, teensy.Program.autoLayout

arguments
    obj (1,1) teensy.TrialDesigner
end

ax = obj.HStates.Axes;
if isempty(ax) || ~isvalid(ax)
    return
end

cla(ax);

S = obj.Program.States;
n = numel(S);

obj.HStates.NodeMap = struct('Index', {}, 'X', {}, 'Y', {}, 'W', {}, 'H', {});

if n == 0
    text(ax, 0.5, 0.5, 'No states yet. Use Add, or start from a template.', ...
        HorizontalAlignment = 'center', FontAngle = 'italic', Color = [0.5 0.55 0.6]);
    return
end

% Nodes are sized so the longest name fits; a name that overflows its box is
% the fastest way to make a diagram unreadable.
maxChars = max(cellfun(@numel, cellstr([S.Name])));
w = min(0.26, max(0.11, 0.016 * maxChars + 0.03));
h = 0.075;

startIdx = obj.Program.stateIndex(obj.Program.StartState);
G = obj.Program.graph();

% --- Edges first, so nodes draw over them ---------------------------------

pairSeen = containers.Map('KeyType', 'char', 'ValueType', 'double');

for e = 1:numel(G.Edges)
    src = G.Edges(e).Source;
    dst = G.Edges(e).Target;

    key = sprintf('%d_%d', min(src, dst), max(src, dst));
    if isKey(pairSeen, key)
        pairSeen(key) = pairSeen(key) + 1;
    else
        pairSeen(key) = 0;
    end
    offset = pairSeen(key);

    p1 = S(src).Position;
    p2 = S(dst).Position;

    if src == dst
        localSelfLoop_(ax, p1, h, G.Edges(e).Label);
    else
        localArrow_(ax, p1, p2, w, h, offset, G.Edges(e).Label);
    end
end

% --- Nodes ---------------------------------------------------------------

for i = 1:n
    s = S(i);
    pos = s.Position;
    x = pos(1) - w / 2;
    y = pos(2) - h / 2;

    color = s.Color;
    if s.IsTerminal
        % Terminal nodes take the colour of their dominant outcome bit, so a
        % diagram reads with the same colour language as gui.History.
        color = localOutcomeColor_(s, color);
    end

    lineWidth = 1;
    edgeColor = [0.35 0.40 0.46];

    if s.IsTerminal
        lineWidth = 2.5;
    end
    if i == obj.SelectedState
        edgeColor = [0.20 0.50 0.90];
        lineWidth = max(lineWidth, 3);
    end
    if i == obj.HStates.LiveState
        edgeColor = [0.95 0.55 0.10];
        lineWidth = 4;
    end

    rectangle(ax, Position = [x y w h], Curvature = [0.35 0.5], ...
        FaceColor = color, EdgeColor = edgeColor, LineWidth = lineWidth, ...
        ButtonDownFcn = @(~, evt) obj.onDiagram('node', i));

    label = char(s.Name);
    if i == startIdx
        label = ['> ' label];
    end

    t = text(ax, pos(1), pos(2), label, ...
        HorizontalAlignment = 'center', VerticalAlignment = 'middle', ...
        FontWeight = 'bold', FontSize = 10, Interpreter = 'none', ...
        Color = localTextColor_(color), ...
        ButtonDownFcn = @(~, evt) obj.onDiagram('node', i));
    t.PickableParts = 'all';

    obj.HStates.NodeMap(end+1) = struct('Index', i, 'X', pos(1), 'Y', pos(2), 'W', w, 'H', h);
end

% --- Start marker ---------------------------------------------------------

if startIdx > 0
    p = S(startIdx).Position;
    plot(ax, [p(1) - w / 2 - 0.05, p(1) - w / 2], [p(2), p(2)], ...
        Color = [0.25 0.30 0.36], LineWidth = 2, HitTest = 'off');
    plot(ax, p(1) - w / 2 - 0.05, p(2), 'o', ...
        MarkerFaceColor = [0.25 0.30 0.36], MarkerEdgeColor = 'none', ...
        MarkerSize = 6, HitTest = 'off');
end
end


% =========================================================================
function localArrow_(ax, p1, p2, w, h, offset, label)
% localArrow_(ax, p1, p2, w, h, offset, label)
% Draw one transition arrow between two node centers.
%
% The line is clipped to both node borders rather than drawn center to
% center, and parallel edges between the same pair are pushed apart
% perpendicular to the run so they stay individually readable.
d = p2 - p1;
len = hypot(d(1), d(2));
if len < 1e-6
    return
end

perp = [-d(2), d(1)] / len;
shift = perp * 0.028 * offset;

a = localBorderPoint_(p1 + shift, p2 + shift, w, h);
b = localBorderPoint_(p2 + shift, p1 + shift, w, h);

plot(ax, [a(1) b(1)], [a(2) b(2)], Color = [0.42 0.47 0.54], ...
    LineWidth = 1.2, HitTest = 'off');

% Arrowhead as a filled triangle in axes units, so it scales with a zoom.
u = (b - a);
u = u / max(hypot(u(1), u(2)), 1e-6);
n = [-u(2), u(1)];
tip = b;
base = b - u * 0.022;
patch(ax, ...
    XData = [tip(1), base(1) + n(1) * 0.009, base(1) - n(1) * 0.009], ...
    YData = [tip(2), base(2) + n(2) * 0.009, base(2) - n(2) * 0.009], ...
    FaceColor = [0.42 0.47 0.54], EdgeColor = 'none', HitTest = 'off');

mid = (a + b) / 2 + perp * 0.018;
shortLabel = localTruncate_(label, 26);
text(ax, mid(1), mid(2), shortLabel, ...
    HorizontalAlignment = 'center', VerticalAlignment = 'middle', ...
    FontSize = 8, Interpreter = 'none', Color = [0.25 0.30 0.36], ...
    BackgroundColor = [1 1 1 ], Margin = 1, HitTest = 'off');
end


function localSelfLoop_(ax, p, h, label)
% localSelfLoop_(ax, p, h, label)
% Draw a self-transition as a loop above the node.
theta = linspace(-0.25 * pi, 1.25 * pi, 40);
r = 0.032;
cx = p(1);
cy = p(2) + h / 2 + r * 0.8;

plot(ax, cx + r * cos(theta) * 1.4, cy + r * sin(theta), ...
    Color = [0.42 0.47 0.54], LineWidth = 1.2, HitTest = 'off');

text(ax, cx, cy + r + 0.018, localTruncate_(label, 22), ...
    HorizontalAlignment = 'center', FontSize = 8, Interpreter = 'none', ...
    Color = [0.25 0.30 0.36], BackgroundColor = [1 1 1], Margin = 1, HitTest = 'off');
end


function q = localBorderPoint_(from, to, w, h)
% q = localBorderPoint_(from, to, w, h)
% Where the line from one node center to another crosses the first box.
d = to - from;
if abs(d(1)) < 1e-9 && abs(d(2)) < 1e-9
    q = from;
    return
end

% Scale the direction until it first leaves the half-width or half-height.
tx = Inf;
ty = Inf;
if abs(d(1)) > 1e-9
    tx = (w / 2) / abs(d(1));
end
if abs(d(2)) > 1e-9
    ty = (h / 2) / abs(d(2));
end

q = from + d * min(tx, ty);
end


function color = localOutcomeColor_(state, fallback)
% color = localOutcomeColor_(state, fallback)
% Colour a terminal node by its most meaningful response bit.
color = fallback;

bits = state.RespCodeBits;
if isempty(bits)
    return
end

% Prefer the outcome bits over the contingency bits: a hit that also delivers
% a reward should read as a hit.
preferred = epsych.BitMask.getResponses();
pick = bits(1);
for i = 1:numel(bits)
    if ismember(bits(i), preferred)
        pick = bits(i);
        break
    end
end

try
    hex = epsych.BitMask.getDefaultColors(pick);
    rgb = sscanf(char(extractAfter(string(hex), 1)), '%2x%2x%2x', 3)' / 255;
    if numel(rgb) == 3
        % Lightened so the bold state name stays readable on top.
        color = min(rgb + 0.45, 1);
    end
catch ME
    vprintf(3, 'teensy.TrialDesigner: outcome colour lookup failed: %s', ME.message);
end
end


function c = localTextColor_(bg)
% c = localTextColor_(bg)
% Black or white label, whichever contrasts with the node fill.
if 0.299 * bg(1) + 0.587 * bg(2) + 0.114 * bg(3) > 0.6
    c = [0.12 0.14 0.18];
else
    c = [1 1 1];
end
end


function s = localTruncate_(text, maxChars)
% s = localTruncate_(text, maxChars)
% Shorten an arrow label with an ellipsis.
s = char(text);
if numel(s) > maxChars
    s = [s(1:maxChars - 1) char(8230)];
end
end
