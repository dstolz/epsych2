function load_bank(obj, ffn)
% load_bank(obj)
% load_bank(obj, ffn)
% Load a stimulus bank from a .spl file and rebuild StimPlayObjs.
%
% Parameters:
%   ffn - full file path (optional); prompts with dialog if omitted

if nargin < 2 || isempty(ffn)
    [fn, pn] = uigetfile('*.spl', 'Load Stimulus Bank', obj.DataPath);
    if isequal(fn, 0), return; end
    ffn = fullfile(pn, fn);
end

bank = load(ffn, '-mat');

obj.ISI           = bank.ISI;
obj.SelectionType = string(bank.SelectionType);

sps = stimgen.StimPlay.empty(0,1);
for k = 1:bank.NItems
    S = bank.Items{k};

    % Reconstruct the StimType object from its serialized struct
    stimClass = char(S.StimObj.Class);
    stimObj   = stimgen.(stimClass)();

    % Restore base StimType properties
    baseProps = {'SoundLevel','Duration','WindowDuration','WindowFcn', ...
                 'ApplyCalibration','ApplyWindow','Fs'};
    for j = 1:numel(baseProps)
        p = baseProps{j};
        if isfield(S.StimObj, p)
            try
                stimObj.(p) = S.StimObj.(p);
            catch ME
                vprintf(0, 1, ME);
            end
        end
    end

    % Restore subclass-specific (UserProperties)
    if isfield(S.StimObj, 'UserProperties')
        for j = 1:numel(S.StimObj.UserProperties)
            p = char(S.StimObj.UserProperties(j));
            if isfield(S.StimObj, p)
                try
                    stimObj.(p) = S.StimObj.(p);
                catch ME
                    vprintf(0, 1, ME);
                end
            end
        end
    end

    sp      = stimgen.StimPlay(stimObj);
    sp.Reps = S.Reps;
    sp.Name = S.Name;
    sp.ISI  = S.ISI;

    sps(end+1, 1) = sp; %#ok<AGROW>
end

obj.StimPlayObjs = sps;

ISIField_sync_(obj);

obj.refresh_listbox_;
obj.clear_tabs_;
obj.update_counter_;

vprintf(1, 'StimPlayer: bank loaded from "%s" (%d items).', ffn, numel(sps));
end


function ISIField_sync_(obj)
% Sync the ISI editfield text with obj.ISI after a load.
h = obj.handles;
if isfield(h, 'ISIField') && isvalid(h.ISIField)
    h.ISIField.Value = mat2str(obj.ISI);
end
if isfield(h, 'OrderDD') && isvalid(h.OrderDD)
    h.OrderDD.Value = obj.SelectionType;
end
end
