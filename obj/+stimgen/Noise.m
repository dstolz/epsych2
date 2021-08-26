classdef Noise < stimgen.StimType
    
    properties (SetObservable,AbortSet)
        HighPass  (1,1) double {mustBeNonnegative,mustBeFinite} = 500; % Hz
        LowPass   (1,1) double {mustBeNonnegative,mustBeFinite} = 20000; % Hz
        
        FilterOrder (1,1) double {mustBePositive,mustBeInteger,mustBeFinite} = 40;
        digFilter % designfilt object
    end
   
    
    methods
                
        function obj = Noise(varargin)
            obj = obj@stimgen.StimType(varargin{:});
        end
        
        function set.HighPass(obj,fc)
            obj.HighPass = fc;
            obj.update_digFilter;
        end
        
        function set.LowPass(obj,fc)
            obj.LowPass = fc;
            obj.update_digFilter;
        end
        
        function set.FilterOrder(obj,fo)
            obj.FilterOrder = fo;
            obj.update_digFilter;
        end
        
        function set.digFilter(obj,d)
            assert(isa(d,'digitalFilter'),'Must use a designfilt object')            
            obj.digFilter = d;
        end
        
        function d = get.digFilter(obj)
            if isempty(obj.digFilter) || ~isvalid(obj.digFilter)
                obj.update_digFilter;
            end
            d = obj.digFilter;
        end
        
        function update_signal(obj)
            t = obj.Time;

            y = randn(length(t),1);
            
            y = filter(obj.digFilter,y);
            
            obj.Signal = y';
            
            obj.apply_gate;
            
            obj.apply_normalization;
        end
    
        function update_digFilter(obj)
            obj.digFilter = designfilt('bandpassfir', ...
                    'FilterOrder',obj.FilterOrder, ...
                    'CutoffFrequency1',obj.HighPass, ...
                    'CutoffFrequency2',obj.LowPass, ...
                    'SampleRate',obj.Fs);
        end
        
        
        
        function create_gui(obj,src,evnt)
            g = uigridlayout(src);
            g.ColumnWidth = {'1x','1x','1x'};
            g.RowHeight = repmat({25},1,8);
            
            R = 1;
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
            
            x = uilabel(g,'Text','Gate Duration:');
            x.Layout.Column = 1;
            x.Layout.Row    = R;
            x.HorizontalAlignment = 'right';
            
            x = uieditfield(g,'numeric','Tag','GateDuration');
            x.Layout.Column = 2;
            x.Layout.Row = R;
            x.Limits = [1e-6 10];
            x.ValueDisplayFormat = '%.4f s';
            x.Value = obj.GateDuration;
            h.GateDuration = x;
            
            structfun(@(a) set(a,'ValueChangedFcn',@obj.interpret_gui),h);
            
            obj.GUIHandles = h;
        end
        
        
        function interpret_gui(obj,src,evnt)
            try
                obj.(src.Tag) = event.Value;
            catch
                obj.(src.Tag) = event.PreviousValue;
            end
        end
    end
    
end
