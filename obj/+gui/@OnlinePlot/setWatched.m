function setWatched(obj,source,options)
% setWatched(obj,source)
% setWatched(obj,source,Rebuild=false)
% Replace the plotted traces.
%
% This is the one place the trace set changes; the Select Traces... dialog
% and a script both come through here, so the operator can do nothing to
% this plot that a paradigm cannot do to it.
%
% `source` is interpreted in the order that makes the common calls do the
% obvious thing:
%   * hw.Parameter array          - plot exactly these, in this order
%   * bit labels of a live bank   - in bitmask mode, show this subset of bits
%   * parameter or bank name(s)   - resolved the way the constructor does
%
% The per-trace COLOURS AND WIDTHS ARE RESET to the palette, because the
% trace set has changed and a colour carried over by position would land on
% a different signal. setTraceOrder, which only permutes, keeps them.
%
% Name=Value
%   Rebuild - Rebuild the axes and buffers now. Default true. Loading saved
%             preferences passes false: the timer's StartFcn is about to run
%             setup_plot anyway, and doing it twice throws away the first
%             samples for nothing.
%
% See also: gui.OnlinePlot.setTraceOrder, gui.OnlinePlot.selectTraces

arguments
    obj
    source
    options.Rebuild (1,1) logical = true
end

if isempty(source)
    vprintf(1,'gui.OnlinePlot: ignoring an empty trace selection')
    return
end

if isa(source,'hw.Parameter')
    obj.BM = [];
    obj.watchedParams = source(:)';

elseif ~isempty(obj.BMFull_) && localAllAreBitLabels(obj.BMFull_,source)
    % Bitmask mode: `source` names bits, so narrow each bank to the bits
    % asked for. The full definition is kept in BMFull_, which is what lets
    % a hidden bit come back without re-reading the protocol.
    obj.BM = localSelectBits(obj.BMFull_, cellstr(source));

else
    % Names: let the constructor's resolver decide parameters vs banks.
    obj.BM = [];
    obj.watchedParams = [];
    obj.resolve_source(cellstr(source));
end

if isempty(obj.BM) && isempty(obj.watchedParams)
    vprintf(0,1,'gui.OnlinePlot: nothing matched the requested traces; leaving the plot unchanged')
    return
end

% A trace set of a different size invalidates every per-trace vector. They
% are cleared rather than trimmed so the getters regenerate from the palette.
obj.yPositions = zeros(0,1);
obj.lineColors = zeros(0,3);
obj.lineWidth  = zeros(0,1);
obj.planDirty_ = true;

if ~options.Rebuild, return; end

obj.setup_plot;      % new lines, new labels, fresh buffers
obj.rebuildTraceColorMenu_;
obj.refreshMenuChecks_;
obj.savePreferences_;
end


function tf = localAllAreBitLabels(BMFull,source)
% True when every entry names a labelled bit of one of the banks.
if isa(source,'hw.Parameter'), tf = false; return; end
try
    src = cellstr(source);
catch
    tf = false; return
end
known = cat(1,BMFull.Label);
tf = ~isempty(src) && all(ismember(src, cellstr(known(:))));
end


function BM = localSelectBits(BMFull,wanted)
% Narrow each bank to the wanted bit labels, dropping banks left with none.
% Bit order follows `wanted`, so this doubles as a reorder within a bank.
BM = BMFull([]);
for i = 1:numel(BMFull)
    lbl = cellstr(BMFull(i).Label(:));
    [tf,pos] = ismember(wanted, lbl);
    keep = pos(tf);
    if isempty(keep), continue; end
    BM(end+1).Bank = BMFull(i).Bank; %#ok<AGROW>
    BM(end).Label = lbl(keep);
    BM(end).Bit = BMFull(i).Bit(keep);
    BM(end).N = numel(keep);
end
end
