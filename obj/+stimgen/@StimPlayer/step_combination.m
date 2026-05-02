function step_combination(obj, step)
% step_combination(obj)
% step_combination(obj, step)
% Step the selected stimulus variant combination and refresh the preview plot.
%
% Parameters:
%   step - Signed integer step size (default +1).

if nargin < 2 || isempty(step)
    step = 1;
end

h = obj.handles;
if ~isfield(h, 'BankList') || ~isvalid(h.BankList)
    return
end
if isempty(h.BankList.Value)
    return
end

idx = h.BankList.Value;
if idx < 1 || idx > numel(obj.StimPlayObjs)
    return
end

try
    stimObj = obj.StimPlayObjs(idx).CurrentStimObj;
    info = stimObj.step_variant(step);

    obj.refresh_combo_controls_;
    obj.update_signal_plot;
    obj.set_status_(sprintf('Showing combo %d of %d.', info.ActiveIndex, info.NumCombinations));
catch ME
    obj.report_gui_error_(ME, "Combination Step Error", ...
        "StimPlayer could not step to the requested stimulus combination.");
end
end
