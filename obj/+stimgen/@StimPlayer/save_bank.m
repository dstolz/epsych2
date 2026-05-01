function save_bank(obj, ffn)
% save_bank(obj)
% save_bank(obj, ffn)
% Serialize the stimulus bank to a .spl file (MATLAB mat format).
%
% Parameters:
%   ffn - full file path (optional); prompts with dialog if omitted

if nargin < 2 || isempty(ffn)
    [fn, pn] = uiputfile('*.spl', 'Save Stimulus Bank', ...
        fullfile(obj.DataPath, 'StimBank.spl'));
    if isequal(fn, 0), return; end
    ffn = fullfile(pn, fn);
end

bank = struct();
bank.ISI           = obj.ISI;
bank.SelectionType = obj.SelectionType;
bank.NItems        = numel(obj.StimPlayObjs);
bank.Items         = arrayfun(@(sp) sp.toStruct, obj.StimPlayObjs, 'uni', false);

save(ffn, '-struct', 'bank', '-v7');
vprintf(1, 'StimPlayer: bank saved to "%s"', ffn);
end
