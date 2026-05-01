classdef Tone < stimgen.StimType

    % obj = stimgen.Tone(Name,Value,...)
    % Pure-tone stimulus generator.
    %
    % Generates a sine tone at Frequency for Duration seconds, optionally
    % windowed/gated and calibrated.
    
    properties (SetObservable,AbortSet)
        Frequency  (1,1) double {mustBePositive,mustBeFinite} = 1000; % Hz
        OnsetPhase (1,1) double = 0;
        
        WindowMethod  (1,1) string {mustBeMember(WindowMethod,["Duration" "Proportional" "#Periods"])} = "Duration"
    end

    
    
    properties (Constant)
        IsMultiObj      = false;
        CalibrationType = "tone";
        Normalization   = "absmax";
    end
    
    methods
        function obj = Tone(varargin)
            obj = obj@stimgen.StimType(varargin{:});

            obj.DisplayName = 'Tone';

            obj.UserProperties = ["Frequency","SoundLevel","Duration","WindowDuration","ApplyWindow","OnsetPhase","WindowMethod"];
        end
        
        function update_signal(obj)
            t = obj.Time;
            
            obj.Signal = sin(2.*pi.*obj.Frequency.*t+obj.OnsetPhase);
            
            
            switch obj.WindowMethod
                case 'Duration'
                    % no conversion needed
                case 'Proportional'
                    obj.WindowDuration = obj.WindowDuration/100*t(end);
                case '#Periods'
                    obj.WindowDuration = 2*obj.WindowDuration/obj.Frequency;
            end
            
            
            obj.apply_normalization;
            
            obj.apply_calibration;
            
            obj.apply_gate;
        end
        
    end

    methods (Access = protected)
        function m = propMeta(obj)
            % propMeta() - Display metadata for Tone GUI properties.
            m = struct();
            m.Frequency    = struct('label', 'Frequency',     'format', '%.1f Hz',  'limits', [100 40000]);
            m.OnsetPhase   = struct('label', 'Onset Phase',   'format', '%.1f deg');
            m.WindowMethod = struct('label', 'Window Method', 'widget', 'dropdown', 'items', ["Duration" "Proportional" "#Periods"]);
            m = stimgen.StimType.merge_prop_meta(m, propMeta@stimgen.StimType(obj));
        end

        function on_gui_changed(obj, propName, ~)
            % Update WindowDuration format label when WindowMethod changes.
            if strcmp(propName, 'WindowMethod')
                switch obj.WindowMethod
                    case 'Proportional', fmt = '%.2f%%';
                    case 'Duration',     fmt = '%.4f s';
                    case '#Periods',     fmt = '%.1f periods';
                end
                if isfield(obj.GUIHandles, 'WindowDuration') && isvalid(obj.GUIHandles.WindowDuration)
                    obj.GUIHandles.WindowDuration.ValueDisplayFormat = fmt;
                end
            end
        end
    end
end