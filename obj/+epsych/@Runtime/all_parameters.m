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
    %   options.Interface        - Char, string, or cellstr of class name(s) to restrict results to one or
    %                             more specific interface classes (default: {}, returns all interfaces).
    %
    % Returns:
    %   P - hw.Parameter array, or struct if asStruct is true.

    arguments
        obj
        options.asStruct (1,1) logical = false
        options.includeInvisible (1,1) logical = false
        options.includeTriggers (1,1) logical = false
        options.includeArray (1,1) logical = true
        options.Access (1,:) char {mustBeMember(options.Access,{'Read','Write','Any','All','Read / Write'})} = 'Read'
        options.Interface = {}
    end

    asStruct = options.asStruct;
    options = rmfield(options, 'asStruct');

    interfaceFilter = cellstr(options.Interface);  % normalize to cellstr; empty cellstr means no filter
    
    options = rmfield(options, 'Interface');

    copts = namedargs2cell(options);
    P = hw.Parameter.empty;
    for i = 1:numel(obj.Interfaces)
        iface = obj.Interfaces(i);
        if ~isempty(interfaceFilter) && ~any(cellfun(@(c) isa(iface, c), interfaceFilter))
            continue
        end
        vprintf(4, 'Retrieving all parameters from %s', class(iface))
        P = [P, iface.all_parameters(copts{:})];
    end

    if asStruct
        P_ = struct();
        for k = 1:numel(P)
            P_.(P(k).validName) = P(k);
        end
        P = P_;
    end
end
