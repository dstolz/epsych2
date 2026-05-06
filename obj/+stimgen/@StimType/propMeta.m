function m = propMeta(~)
% propMeta(obj)
% Return display metadata for GUI-visible base properties.
% Subclasses can override this and merge with the base struct.
%
% Each field name matches a property name. Each value is a struct with:
%   label     (required) - display label string
%   format    (optional) - printf format string for numeric fields
%   limits    (optional) - [min max] for numeric editfield
%   widget    (optional) - 'numeric'|'text'|'checkbox'|'dropdown'
%   items     (optional) - dropdown display items
%   itemsData (optional) - dropdown underlying values
m = struct();
m.SoundLevel     = struct('label', 'Sound Level',     'format', '%.1f dB SPL');
m.Duration       = struct('label', 'Duration',        'format', '%.3f s',  'limits', [0.001 10]);
m.WindowDuration = struct('label', 'Window Duration', 'format', '%.4f s',  'limits', [1e-6 10]);
m.ApplyWindow    = struct('label', 'Apply Window');
m.VariantSelectionMode = struct('label', 'Variant Selection', 'widget', 'dropdown', ...
    'items', ["Serial" "ShuffleUniform" "ShuffleLeastUsed" "CustomSelector"]);
m.VariantCombinationMode = struct('label', 'Variant Combination', 'widget', 'dropdown', ...
    'items', ["Cartesian" "PairwiseStrict" "PairwiseScalarExpand"]);
m.VariantSelectorClass = struct('label', 'Variant Selector Class');
m.VariantReselectOnUpdate = struct('label', 'Reselect Variant Each Update');
end
