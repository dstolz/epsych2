classdef Tone < stimgen.StimType
    
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
            
            
            obj.apply_gate;
            
            obj.apply_normalization;
            
            obj.apply_calibration;
        end
        
        function h = create_gui(obj,src,evnt)
            g = uigridlayout(src);
            g.ColumnWidth = {'1x','1x','1x'};
            g.RowHeight = repmat({25},1,8);
            
            R = 1;
            x = uilabel(g,'Text','Frequency:');
            x.Layout.Column = 1;
            x.Layout.Row    = R;
            x.HorizontalAlignment = 'right';
            
            x = uieditfield(g,'numeric','Tag','Frequency');
            x.Layout.Column = 2;
            x.Layout.Row = R;
            x.Limits = [100 40000];
            x.ValueDisplayFormat = '%.1f Hz';
            x.Value = obj.Frequency;
            h.Frequency = x;
            
            R = R + 1;
            
            x = uilabel(g,'Text','Sound Level:');
            x.Layout.Column = 1;
            x.Layout.Row    = R;
            x.HorizontalAlignment = 'right';
            
            x = uieditfield(g,'Numeric','Tag','SoundLevel');
            x.Layout.Column = 2;
            x.Layout.Row = R;
            x.Value = obj.SoundLevel;
            h.SoundLevel = x;
            
            
            R = R + 1;
            
            x = uilabel(g,'Text','Duration:');
            x.Layout.Column = 1;
            x.Layout.Row    = R;
            x.HorizontalAlignment = 'right';
            
            x = uieditfield(g,'numeric','Tag','Duration');
            x.Layout.Column = 2;
            x.Layout.Row = R;
            x.Limits = [0.001 10];
            x.ValueDisplayFormat = '%.3f s';
            x.Value = obj.Duration;
            h.Duration = x;
                        
            R = R + 1;
            
            x = uilabel(g,'Text','Window Duration:');
            x.Layout.Column = 1;
            x.Layout.Row    = R;
            x.HorizontalAlignment = 'right';
            
            x = uieditfield(g,'numeric','Tag','WindowDuration');
            x.Layout.Column = 2;
            x.Layout.Row = R;
            x.Limits = [1e-6 10];
            x.ValueDisplayFormat = '%.4f s';
            x.Value = obj.WindowDuration;
            h.WindowDuration = x;
            
            x = uidropdown(g,'Tag','WindowMethod');
            x.Layout.Column = 3;
            x.Layout.Row = R;
            x.Items = ["Duration" "Proportional" "#Periods"];
            x.Value = obj.WindowMethod;
            h.WindowDurationMethod = x;
            
            structfun(@(a) set(a,'ValueChangedFcn',@obj.interpret_gui),h);
            
            obj.GUIHandles = h;
            
%             obj.create_handle_listeners;
        end
        
    end
    
    methods (Access = protected)
        function interpret_gui(obj,src,event)
            try
                obj.(src.Tag) = event.Value;
            catch
                obj.(src.Tag) = event.PreviousValue;
            end
            
            if isequal(src.Tag,'WindowMethod')
                switch src.Value
                    case 'Proportional'
                        fmt = '%.2f%%';
                    case 'Duration'
                        fmt = '%.4f s';
                    case '#Periods'
                        fmt = '%.1f periods';
                end
                obj.GUIHandles.WindowDuration.ValueDisplayFormat = fmt;
            end
        end
        
    end
end