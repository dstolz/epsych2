function P = filter_parameters(obj, propertyName, propertyValue, options, poptions)
    % P = filter_parameters(obj, propertyName, propertyValue, options, poptions)
    % Return hw.Parameter objects whose named property matches a target value.
    %
    % Parameters:
    %   obj                       - epsych.Runtime instance.
    %   propertyName              - Name of the hw.Parameter property to test.
    %   propertyValue             - Target value or pattern passed to testFcn.
    %   options.testFcn           - Comparator function (default: @isequal); e.g. @contains.
    %   poptions.includeTriggers  - Include trigger parameters (default: false).
    %   poptions.includeInvisible - Include invisible parameters (default: false).
    %
    % Returns:
    %   P - hw.Parameter array matching the filter criterion.
    arguments
        obj
        propertyName (1,:) char
        propertyValue
        options.testFcn (1,1) function_handle = @isequal
        poptions.includeTriggers (1,1) logical = false
        poptions.includeInvisible (1,1) logical = false
    end
    poptions = namedargs2cell(poptions);
    P = obj.all_parameters(poptions{:});
    ind = arrayfun(@(a) obj.local_test(options.testFcn, a.(propertyName), propertyValue), P);
    P = P(ind);

end
