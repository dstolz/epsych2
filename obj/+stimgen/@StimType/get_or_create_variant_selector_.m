function selector = get_or_create_variant_selector_(obj)
% selector = get_or_create_variant_selector_(obj)
% Lazy-initialize the custom variant selector object specified by
% VariantSelectorClass. Returns the cached instance on subsequent calls.
%
% Returns:
%   selector - Selector instance exposing initialize() and selectNext().

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

% Duck-typed rather than tied to a concrete base class so selectors can be
% supplied by any host application. Both methods are exercised: initialize
% below, selectNext in select_variant_index_.
selector = feval(className);
requiredMethods = {'initialize','selectNext'};
missing = requiredMethods(~cellfun(@(m) ismethod(selector, m), requiredMethods));
if ~isempty(missing)
    error('stimgen:StimType:SelectorClassType', ...
        'Variant selector class "%s" must define method(s): %s.', ...
        className, strjoin(missing, ', '));
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
