function colors = getDefaultColors(bitMasks)
% colors = epsych.BitMask.getDefaultColors(bitMasks)
% Return default hex colors for BitMask values.
% Parameters:
%   bitMasks - Optional epsych.BitMask array or numeric array of valid enum
%       values. If omitted, colors are returned for all enum members.
% Returns:
%   colors - String array of hex color values matching the size of bitMasks.
%
% See also documentation/epsych/epsych_BitMask.md for grouped usage examples.

if nargin < 1 || isempty(bitMasks)
    bitMasks = epsych.BitMask.getAll;
end

if isa(bitMasks, 'epsych.BitMask')
    bitValues = uint32(bitMasks);
else
    if ~isnumeric(bitMasks) || ~all(isfinite(bitMasks(:))) || ~all(bitMasks(:) == floor(bitMasks(:)))
        error('bitMasks must be an epsych.BitMask array or integer numeric values.');
    end
    bitValues = uint32(bitMasks);
end

allMasks = epsych.BitMask.getAll;
allValues = uint32(allMasks);
defaultColors = [...
    "#b8b8b8"; ... % Undefined
    "#1fa050"; ... % Hit
    "#db3939"; ... % Miss
    "#0d42f0"; ... % CorrectReject
    "#ff8800"; ... % FalseAlarm
    "#585757"; ... % Abort
    "#18b368"; ... % Reward
    "#7a2338"; ... % Punish
    "#8ecae6"; ... % PreResponseWindow
    "#219ebc"; ... % ResponseWindow
    "#023047"; ... % PostResponseWindow
    "#264653"; ... % TrialType_0
    "#2a9d8f"; ... % TrialType_1
    "#e9c46a"; ... % TrialType_2
    "#f4a261"; ... % TrialType_3
    "#e76f51"; ... % TrialType_4
    "#8ab17d"; ... % TrialType_5
    "#3a86ff"; ... % Choice_0
    "#8338ec"; ... % Choice_1
    "#ff006e"; ... % Choice_2
    "#fb5607"; ... % Choice_3
    "#ffbe0b"; ... % Choice_4
    "#6a994e"; ... % Choice_5
    "#003049"; ... % Option_A
    "#d62828"; ... % Option_B
    "#f77f00"; ... % Option_C
    "#fcbf49"; ... % Option_D
    "#2a9d8f"; ... % Option_E
    "#577590"; ... % Option_F
    "#90be6d"; ... % Option_G
    "#9b5de5"; ... % Option_H
    "#f15bb5"];    % Option_I

[tf, loc] = ismember(bitValues(:), allValues);
if ~all(tf)
    error('bitMasks contains values that are not defined in epsych.BitMask.');
end

colors = reshape(defaultColors(loc), size(bitValues));
