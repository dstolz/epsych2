classdef ParamSweep < stimgen.StimType
    % obj = stimgen.ParamSweep(stim, Name, Value, ...)
    % Generic full-factorial parameter-sweep stimulus container.
    %
    % Package guide: documentation/stimgen/stimgen_overview.md
    % Class guide: documentation/stimgen/stimgen_StimType.md
    %
    % Wraps any stimgen.StimType subclass (the Prototype) and builds a
    % full-factorial array of child stimulus objects from a SweepParams
    % struct. Replaces the tightly-coupled stimgen.multiTone class.
    %
    % Parameters:
    %   stim        - class name string (e.g. 'stimgen.Tone') or an existing
    %                 StimType instance to use as the prototype (deep-copied)
    %   Name,Value  - any StimType base properties (Duration, Fs, SoundLevel,
    %                 WindowDuration, ApplyWindow, WindowFcn, ApplyCalibration)
    %                 applied to the wrapper AND propagated to all children
    %
    % Properties:
    %   Prototype    - template stimulus object; stim-specific defaults live here
    %   SweepParams  - struct whose fields are Prototype property names and
    %                  values are numeric arrays or MATLAB expression strings;
    %                  reassigning this property triggers a full rebuild
    %   MultiObjects - (read-only) array of generated child StimType objects
    %
    % Returns:
    %   obj - stimgen.ParamSweep instance
    %
    % Usage examples:
    %   % Tone swept over frequency × level (full-factorial grid)
    %   ps = stimgen.ParamSweep('stimgen.Tone');
    %   ps.Duration = 0.25;
    %   ps.SweepParams = struct('Frequency',  [1000 2000 4000 8000 16000], ...
    %                           'SoundLevel', 0:7:70);
    %   % → 55 children in ps.MultiObjects
    %
    %   % Pre-configured prototype
    %   t = stimgen.Tone('OnsetPhase', pi/4);
    %   ps = stimgen.ParamSweep(t);
    %   ps.SweepParams = struct('Frequency', "500*2.^(0:5)"); % expression string
    %
    %   % Band-limited noise swept over bandwidth × level
    %   ps = stimgen.ParamSweep('stimgen.Noise');
    %   ps.SweepParams = struct('HighPass', [100 500 1000], 'SoundLevel', [50 60 70]);

    % ---------------------------------------------------------------
    % Properties
    % ---------------------------------------------------------------

    properties
        Prototype (1,1) stimgen.StimType   % template instance; stim-type-specific defaults live here
    end

    properties (SetObservable, AbortSet)
        SweepParams (1,1) struct = struct()  % fieldnames = Prototype property names; values = numeric arrays or expression strings
    end

    properties (SetAccess = protected)
        MultiObjects (1,:) stimgen.StimType = stimgen.StimType.empty  % generated child objects (read-only)
    end

    % ---------------------------------------------------------------
    % Constants required by StimType
    % ---------------------------------------------------------------

    properties (Constant)
        IsMultiObj      = true;
        CalibrationType = "noise";   % vestigial at wrapper level; children use their own
        Normalization   = "rms";     % vestigial at wrapper level
    end

    % ---------------------------------------------------------------
    % Public methods
    % ---------------------------------------------------------------

    methods

        function obj = ParamSweep(stim, varargin)
            % ParamSweep(stim, Name, Value, ...)
            % stim: class name string or StimType instance

            obj = obj@stimgen.StimType(varargin{:});

            if nargin < 1 || isempty(stim)
                stim = 'stimgen.Tone';
            end

            if ischar(stim) || isstring(stim)
                ctor = str2func(stim);
                obj.Prototype = ctor();
            else
                obj.Prototype = copy(stim);
            end

            obj.DisplayName = sprintf('ParamSweep(%s)', class(obj.Prototype));
            obj.UserProperties = ["SweepParams", "Duration", "Fs", ...
                                   "WindowDuration", "WindowFcn", "ApplyWindow", "ApplyCalibration"];
        end

        function update_signal(obj)
            % update_signal - Rebuild MultiObjects and concatenate their signals.
            obj.build_multi_objects();

            if isempty(obj.MultiObjects)
                obj.Signal = [];
                return
            end

            sigs = arrayfun(@(c) c.Signal(:), obj.MultiObjects, 'UniformOutput', false);
            obj.Signal = horzcat(sigs{:});
        end

        function S = toStruct(obj)
            % toStruct - Serialize ParamSweep to struct, including Prototype.
            S = toStruct@stimgen.StimType(obj);
            S.StimClass  = class(obj.Prototype);
            S.Prototype  = obj.Prototype.toStruct();
            S.SweepParams = obj.SweepParams;
        end

    end % methods (public)

    % ---------------------------------------------------------------
    % Protected methods
    % ---------------------------------------------------------------

    methods (Access = protected)

        function build_multi_objects(obj)
            % build_multi_objects - Build full-factorial array of child stims.
            %
            % 1. Evaluates each SweepParams field (string → eval; numeric → direct).
            % 2. Builds an ndgrid of all combinations.
            % 3. For each grid point: copy(Prototype), propagate wrapper base
            %    properties + calibration, set swept values, call update_signal().

            fields = fieldnames(obj.SweepParams);

            if isempty(fields)
                obj.MultiObjects = stimgen.StimType.empty;
                return
            end

            % Validate that each field exists on the Prototype
            for k = 1:numel(fields)
                if ~isprop(obj.Prototype, fields{k})
                    error('stimgen:ParamSweep:invalidParam', ...
                        'SweepParams field ''%s'' is not a property of %s.', ...
                        fields{k}, class(obj.Prototype));
                end
            end

            % Evaluate each parameter value vector
            paramVecs = cell(1, numel(fields));
            for k = 1:numel(fields)
                v = obj.SweepParams.(fields{k});
                if ischar(v) || isstring(v)
                    paramVecs{k} = eval(v);
                else
                    paramVecs{k} = v(:)';  % ensure row vector
                end
            end

            % Build full-factorial grid
            gridCells = cell(1, numel(fields));
            [gridCells{:}] = ndgrid(paramVecs{:});
            nTotal = numel(gridCells{1});

            % Identify base StimType property names to propagate from wrapper to child
            baseProps = ["Duration", "Fs", "WindowDuration", "WindowFcn", ...
                         "ApplyWindow", "ApplyCalibration"];

            children(1, nTotal) = copy(obj.Prototype);  % pre-allocate with valid objects
            for i = 1:nTotal
                child = copy(obj.Prototype);

                % Propagate wrapper base properties
                for p = baseProps
                    % Only propagate if the wrapper has a non-swept value for it
                    if ~ismember(char(p), fields) && isprop(child, char(p))
                        child.(char(p)) = obj.(char(p));
                    end
                end

                % Propagate calibration
                child.Calibration = obj.Calibration;

                % Set swept property values
                for k = 1:numel(fields)
                    child.(fields{k}) = gridCells{k}(i);
                end

                child.update_signal();
                children(i) = child;
            end

            obj.MultiObjects = children;
        end

        function m = propMeta(obj)
            % propMeta - GUI metadata for ParamSweep properties.
            m = struct();
            m.SweepParams = struct('label', 'Sweep Parameters', 'widget', 'text');
            m = stimgen.StimType.merge_prop_meta(m, propMeta@stimgen.StimType(obj));
        end

    end % methods (protected)

end
