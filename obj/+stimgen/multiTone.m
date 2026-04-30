classdef multiTone < stimgen.StimType
    % obj = stimgen.multiTone(Name,Value,...)
    % Multi-tone stimulus generator (grid of frequency x level).
    %
    % This StimType builds a set of stimgen.Tone objects from the expression
    % strings Frequency_MO and SoundLevel_MO and concatenates their signals.
    properties (SetObservable)
        MultiObjects (1,:) stimgen.Tone = stimgen.Tone.empty

        OnsetPhase (1,1) double = 0

        WindowMethod  (1,1) string {mustBeMember(WindowMethod,["Duration" "Proportional" "#Periods"])} = "Duration"        

        
        Frequency_MO  (1,1) string = "500*2.^(0:6)";
        SoundLevel_MO (1,1) string = "10:10:70";
    end
    
    properties (Dependent)
        Frequency_  (1,:) double
        SoundLevel_ (1,:) double
    end

    properties (Constant)
        IsMultiObj      = true;
        CalibrationType = "tone";
        Normalization   = "absmax";
    end
    
    methods
        function obj = multiTone(varargin)
            obj = obj@stimgen.StimType(varargin{:});

            obj.DisplayName = 'Multi Tone';

            obj.UserProperties = ["Frequency_MO","SoundLevel_MO","Duration","OnsetPhase","WindowDuration","ApplyWindow","WindowMethod"];

        end


        function update_signal(obj)
            obj.update_tone_objs();

            if isempty(obj.MultiObjects)
                obj.Signal = [];
                return
            end

            % Concatenate signals from all tone objects
            sigs = cellfun(@(t) t.Signal(:),num2cell(obj.MultiObjects),'UniformOutput',false);
            obj.Signal = vertcat(sigs{:})';
            
        end

        
        function h = create_gui(obj,src,evnt)
            g = uigridlayout(src);
            g.ColumnWidth = {'1x','1x','1x'};
            g.RowHeight = repmat({25},1,8);
            
            R = 1;
            x = uilabel(g,'Text','Frequencies (Hz):');
            x.Layout.Column = 1;
            x.Layout.Row    = R;
            x.HorizontalAlignment = 'right';
            
            x = uieditfield(g,'Tag','Frequency_MO');
            x.Layout.Column = 2;
            x.Layout.Row = R;
            x.Value = obj.Frequency_MO;
            h.Frequency = x;
            
            
            R = R + 1;
            
            x = uilabel(g,'Text','Sound Levels (dB):');
            x.Layout.Column = 1;
            x.Layout.Row    = R;
            x.HorizontalAlignment = 'right';
            
            x = uieditfield(g,'Tag','SoundLevel_MO');
            x.Layout.Column = 2;
            x.Layout.Row = R;
            x.Value = obj.SoundLevel_MO;
            h.SoundLevel = x;


            R = R + 1;
            
            x = uilabel(g,'Text','Duration (s):');
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
            
            x = uilabel(g,'Text','Onset Phase (deg):');
            x.Layout.Column = 1;
            x.Layout.Row    = R;
            x.HorizontalAlignment = 'right';
            
            x = uieditfield(g,'numeric','Tag','OnsetPhase');
            x.Layout.Column = 2;
            x.Layout.Row = R;
            x.Value = obj.OnsetPhase;
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
            x.Value = "Duration";
            h.WindowDurationMethod = x;
            
            
            structfun(@(a) set(a,'ValueChangedFcn',@obj.interpret_gui),h);
            
            obj.GUIHandles = h;
            
%             obj.create_handle_listeners;
        end


        function f = get.Frequency_(obj)
            f = eval(obj.Frequency_MO);
        end

        function s = get.SoundLevel_(obj)
            s = eval(obj.SoundLevel_MO);
        end
        
    end

    
    
    methods (Access = protected)
        function update_tone_objs(obj)
            f = obj.Frequency_;
            s = obj.SoundLevel_;

            nTones = numel(f)*numel(s);
            obj.MultiObjects = repmat(stimgen.Tone(),1,nTones);

            for i = 1:nTones
                fi = mod(i-1,numel(f))+1;
                si = mod(floor((i-1)/numel(f)),numel(s))+1;

                obj.MultiObjects(i) = stimgen.Tone(); % create a new handle for each object
                obj.MultiObjects(i).Calibration = obj.Calibration;
                obj.MultiObjects(i).Frequency = f(fi);
                obj.MultiObjects(i).SoundLevel = s(si);
            end

            % arrayfun(@update_signal,obj.MultiObjects);

        end
    end

    methods (Access = protected)
        function m = propMeta(obj)
            % propMeta() - Display metadata for multiTone GUI properties.
            m = struct();
            m.Frequency_MO  = struct('label', 'Frequencies (Hz)',  'widget', 'text');
            m.SoundLevel_MO = struct('label', 'Sound Levels (dB)', 'widget', 'text');
            m.OnsetPhase    = struct('label', 'Onset Phase',        'format', '%.1f deg');
            m.WindowMethod  = struct('label', 'Window Method', 'widget', 'dropdown', ...
                                    'items', ["Duration" "Proportional" "#Periods"]);
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