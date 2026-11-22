classdef ReadPlan < handle
    % plan = hw.ReadPlan(P)
    % values = plan.read()
    % Read a fixed set of hw.Parameter values with one backend call per
    % interface instead of one per parameter.
    %
    % values{k} is exactly what P(k).Value would have returned -- same value,
    % same class -- so a caller can switch between the two without its
    % results changing. What changes is the cost. P(k).Value is a property
    % get, a connection check, an arguments block and a result reorder around
    % each device call; measured on an RZ6 it is about 120 us for a 44 us COM
    % read. A plan groups the parameters by owning interface once, and each
    % read() hands every group to its backend's get_parameter in one call.
    %
    % A plan is built for a list that is read REPEATEDLY: the trial-end sweep
    % (epsych.Runtime.all_parameters with valueOnly), a polling display.
    % Building one costs more than a single pass of P(k).Value.
    %
    % What stays on P(k).Value, because that is where it is correctly served:
    %   - write-only parameters (get.Value answers NaN and says why)
    %   - 'StimType' parameters, which are host-side objects
    %   - parameters of hw.Software, and of a parent that is not an hw.Interface
    %   - a group of one, and a group whose backend is not ready for I/O
    %     (a disconnected backend's get_parameter does not always return the
    %     stored value; get.Value does)
    %   - a group holding two parameters of the same Name, which a backend
    %     that restores the caller's order by name cannot tell apart
    %
    % A backend that cannot take an array at all (hw.VlcRecorder takes one
    % name and no options) is found out on the first read and left on
    % P(k).Value for good, rather than paying a failing call every time. Any
    % OTHER error from a batched read is not swallowed: the group is read
    % again one parameter at a time, so whatever P(k).Value throws is what the
    % caller sees, exactly as before.
    %
    % Properties:
    %   Parameters - the hw.Parameter array, in the order read() returns
    %   Names      - matlab.lang.makeValidName of each Name, computed once
    %                (a struct of the values wants these as field names)
    %
    % Methods:
    %   read      - 1xN cell of values
    %   readStruct- struct of values keyed by Names (a later duplicate wins)
    %   matches   - true when a parameter array is the one this plan was built for
    %
    % Example:
    %   plan = hw.ReadPlan(RUNTIME.all_parameters(Access='Read'));
    %   v = plan.read();          % every trial
    %
    % See also: hw.Parameter, hw.Interface.get_parameter, hw.Interface.ioReady,
    %           gui.components.OnlinePlot (which batches its own polling the same way)

    properties (SetAccess = private)
        Parameters (1,:)
        Names      (1,:) cell = {}
    end

    properties (Access = private)
        rawNames_ (1,:) cell = {}
        localIdx_ (1,:) double = zeros(1,0)
        groups_ = struct('Parent', {}, 'Params', {}, 'Idx', {}, 'Batched', {})
    end

    methods
        function obj = ReadPlan(P)
            arguments
                P = hw.Parameter.empty(1,0)
            end
            if isempty(P)
                P = hw.Parameter.empty(1,0);
            end
            P = reshape(P, 1, []);
            obj.Parameters = P;
            obj.rawNames_ = {P.Name};
            if isempty(P)
                return
            end
            obj.Names = matlab.lang.makeValidName(obj.rawNames_);

            groups = obj.groups_;
            for k = 1:numel(P)
                p = P(k);
                parent = p.Parent;
                if isequal(p.Access, 'Write') || isequal(p.Type, 'StimType') ...
                        || ~isa(parent, 'hw.Interface') || isa(parent, 'hw.Software') ...
                        || ~isvalid(parent)
                    obj.localIdx_(end+1) = k;
                    continue
                end

                g = 0;
                for j = 1:numel(groups)
                    % Class first, and short-circuit: == across two different
                    % handle classes errors, and a rig may mix backends.
                    if strcmp(class(groups(j).Parent), class(parent)) && groups(j).Parent == parent
                        g = j;
                        break
                    end
                end
                if g == 0
                    groups(end+1) = struct('Parent', parent, 'Params', p, 'Idx', k, 'Batched', true);
                else
                    groups(g).Params(end+1) = p;
                    groups(g).Idx(end+1) = k;
                end
            end

            for g = 1:numel(groups)
                n = numel(groups(g).Idx);
                names = {groups(g).Params.Name};
                groups(g).Batched = n > 1 && numel(unique(names)) == n;
            end
            obj.groups_ = groups;
        end

        function tf = matches(obj, P)
            % tf = matches(obj, P)
            % True when P is the parameter array this plan was built for:
            % the same handles in the same order under the same names.
            tf = numel(P) == numel(obj.Parameters);
            if ~tf || isempty(P)
                return
            end
            tf = all(reshape(P, 1, []) == obj.Parameters) && isequal({P.Name}, obj.rawNames_);
        end

        function values = read(obj)
            % values = read(obj)
            % 1xN cell; values{k} is what Parameters(k).Value returns.
            P = obj.Parameters;
            values = cell(1, numel(P));

            for k = obj.localIdx_
                values{k} = P(k).Value;
            end

            for g = 1:numel(obj.groups_)
                G = obj.groups_(g);

                if ~G.Batched || ~G.Parent.ioReady()
                    for k = G.Idx
                        values{k} = P(k).Value;
                    end
                    continue
                end

                ok = false;
                try
                    v = G.Parent.get_parameter(G.Params, includeInvisible = true);
                    ok = iscell(v) && numel(v) == numel(G.Idx);
                    if ~ok
                        % An answer of the wrong shape is how this backend
                        % answers an array; it will not change.
                        obj.groups_(g).Batched = false;
                        vprintf(2, 'hw.ReadPlan: %s does not return one value per parameter; reading one at a time', ...
                            class(G.Parent));
                    end
                catch ME
                    if hw.ReadPlan.isSignatureError_(ME)
                        obj.groups_(g).Batched = false;
                        vprintf(2, 'hw.ReadPlan: %s cannot batch reads, reading one at a time (%s)', ...
                            class(G.Parent), ME.message);
                    end
                    % Anything else is a real failure. Fall through to the
                    % per-parameter read, which raises it the way it always
                    % was raised.
                end

                if ~ok
                    for k = G.Idx
                        values{k} = P(k).Value;
                    end
                    continue
                end

                for j = 1:numel(G.Idx)
                    x = v{j};
                    if isnumeric(x)
                        x = double(x);   % as hw.Parameter.get.Value does
                    end
                    values{G.Idx(j)} = x;
                end
            end
        end

        function S = readStruct(obj)
            % S = readStruct(obj)
            % The values as a struct keyed by Names. Two parameters whose
            % names make the same field keep the first one's position and
            % the last one's value, as assigning them in order always did.
            values = obj.read();
            S = struct();
            names = obj.Names;
            for k = 1:numel(names)
                S.(names{k}) = values{k};
            end
        end
    end

    methods (Static, Access = private)
        function tf = isSignatureError_(ME)
            % An error that says "this backend's get_parameter does not take
            % that call", as opposed to one that says the read failed.
            tf = any(strcmp(ME.identifier, { ...
                'MATLAB:TooManyInputs', ...
                'MATLAB:maxrhs', ...
                'MATLAB:InputParser:ArgumentFailedValidation', ...
                'MATLAB:validators:mustBeTextScalar', ...
                'MATLAB:validation:IncompatibleSize', ...
                'MATLAB:functionValidation:NotEnoughInputs', ...
                'MATLAB:unrecognizedStringChoice'})) ...
                || startsWith(ME.identifier, 'MATLAB:functionValidation') ...
                || startsWith(ME.identifier, 'MATLAB:validation') ...
                || contains(ME.message, 'Too many input arguments');
        end
    end
end
