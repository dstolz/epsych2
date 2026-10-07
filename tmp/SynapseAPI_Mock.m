classdef SynapseAPI_Mock < handle
% SynapseAPI_Mock - In-process stand-in for TDT's SynapseAPI client, for hw.TDT_Synapse.
%
% Answers the methods hw.TDT_Synapse calls with the shapes the real client
% returns (TDTfun/SynapseAPI/SynapseAPI.m and the SynapseAPI manual),
% including the behaviours that only show against a processor in LEGACY
% mode and that the lab's 2018-2021 integration met on the rig:
%   - the legacy processor is listed by getGizmoNames under its own name
%     ('RZ6(1)'), with category 'Legacy', and getGizmoParent answers 0 for
%     it: it has no parent, it IS the processor;
%   - getParameterInfo reports Type as 'Float', 'Int' or 'Logic', Access as
%     a word, and Array as 'No'/'Yes' while Synapse is Idle (design time)
%     but as the element count in any runtime mode;
%   - getParameterInfo answers a struct with no fields for a tag Synapse
%     lists but will not describe;
%   - parameter reads answer '' and writes 0 while Idle, since Synapse
%     refuses parameter access outside a runtime mode;
%   - setMode(1) is refused -- returns 0, mode unchanged -- when
%     StandbyEnabled is false, as Synapse does until Standby Mode is
%     enabled under Menu > Preferences.
%
% Mirrors tmp/Bpod_Mock and tmp/Teensy_Mock in intent: the backend under
% test is the real class, through tmp/TDT_Synapse_Mock, which swaps in
% this object at the one seam where a client is constructed.
%
% Usage
%   api = SynapseAPI_Mock();                  % the default legacy experiment
%   I = TDT_Synapse_Mock(api, Connect=true);
%   api.lastCall('setParameterValues')        % args of the latest such call
%   api.value('RZ6(1)', 'Freq')               % what the "device" holds
%
% Properties
%   Mode           - 0 Idle, 1 Standby, 2 Preview, 3 Record.
%   StandbyEnabled - Whether setMode(1) succeeds.
%   Gizmos         - Experiment: struct array (Name, Category, GizmoType,
%                    Parent, Parameters), Parameters a struct array (Name,
%                    Unit, Min, Max, Access, Type, Size, Value, Describable).
%   Rates          - getSamplingRates answer, keyed by cleaned processor name.
%   Log            - Every state-changing or value-reading call, in order,
%                    each a cell {method, arg1, arg2, ...}.
%
% See also: TDT_Synapse_Mock, hw.TDT_Synapse, tmp/smoke_test_synapse_legacy.m

    properties
        Mode (1,1) double = 0
        StandbyEnabled (1,1) logical = true
        Gizmos (1,:) struct
        Rates (1,1) struct
        Info (1,1) struct
        Log (1,:) cell = {}

        % Number of getMode polls a requested mode takes to arrive. 0 is
        % immediate. Above 0, setMode answers 0 at once -- the 503 "Could
        % not process request in time" the rig gave for Preview -> Idle --
        % while the change goes on behind it.
        SlowTransitions (1,1) double = 0

        % Parameter names whose scalar read throws, as a dropped connection
        % would mid-trial.
        ReadErrors (1,:) cell = {}
    end

    properties (Access = private)
        PendingMode_ (1,1) double = 0
        PendingPolls_ (1,1) double = 0
    end

    properties (Constant)
        MODES = {'Idle', 'Standby', 'Preview', 'Record'}
    end

    methods
        function obj = SynapseAPI_Mock(options)
            arguments
                options.Experiment (1,:) struct = SynapseAPI_Mock.legacyExperiment()
                options.Rates (1,1) struct = struct('RZ6_1', 48828.125, 'RZ2_1', 24414.0625)
            end
            obj.Gizmos = options.Experiment;
            obj.Rates = options.Rates;
            obj.Info = struct('user', 'tester', 'subject', 'M1', ...
                'experiment', 'LegacyDetect', 'tank', 'C:\Tanks\LegacyDetect', 'block', 'M1-260101');
        end

        % ---- mode -------------------------------------------------------
        function iMode = getMode(obj)
            if obj.PendingPolls_ > 0
                obj.PendingPolls_ = obj.PendingPolls_ - 1;
                if obj.PendingPolls_ == 0
                    obj.Mode = obj.PendingMode_;
                end
            end
            iMode = obj.Mode;
        end

        function sMode = getModeStr(obj)
            sMode = obj.MODES{obj.getMode() + 1};
        end

        function bSuccess = setMode(obj, iNewMode)
            if ~any(iNewMode == 0:3)
                error('Invalid input to setMode, must be integer between 0 and 3');
            end
            obj.Log{end+1} = {'setMode', iNewMode};
            if iNewMode == 1 && ~obj.StandbyEnabled
                bSuccess = 0;
                return
            end
            if obj.SlowTransitions > 0 && iNewMode ~= obj.Mode
                obj.PendingMode_ = iNewMode;
                obj.PendingPolls_ = obj.SlowTransitions;
                bSuccess = 0;
                return
            end
            obj.Mode = iNewMode;
            bSuccess = 1;
        end

        function settle(obj)
            % settle(obj)
            % Abandon a pending transition, for a test that timed one out.
            obj.PendingPolls_ = 0;
            obj.SlowTransitions = 0;
        end

        function bSuccess = setModeStr(obj, sNewMode)
            idx = find(strcmp(obj.MODES, sNewMode), 1);
            if isempty(idx)
                error('Allowed modes are: ''Idle'', ''Standby'', ''Preview'', or ''Record''')
            end
            bSuccess = obj.setMode(idx - 1);
        end

        % ---- gizmos -----------------------------------------------------
        function cGizmos = getGizmoNames(obj, varargin)
            apiOnly = numel(varargin) > 0 && logical(varargin{1});
            cGizmos = {obj.Gizmos.Name};
            if apiOnly
                cGizmos = cGizmos(arrayfun(@(g) ~isempty(g.Parameters), obj.Gizmos));
            end
            if isempty(cGizmos)
                cGizmos = [];
            end
        end

        function tGizmoInfo = getGizmoInfo(obj, sGizmoName)
            gi = obj.gizmoIndex_(sGizmoName);
            if isempty(gi)
                tGizmoInfo = 0;
                return
            end
            g = obj.Gizmos(gi);
            tGizmoInfo = struct('type', g.GizmoType, 'desc', '', 'cat', g.Category, 'icon', '');
        end

        function sGizmoParent = getGizmoParent(obj, sGizmoName)
            gi = obj.gizmoIndex_(sGizmoName);
            if isempty(gi) || isempty(obj.Gizmos(gi).Parent)
                % What the rig did for the legacy RZ6: a 404 the client
                % turns into a warning with a stack, and an empty answer.
                warning('Error from Synapse:  404 Not found')
                sGizmoParent = '';
                return
            end
            sGizmoParent = SynapseAPI_Mock.cleanField(obj.Gizmos(gi).Parent);
        end

        function tSamplingRates = getSamplingRates(obj)
            tSamplingRates = obj.Rates;
        end

        % ---- parameters -------------------------------------------------
        function cParameters = getParameterNames(obj, sGizmo)
            gi = obj.gizmoIndex_(sGizmo);
            cParameters = [];
            if isempty(gi) || isempty(obj.Gizmos(gi).Parameters)
                return
            end
            cParameters = {obj.Gizmos(gi).Parameters.Name};
        end

        function tParameterInfo = getParameterInfo(obj, sGizmo, sParameter)
            tParameterInfo = struct();
            [gi, pi] = obj.parameterIndex_(sGizmo, sParameter);
            if isempty(pi)
                return
            end
            p = obj.Gizmos(gi).Parameters(pi);
            if ~p.Describable
                return
            end
            if p.Size > 1
                if obj.Mode == 0
                    arrayField = 'Yes';
                else
                    arrayField = p.Size;
                end
            else
                arrayField = 'No';
            end
            tParameterInfo = struct('Name', p.Name, 'Unit', p.Unit, 'Min', p.Min, 'Max', p.Max, ...
                'Access', p.Access, 'Type', p.Type, 'Array', arrayField);
        end

        function dValue = getParameterSize(obj, sGizmo, sParameter)
            [gi, pi] = obj.parameterIndex_(sGizmo, sParameter);
            if isempty(pi)
                dValue = 0;
                return
            end
            dValue = obj.Gizmos(gi).Parameters(pi).Size;
        end

        function dValue = getParameterValue(obj, sGizmo, sParameter)
            obj.Log{end+1} = {'getParameterValue', sGizmo, sParameter};
            if any(strcmp(obj.ReadErrors, sParameter))
                error('SynapseAPI_Mock:ReadError', 'Connection reset while reading %s.%s', sGizmo, sParameter);
            end
            [gi, pi] = obj.parameterIndex_(sGizmo, sParameter);
            if isempty(pi) || obj.Mode == 0
                dValue = '';
                return
            end
            v = obj.Gizmos(gi).Parameters(pi).Value;
            dValue = double(v(1));
        end

        function fValues = getParameterValues(obj, sGizmo, sParameter, varargin)
            obj.Log{end+1} = [{'getParameterValues', sGizmo, sParameter}, varargin];
            if isempty(varargin)
                % The client's own size cache: a struct keyed 'Gizmo_Param'.
                % For a legacy processor that key is 'RZ6(2)_Stim', not a
                % field name, and the real client throws exactly this.
                lookup = [sGizmo '_' sParameter];
                if ~isvarname(lookup)
                    error('MATLAB:AddField:InvalidFieldName', 'Invalid field name: ''%s''.', lookup);
                end
            end
            [gi, pi] = obj.parameterIndex_(sGizmo, sParameter);
            if isempty(pi) || obj.Mode == 0
                fValues = '';
                return
            end
            fValues = double(reshape(obj.Gizmos(gi).Parameters(pi).Value, 1, []));
            if ~isempty(varargin)
                fValues = fValues(1:min(double(varargin{1}), numel(fValues)));
            end
        end

        function bSuccess = setParameterValue(obj, sGizmo, sParameter, dValue)
            if numel(dValue) > 1 && ~ischar(dValue)
                bSuccess = obj.setParameterValues(sGizmo, sParameter, dValue);
                return
            end
            obj.Log{end+1} = {'setParameterValue', sGizmo, sParameter, dValue};
            [gi, pi] = obj.parameterIndex_(sGizmo, sParameter);
            if isempty(pi) || obj.Mode == 0
                bSuccess = 0;
                return
            end
            obj.Gizmos(gi).Parameters(pi).Value = double(dValue);
            bSuccess = 1;
        end

        function bSuccess = setParameterValues(obj, sGizmo, sParameter, fValues, varargin)
            % Lands at offset in a buffer whose size the circuit fixed, as
            % the device would; the rest of the buffer keeps what it held.
            obj.Log{end+1} = [{'setParameterValues', sGizmo, sParameter, fValues}, varargin];
            offset = 0;
            if numel(varargin) > 0
                offset = double(varargin{1});
            end
            [gi, pi] = obj.parameterIndex_(sGizmo, sParameter);
            if isempty(pi) || obj.Mode == 0
                bSuccess = 0;
                return
            end
            buffer = obj.Gizmos(gi).Parameters(pi).Value;
            n = numel(fValues);
            if offset + n > numel(buffer)
                bSuccess = 0;
                return
            end
            buffer(offset + (1:n)) = double(reshape(fValues, 1, []));
            obj.Gizmos(gi).Parameters(pi).Value = buffer;
            bSuccess = 1;
        end

        % ---- session info -----------------------------------------------
        function s = getCurrentUser(obj),       s = obj.Info.user;       end
        function s = getCurrentSubject(obj),    s = obj.Info.subject;    end
        function s = getCurrentExperiment(obj), s = obj.Info.experiment; end
        function s = getCurrentTank(obj),       s = obj.Info.tank;       end
        function s = getCurrentBlock(obj)
            % A block exists only in Preview and Record; asking earlier is
            % a 404 plus the client's "not in a run-time mode" warning.
            if obj.Mode < 2
                warning('Error from Synapse:  404 Not found')
                s = '';
                return
            end
            s = obj.Info.block;
        end

        % ---- test helpers -----------------------------------------------
        function args = lastCall(obj, method)
            % args = lastCall(obj, method)
            % Arguments of the most recent call to method, {} if none.
            args = {};
            for k = numel(obj.Log):-1:1
                if strcmp(obj.Log{k}{1}, method)
                    args = obj.Log{k}(2:end);
                    return
                end
            end
        end

        function n = callCount(obj, method)
            n = sum(cellfun(@(c) strcmp(c{1}, method), obj.Log));
        end

        function v = value(obj, sGizmo, sParameter)
            % v = value(obj, gizmo, parameter)
            % What the simulated device holds, whatever the mode.
            [gi, pi] = obj.parameterIndex_(sGizmo, sParameter);
            if isempty(pi)
                error('SynapseAPI_Mock:NoSuchParameter', ...
                    'The mock experiment has no parameter %s.%s.', sGizmo, sParameter);
            end
            v = obj.Gizmos(gi).Parameters(pi).Value;
        end

        function clearLog(obj)
            obj.Log = {};
        end
    end

    methods (Access = private)
        function gi = gizmoIndex_(obj, name)
            gi = find(strcmp({obj.Gizmos.Name}, name), 1);
        end

        function [gi, pi] = parameterIndex_(obj, gizmo, param)
            pi = [];
            gi = obj.gizmoIndex_(gizmo);
            if isempty(gi) || isempty(obj.Gizmos(gi).Parameters)
                return
            end
            pi = find(strcmp({obj.Gizmos(gi).Parameters.Name}, param), 1);
        end
    end

    methods (Static)
        function g = legacyExperiment()
            % g = SynapseAPI_Mock.legacyExperiment()
            % One RZ6 in legacy mode running a detection circuit, beside an
            % RZ2 with ordinary gizmos: a PulseGen with an API parameter and
            % a Neu1 with none. The legacy tags are spelled as the lab's
            % circuits spell them for the runtime (x_NewTrial_1 and its
            % kin), with the Access string and the +/-1e20 bounds a live
            % Synapse reported for every legacy tag on 2026-10-07.
            rz6 = [ ...
                SynapseAPI_Mock.param('Freq',    'Float', 'Read / Write', Unit='Hz', Min=100, Max=20000, Value=1000), ...
                SynapseAPI_Mock.param('NTrials', 'Int',   'Read / Write', Min=-1e20, Max=1e20, Value=0), ...
                SynapseAPI_Mock.param('Resp',    'Logic', 'Read',  Value=0), ...
                SynapseAPI_Mock.param('~BoxID',  'Int',   'Read',  Value=1), ...
                SynapseAPI_Mock.param('!Trig',   'Logic', 'Write', Describable=false), ...
                SynapseAPI_Mock.param('Stim',    'Float', 'Read / Write', Min=-1e20, Max=1e20, Size=100000), ...
                SynapseAPI_Mock.param('StimSmall','Float','Read / Write', Size=100), ...
                SynapseAPI_Mock.param('x_NewTrial_1',     'Float', 'Read / Write', Min=-1e20, Max=1e20), ...
                SynapseAPI_Mock.param('x_ResetTrig_1',    'Float', 'Read / Write', Min=-1e20, Max=1e20), ...
                SynapseAPI_Mock.param('x_TrialComplete_1','Float', 'Read / Write', Min=-1e20, Max=1e20), ...
                SynapseAPI_Mock.param('x_TrialNum_1',     'Float', 'Read / Write', Min=-1e20, Max=1e20), ...
                SynapseAPI_Mock.param('_RespCode_1',      'Float', 'Read / Write', Min=-1e20, Max=1e20), ...
                SynapseAPI_Mock.param('%junk',   'Float'), ...
                SynapseAPI_Mock.param('#Hidden', 'Float'), ...
                SynapseAPI_Mock.param('sRCod/',  'Float'), ...
                SynapseAPI_Mock.param('%rPvDsHElpEr77638', 'Float')];

            g = [ ...
                SynapseAPI_Mock.gizmo('RZ6(1)',    'Legacy',            'Legacy',   '',       rz6), ...
                SynapseAPI_Mock.gizmo('RZ2(1)',    'Hardware Access',   'RZ2',      '',       SynapseAPI_Mock.param()), ...
                SynapseAPI_Mock.gizmo('PulseGen1', 'Signal Generators', 'PulseGen', 'RZ2(1)', ...
                    SynapseAPI_Mock.param('PulseFreq', 'Float', 'Read / Write', Unit='Hz', Min=0, Max=5000, Value=10)), ...
                SynapseAPI_Mock.gizmo('Neu1',      'Neural',            'Neu',      'RZ2(1)', SynapseAPI_Mock.param())];
        end

        function g = gizmo(name, category, gizmoType, parent, parameters)
            g = struct('Name', name, 'Category', category, 'GizmoType', gizmoType, ...
                'Parent', parent, 'Parameters', parameters);
        end

        function p = param(name, type, access, options)
            % p = SynapseAPI_Mock.param(name, type, access, Name=Value)
            % p = SynapseAPI_Mock.param()           % the empty parameter list
            arguments
                name (1,:) char = ''
                type (1,:) char = 'Float'
                access (1,:) char = 'Read / Write'
                options.Unit (1,:) char = ''
                options.Min (1,1) double = nan
                options.Max (1,1) double = nan
                options.Size (1,1) double = 1
                options.Value double = []
                options.Describable (1,1) logical = true
            end
            p = struct('Name', {}, 'Unit', {}, 'Min', {}, 'Max', {}, 'Access', {}, ...
                'Type', {}, 'Size', {}, 'Value', {}, 'Describable', {});
            if isempty(name)
                return
            end
            v = options.Value;
            if isempty(v)
                v = zeros(1, options.Size);
            end
            p(1) = struct('Name', name, 'Unit', options.Unit, 'Min', options.Min, 'Max', options.Max, ...
                'Access', access, 'Type', type, 'Size', options.Size, 'Value', v, ...
                'Describable', options.Describable);
        end

        function s = cleanField(name)
            % 'RZ6(1)' -> 'RZ6_1', as SynapseAPI.cleanField does.
            s = regexprep(name, '[()]', '_');
            s = regexprep(s, '_$', '');
        end
    end
end
