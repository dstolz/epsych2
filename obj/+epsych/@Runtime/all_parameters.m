function P = all_parameters(obj, options)
    % P = all_parameters(obj, options)
    % Retrieve all parameters from all registered interfaces, with optional filtering.
    %
    % Parameters:
    %   obj                      - epsych.Runtime instance.
    %   options.includeTriggers  - Include trigger parameters (default: false).
    %   options.includeInvisible - Include invisible parameters (default: false).
    %   options.includeArray     - Include array-valued parameters (default: true).
    %   options.Access           - Filter by access: 'Read', 'Write', 'Any', 'All', 'Read / Write' (default: 'Read').
    %   options.asStruct         - Return as struct keyed by validName instead of array (default: false).
    %   options.valueOnly        - Return only each parameter's Value instead of the hw.Parameter object.
    %                             With asStruct, struct fields hold the Values; otherwise a cell array of
    %                             Values is returned (default: false).
    %   options.Interface        - Char, string, or cellstr of class name(s) to restrict results to one or
    %                             more specific interface classes (default: {}, returns all interfaces).
    %
    % Returns:
    %   P - hw.Parameter array, or struct if asStruct is true. If valueOnly is true, returns a cell array
    %       of Values, or a struct of Values when asStruct is also true.

    arguments
        obj
        options.asStruct (1,1) logical = false
        options.valueOnly (1,1) logical = false
        options.includeInvisible (1,1) logical = false
        options.includeTriggers (1,1) logical = false
        options.includeArray (1,1) logical = true
        options.Access (1,:) char {mustBeMember(options.Access,{'Read','Write','Any','All','Read / Write'})} = 'Read'
        options.Interface = {}
    end

    asStruct = options.asStruct;
    options = rmfield(options, 'asStruct');

    valueOnly = options.valueOnly;
    options = rmfield(options, 'valueOnly');

    interfaceFilter = cellstr(options.Interface);  % normalize to cellstr; empty cellstr means no filter
    
    options = rmfield(options, 'Interface');

    copts = namedargs2cell(options);
    P = hw.Parameter.empty;
    for i = 1:numel(obj.Interfaces)
        iface = obj.Interfaces(i);
        if ~isempty(interfaceFilter) && ~any(cellfun(@(c) isa(iface, c), interfaceFilter))
            continue
        end
        P = [P, iface.all_parameters(copts{:})];
    end

    if valueOnly
        % Values come through a read plan: one backend call per interface
        % rather than a property get per parameter, and field names made
        % once rather than on every call. The trial-end sweep asks this of
        % every readable parameter at every trial boundary, while the
        % subject waits. The plan is kept and reused for as long as the
        % parameter list it was built for is the one asked for again -- the
        % same handles under the same names -- so a recompile, a phase load
        % or a parameter added mid-session simply builds a new one. Each
        % value is exactly what P(k).Value returns (hw.ReadPlan).
        plan = obj.ReadPlanCache_;
        if isempty(plan) || ~isvalid(plan) || ~plan.matches(P)
            plan = hw.ReadPlan(P);
            obj.ReadPlanCache_ = plan;
        end
        if asStruct
            P = plan.readStruct();
        else
            P = plan.read();
        end
    elseif asStruct
        P_ = struct();
        for k = 1:numel(P)
            P_.(P(k).validName) = P(k);
        end
        P = P_;
    end
end
