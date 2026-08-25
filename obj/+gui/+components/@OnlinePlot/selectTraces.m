function selectTraces(obj,varargin)
% selectTraces(obj)
% Ask the operator which traces to plot, then apply the answer.
%
% The offer depends on the mode: bitmask mode lists the bank's labelled bits,
% parameter mode lists every readable parameter the runtime knows plus
% whatever is already plotted (a parameter named by the paradigm can be
% invisible, and dropping it off the list would make it unrecoverable).
% Current traces come up preselected.
%
% Choosing here marks the selection as the OPERATOR'S, which is what makes it
% outrank a `source` the constructor was given the next time this plot is
% built. A paradigm's list is a default; a hand-picked one is a decision.
%
% Cancelling changes nothing.
%
% See also: gui.components.OnlinePlot.setWatched, gui.components.OnlinePlot.reorderTraces

current = obj.traceNames;

if ~isempty(obj.BMFull_)
    choices = cellstr(cat(1,obj.BMFull_.Label));
    prompt = 'Select bits to plot';
else
    avail = {};
    if ~isempty(obj.allParams_), avail = {obj.allParams_.Name}; end
    choices = unique([avail, current], 'stable');
    prompt = 'Select parameters to plot';
end
choices = choices(:)';
if isempty(choices)
    vprintf(0,1,'gui.components.OnlinePlot: no parameters are available to plot')
    return
end

[~,pre] = ismember(current,choices);
pre = pre(pre > 0);

% listdlg is modal, so an always-on-top plot would sit over it.
gui.PopOut.setAlwaysOnTop(obj.figH,false);
restore = onCleanup(@() gui.PopOut.setAlwaysOnTop(obj.figH,obj.stayOnTop));

[sel,ok] = listdlg('PromptString',prompt, ...
    'SelectionMode','multiple', ...
    'ListString',choices, ...
    'InitialValue',pre, ...
    'ListSize',[280 320], ...
    'Name','Online Plot');
if ok == 0 || isempty(sel), return; end

picked = choices(sel);

% Keep the order the operator already has: selection answers WHICH, not
% WHERE. Anything newly added goes on top, in list order.
kept = current(ismember(current,picked));
added = picked(~ismember(picked,current));
wanted = [kept, added];

if isempty(obj.BMFull_)
    P = localResolve(obj,wanted);
    if isempty(P), return; end
    obj.setWatched(P);
else
    obj.setWatched(wanted);
end

obj.selectionByOperator_ = true;
obj.savePreferences_;
end


function P = localResolve(obj,names)
% Parameter handles for `names`, preferring the ones already resolved.
P = hw.Parameter.empty(1,0);
pool = obj.allParams_;
if ~isempty(obj.watchedParams), pool = [obj.watchedParams pool]; end
poolNames = {};
if ~isempty(pool), poolNames = {pool.Name}; end

for k = 1:numel(names)
    i = find(strcmp(poolNames,names{k}),1);
    if ~isempty(i)
        P(end+1) = pool(i); %#ok<AGROW>
        continue
    end
    p = obj.RUNTIME.find_parameter(names{k}, ...
        includeInvisible=true,silenceParameterNotFound=true);
    if ~isempty(p), P(end+1) = p(1); end %#ok<AGROW>
end
end
