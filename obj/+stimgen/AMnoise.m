classdef AMnoise < stimgen.Noise
    
    properties (SetObservable,AbortSet)
        AMDepth (1,1) double {mustBeGreaterThanOrEqual(AMDepth,0),mustBeLessThanOrEqual(AMDepth,1)} = 1; % [0 1] 
        AMRate  (1,1) double {mustBePositive,mustBeFinite} = 5; % Hz
        
        OnsetPhase (1,1) double = 180; % degrees
        
%         AMExponential (1,1) double
        
        EnvelopeOnly (1,1) logical = false;
        
        ApplyViemeisterCorrection (1,1) logical = true;
    end
    
    

    properties (Constant)
        %IsMultiObj      = false;
        %CalibrationType = "noise"; % defined in stimgen.Noise superclass
        %Normalization = "rms"; % defined in stimgen.Noise superclass
    end
    
    methods
                
        function obj = AMnoise(varargin)
            obj = obj@stimgen.Noise(varargin{:});

            obj.DisplayName = 'AM Noise';
            obj.UserProperties = ["SoundLevel","Duration","WindowDuration","ApplyWindow","HighPass","LowPass","AMDepth","AMRate","OnsetPhase","EnvelopeOnly","ApplyViemeisterCorrection"]; 
                        
            obj.Duration = 1;
        end
        
        
        function update_signal(obj)
            obj.temporarilyDisableSignalMods = true;
            
            update_signal@stimgen.Noise(obj);
            noise = obj.Signal;
            
            obj.temporarilyDisableSignalMods = false;
           
            
%             x(t) = A(t) sin(2 pi fc t)
%             A(t) = A [1 + m sin(2 pi fm t)]

            
            am = cos(2.*pi.*obj.AMRate.*obj.Time+deg2rad(obj.OnsetPhase));
            am = (am + 1)./2;
            am = am .* obj.AMDepth + 1 - obj.AMDepth;
            
            if obj.ApplyViemeisterCorrection
                am = am .* sqrt(1/(obj.AMDepth^2/2+1));
            end
            
            if obj.EnvelopeOnly
                obj.Signal = am;
            else
                obj.Signal = noise .* am;
            end
            
            obj.apply_gate;
            
            obj.apply_normalization;
            
            obj.apply_calibration;
        end
    
        function create_gui(obj,src,evnt)
            g = uigridlayout(src);
            g.ColumnWidth = {'1x','1x','1x'};
            g.RowHeight = repmat({25},1,8);
            
            R = 1;
            x = uilabel(g,'Text','AM Depth:');
            x.Layout.Column = 1;
            x.Layout.Row    = R;
            x.HorizontalAlignment = 'right';
            
            x = uieditfield(g,'numeric','Tag','AMDepth');
            x.Layout.Column = 2;
            x.Layout.Row = R;
            x.Limits = [0 1];
            x.ValueDisplayFormat = '%.2f';
            x.Value = obj.AMDepth;
            h.AMDepth = x;
            
            R = R + 1;
            
            x = uilabel(g,'Text','Onset Phase:');
            x.Layout.Column = 1;
            x.Layout.Row    = R;
            x.HorizontalAlignment = 'right';
            
            x = uieditfield(g,'numeric','Tag','OnsetPhase');
            x.Layout.Column = 2;
            x.Layout.Row = R;
            x.Limits = [-180 180];
            x.ValueDisplayFormat = '%.2f deg';
            x.Value = obj.OnsetPhase;
            h.OnsetPhase = x;
            
            R = R + 1;
            
            
            
            x = uilabel(g,'Text','HighPass Fc:');
            x.Layout.Column = 1;
            x.Layout.Row    = R;
            x.HorizontalAlignment = 'right';
            
            x = uieditfield(g,'numeric','Tag','HighPass');
            x.Layout.Column = 2;
            x.Layout.Row = R;
            x.Limits = [100 40000];
            x.ValueDisplayFormat = '%.1f Hz';
            x.Value = obj.HighPass;
            h.HighPass = x;
            
            R = R + 1;
            x = uilabel(g,'Text','LowPass Fc:');
            x.Layout.Column = 1;
            x.Layout.Row    = R;
            x.HorizontalAlignment = 'right';
            
            x = uieditfield(g,'numeric','Tag','LowPass');
            x.Layout.Column = 2;
            x.Layout.Row = R;
            x.Limits = [100 40000];
            x.ValueDisplayFormat = '%.1f Hz';
            x.Value = obj.LowPass;
            h.LowPass = x;
                        
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
            
%             R = R + 1;
%             
%             x = uilabel(g,'Text','Normalization:');
%             x.Layout.Column = 1;
%             x.Layout.Row    = R;
%             x.HorizontalAlignment = 'right';
%             
%             x = uidropdown(g,'Tag','Normalization');
%             x.Layout.Column = 2;
%             x.Layout.Row = R;
%             x.Items = ["none","absmax","rms","max","min"];
%             x.Value = obj.Normalization;
%             h.Normalization = x;
%             
%             
            
            
            structfun(@(a) set(a,'ValueChangedFcn',@obj.interpret_gui),h);
            
            obj.GUIHandles = h;
            
%             obj.create_handle_listeners;
        end
        
    end
    
end
