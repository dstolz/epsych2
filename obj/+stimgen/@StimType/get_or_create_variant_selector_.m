function selector = get_or_create_variant_selector_(obj)
% selector = get_or_create_variant_selector_(obj)
% Lazy-initialize the custom variant selector object specified by
% VariantSelectorClass. Returns the cached instance on subsequent calls.
%
% Returns:
%   selector - Valid epsych.TrialSelector instance.

if ~isempty(obj.variantSelectorObj_) && isa(obj.variantSelectorObj_, 'handle') && isvalid(obj.variantSelectorObj_)
    selector = obj.variantSelectorObj_;
    return
end

className = strtrim(char(obj.VariantSelectorClass));
if isempty(className)
    error('stimgen:StimType:MissingSelectorClass', ...
        'VariantSelectorClass must be provided when VariantSelectionMode is CustomSelector.');
end
if exist(className, 'class') ~= 8
    error('stimgen:StimType:SelectorClassNotFound', ...
        'Variant selector class "%s" was not found.', className);
end

selector = feval(className);
if ~isa(selector, 'epsych.TrialSelector')
    error('stimgen:StimType:SelectorClassType', ...
        'Variant selector class "%s" must inherit epsych.TrialSelector.', className);
end

if ~isempty(fieldnames(obj.VariantSelectorConfig))
    cfgNames = fieldnames(obj.VariantSelectorConfig);
    for k = 1:numel(cfgNames)
        cfgName = cfgNames{k};
        if isprop(selector, cfgName)
            selector.(cfgName) = obj.VariantSelectorConfig.(cfgName);
        end
    end
end

trialsStruct = struct('trials', {num2cell((1:max(1,numel(obj.variantCombinationTable_))).')});
selector.initialize(trialsStruct);
obj.variantSelectorObj_ = selector;
