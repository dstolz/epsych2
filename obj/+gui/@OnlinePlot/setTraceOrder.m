function setTraceOrder(obj,order,options)
% setTraceOrder(obj,order)
% setTraceOrder(obj,order,Rebuild=false)
% Reorder the traces up the y axis, bottom first.
%
% `order` is either a permutation of 1:N, or the trace names in the order
% wanted. Names are matched against traceNames, and matching by name is what
% makes a REMEMBERED order survive a protocol edit: a name this plot does not
% have is ignored, and a trace the saved order never heard of keeps its
% relative place at the end rather than disappearing.
%
% Per-trace colours and widths travel WITH their traces, so a trace the
% operator recoloured keeps its colour when moved. (setWatched, which changes
% the set rather than the order, resets them.)
%
% Name=Value
%   Rebuild - Rebuild the axes now. Default true; preference loading passes
%             false because setup_plot is about to run anyway.
%
% See also: gui.OnlinePlot.reorderTraces, gui.OnlinePlot.traceNames

arguments
    obj
    order
    options.Rebuild (1,1) logical = true
end

names = obj.traceNames;
n = numel(names);
if n == 0, return; end

if isnumeric(order) || islogical(order)
    perm = double(order(:))';
    if ~isequal(sort(perm), 1:n)
        vprintf(0,1,'gui.OnlinePlot: setTraceOrder needs a permutation of 1:%d',n)
        return
    end
else
    wanted = cellstr(order);
    wanted = wanted(ismember(wanted,names));       % drop names we do not have
    [~,perm] = ismember(wanted,names);
    perm = perm(:)';
    perm = [perm, setdiff(1:n, perm, 'stable')];   % unnamed traces keep their order, at the end
end

if isequal(perm,1:n), return; end % nothing to do

% Materialize the per-trace vectors BEFORE permuting: the getters expand a
% short or empty vector from the palette, and permuting the expanded form is
% what carries a hand-picked colour along with its trace.
c = obj.lineColors;
w = obj.lineWidth;

if isempty(obj.BM)
    obj.watchedParams = obj.watchedParams(perm);
else
    obj.BM = localPermuteBanks(obj.BM, perm);
end

obj.lineColors = c(perm,:);
obj.lineWidth  = w(perm);
obj.yPositions = zeros(0,1); % back to 1:N in the new order
obj.planDirty_ = true;

if ~options.Rebuild, return; end

obj.setup_plot;
obj.rebuildTraceColorMenu_;
obj.savePreferences_;
end


function BM = localPermuteBanks(BMIn,perm)
% Apply a trace-level permutation to bank-level records.
%
% Traces are the concatenation of every bank's bits, so a permutation can
% interleave two banks. Each contiguous run of one bank becomes its own
% record -- the bank parameter is still read once per record, and identical
% banks collapse again on the next read plan because they share a Parent.
bank = []; lbl = {}; bit = [];
for i = 1:numel(BMIn)
    bank = [bank repmat(i,1,BMIn(i).N)]; %#ok<AGROW>
    lbl  = [lbl; cellstr(BMIn(i).Label(:))]; %#ok<AGROW>
    bit  = [bit; BMIn(i).Bit(:)]; %#ok<AGROW>
end
bank = bank(perm); lbl = lbl(perm); bit = bit(perm);

BM = BMIn([]);
k = 1;
while k <= numel(bank)
    j = k;
    while j < numel(bank) && bank(j+1) == bank(k), j = j + 1; end
    BM(end+1).Bank = BMIn(bank(k)).Bank; %#ok<AGROW>
    BM(end).Label = lbl(k:j);
    BM(end).Bit = bit(k:j);
    BM(end).N = j - k + 1;
    k = j + 1;
end
end
