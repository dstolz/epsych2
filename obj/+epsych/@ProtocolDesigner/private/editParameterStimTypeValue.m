function [stimValues, cancelled] = editParameterStimTypeValue(~, parameter)
% [stimValues, cancelled] = editParameterStimTypeValue(obj, parameter)
% Edit StimType levels for a ProtocolDesigner parameter via StimPlayer.
%
% Parameters:
%   parameter - hw.Parameter with Type 'StimType' being edited.
%
% Returns:
%   stimValues - Cell array of stimgen.StimType objects chosen by the user.
%   cancelled  - True when the operation is dismissed without applying changes.

cancelled = false;
stimValues = parameter.Values;

try
    player = stimgen.StimPlayer();
catch ME
    vprintf(0, 1, ME);
    cancelled = true;
    return
end

localSeedPlayerBank_(player, stimValues);

dialog = uifigure( ...
    'Name', sprintf('StimType Bank Editor: %s', parameter.Name), ...
    'Position', [220 220 600 300], ...
    'WindowStyle', 'normal', ...
    'CloseRequestFcn', @onCancel, ...
    'Resize', 'off');

uilabel(dialog, ...
    'Text', sprintf('Editing StimType levels for "%s"', parameter.Name), ...
    'Position', [20 256 560 24], ...
    'FontSize', 15, ...
    'FontWeight', 'bold');

uilabel(dialog, ...
    'Text', ['Use the StimPlayer window to add, remove, or configure stimuli. ' ...
             'Click Apply Current Bank when ready.'], ...
    'Position', [20 220 560 30], ...
    'FontAngle', 'italic', ...
    'FontColor', [0.36 0.43 0.52]);

uilabel(dialog, ...
    'Text', 'You can also load a saved StimPlayer bank (.spl) first, then apply it.', ...
    'Position', [20 196 560 20], ...
    'FontColor', [0.36 0.43 0.52]);

uilabel(dialog, ...
    'Text', 'This window stays open while you work in StimPlayer.', ...
    'Position', [20 174 560 18], ...
    'FontColor', [0.36 0.43 0.52]);

uibutton(dialog, 'push', ...
    'Text', 'Load Saved Bank...', ...
    'Position', [20 132 170 34], ...
    'Tooltip', 'Load a .spl StimPlayer bank into the active StimPlayer window.', ...
    'ButtonPushedFcn', @onLoadBank);

uibutton(dialog, 'push', ...
    'Text', 'Apply Current Bank', ...
    'Position', [352 24 140 36], ...
    'FontWeight', 'bold', ...
    'ButtonPushedFcn', @onApply);

uibutton(dialog, 'push', ...
    'Text', 'Cancel', ...
    'Position', [504 24 76 36], ...
    'ButtonPushedFcn', @onCancel);

uiwait(dialog);

    function onLoadBank(~, ~)
        if isempty(player) || ~isvalid(player)
            uialert(dialog, ...
                'StimPlayer window is no longer available. Close this dialog and retry.', ...
                'StimPlayer Closed');
            return
        end

        [fn, pn] = uigetfile('*.spl', 'Load StimPlayer Bank');
        if isequal(fn, 0)
            return
        end

        try
            player.load_bank(fullfile(pn, fn));
        catch ME
            vprintf(0, 1, ME);
            uialert(dialog, ...
                'Unable to load the selected .spl bank. See command window/log output for details.', ...
                'Load Failed');
        end
    end

    function onApply(~, ~)
        if isempty(player) || ~isvalid(player)
            uialert(dialog, ...
                'StimPlayer window was closed before applying. No changes were made.', ...
                'StimPlayer Closed');
            cancelled = true;
            delete(dialog);
            return
        end

        stimValues = localExtractPlayerStimTypes_(player);
        localClosePlayer_(player);
        delete(dialog);
    end

    function onCancel(~, ~)
        cancelled = true;
        localClosePlayer_(player);
        delete(dialog);
    end
end


function localSeedPlayerBank_(player, stimValues)
if isempty(stimValues)
    return
end

for k = 1:numel(stimValues)
    stim = stimValues{k};
    if ~isa(stim, 'stimgen.StimType')
        continue
    end

    label = string(stim.DisplayName);
    if strlength(label) == 0
        className = string(class(stim));
        parts = split(className, '.');
        label = parts(end);
    end

    player.open_stim(stim, Name=label);
end
end


function stimValues = localExtractPlayerStimTypes_(player)
if isempty(player.StimPlayObjs)
    stimValues = {};
    return
end

n = numel(player.StimPlayObjs);
stimValues = cell(1, n);
for k = 1:n
    stimValues{k} = player.StimPlayObjs(k).StimObj;
end
end


function localClosePlayer_(player)
if isempty(player) || ~isvalid(player)
    return
end

delete(player);
end
