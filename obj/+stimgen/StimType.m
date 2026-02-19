classdef (Hidden) StimType < handle & matlab.mixin.Heterogeneous & matlab.mixin.Copyable & matlab.mixin.SetGet

    properties
        Calibration     (1,1) stimgen.StimCalibration
        UserProperties  (1,:) string = string.empty
        DisplayName   (1,1) string = "undefined";
    end

    properties (SetObservable,AbortSet)
        SoundLevel     (1,1) double {mustBeFinite} = 60; % dB SPL if calibrated
        Duration       (1,1) double {mustBePositive,mustBeFinite} = 0.1;  % seconds

        WindowDuration (1,1) double {mustBeNonnegative,mustBeFinite} = 0.002; % seconds
        WindowFcn      (1,1) string = "cos2";

        ApplyCalibration (1,1) logical = true;
        ApplyWindow      (1,1) logical = true;

        Fs             (1,1) double {mustBePositive,mustBeFinite} = 97656.25; % Hz
    end


    properties (SetAccess = protected, SetObservable)
        Signal       (1,:) = [];
    end

    properties (Dependent)
        N
        Time
        Window
        StrProps
    end


    properties (Hidden,Access = protected)
        temporarilyDisableSignalMods (1,1) logical = false;
        els
        GUIHandles
        calibrationWarningIssued (1,1) logical = false;
        plotLineHandle matlab.graphics.chart.primitive.Line = matlab.graphics.chart.primitive.Line.empty
        plotAxHandle   matlab.graphics.axis.Axes = matlab.graphics.axis.Axes.empty
    end


    properties (Abstract, Constant)
        IsMultiObj      (1,1) logical
        CalibrationType (1,1) string % "noise","tone","click"
        Normalization   (1,1) string {mustBeMember(Normalization,["absmax","max","min","rms"])} 
    end

    methods (Abstract)
        update_signal(obj); % implemented in subclasses
        h = create_gui(obj,src,evnt);
    end

    methods

        function obj = StimType(varargin)
            % does no property name case matching
            for i = 1:2:length(varargin)
                if isfield(obj,varargin{i})
                    obj.(varargin{i}) = varargin{i+1};
                end
            end

            obj.create_listeners;
        end

        function S = toStruct(obj)
            %TOSTRUCT  Serialize StimType object to a struct.

            % Basic class metadata
            S = struct;
            S.Class        = string(class(obj));
            S.DisplayName  = obj.DisplayName;

            % Core StimType properties
            S.SoundLevel       = obj.SoundLevel;
            S.Duration         = obj.Duration;
            S.WindowDuration   = obj.WindowDuration;
            S.WindowFcn        = obj.WindowFcn;
            S.ApplyCalibration = obj.ApplyCalibration;
            S.ApplyWindow      = obj.ApplyWindow;
            S.Fs               = obj.Fs;

            % Abstract/constant properties (same across instances of subclass)
            S.CalibrationType  = obj.CalibrationType;
            S.Normalization    = obj.Normalization;
            S.IsMultiObj       = obj.IsMultiObj;

            % Calibration
            S.Calibration = obj.Calibration.toStruct;


            % User-defined property list and values
            S.UserProperties = obj.UserProperties;
            for k = 1:numel(obj.UserProperties)
                pname = obj.UserProperties(k);
                if isprop(obj,pname)
                    S.(pname) = obj.(pname);
                end
            end

            % Do NOT store Signal, GUIHandles, listeners, etc. here
        end

        function set.Calibration(obj,calObj)
            obj.Calibration = calObj;
            if obj.IsMultiObj
                arrayfun(@(x) set(x,'Calibration',calObj), obj.MultiObjects);
            end
        end

        function s = get.StrProps(obj)
            pr = obj.UserProperties;
            s = string();
            for i = 1:length(pr)
                s = s+pr(i)+": "+string(obj.(pr(i))) + "; ";
            end
        end

        function t = get.Time(obj)
            t = linspace(0,obj.Duration-1./obj.Fs,obj.N);
        end

        function n = get.N(obj)
            n = round(obj.Fs*obj.Duration);
        end


        function g = get.Window(obj)
            n = round(obj.WindowDuration.*obj.Fs);
            n = n + rem(n,2);

            switch obj.WindowFcn
                case ""
                    g = ones(1,n);
                case "cos2"
                    g = hann(n);
                otherwise
                    g = feval(obj.WindowFcn,n);
            end
            g = g(:)'; % conform to row vector
        end

        function h = plot(obj,ax)
            % PLOT  Plot current Signal vs Time.
            %   If a valid plot already exists, its data are updated instead
            %   of creating a new line.
            if nargin < 2 || isempty(ax)
                if ~isempty(obj.plotAxHandle) && isvalid(obj.plotAxHandle)
                    ax = obj.plotAxHandle;
                else
                    ax = gca;
                end
            end

            if isempty(obj.Signal)
                obj.update_signal; % subclass implementation
            end

            if ~isempty(obj.plotLineHandle) && isvalid(obj.plotLineHandle) && ...
                    isvalid(obj.plotAxHandle) && obj.plotAxHandle == ax
                set(obj.plotLineHandle,'XData',obj.Time,'YData',obj.Signal);
                h = obj.plotLineHandle;
            else
                h = plot(ax,obj.Time,obj.Signal);
                obj.plotLineHandle = h;
                obj.plotAxHandle   = ax;
            end
            grid(ax,'on');
            xlabel(ax,'time (s)');
        end

        function play(obj)
            ap = audioplayer(obj.Signal./max(abs(obj.Signal)),obj.Fs);
            playblocking(ap);
            delete(ap);
        end
    end % methods (Access = public)

    methods (Access = protected)

        function apply_gate(obj)
            if ~obj.ApplyWindow || obj.temporarilyDisableSignalMods, return; end

            g = obj.Window;

            n = length(g);
            ga = g(1:n/2);
            gb = g(n/2+1:end);

            obj.Signal(1:n/2) = obj.Signal(1:n/2) .* ga;
            obj.Signal(end-n/2+1:end) = obj.Signal(end-n/2+1:end) .* gb;
        end


        function apply_calibration(obj)
            %APPLY_CALIBRATION  Apply either scalar (LUT) calibration or filter+gain calibration.

            if ~obj.ApplyCalibration || obj.temporarilyDisableSignalMods
                return
            end

            C = obj.Calibration;

            if ~isa(C,'stimgen.StimCalibration') || isempty(C.CalibrationData)
                if obj.calibrationWarningIssued
                    vprintf(2,1,'No calibration data available for stim');
                else
                    vprintf(0,1,'No calibration data available for stim');
                    obj.calibrationWarningIssued = true;
                end
                return
            end

            type  = obj.CalibrationType;
            level = obj.SoundLevel;

            % Resolve LUT "value" where relevant
            switch type
                case "tone"
                    value = obj.Frequency;
                case "click"
                    value = obj.ClickDuration;
                otherwise
                    value = NaN;
            end

            % --- Filter-based calibration: equalize spectrum + apply level gain ---
            if type == "filter" && isfield(C.CalibrationData,'filter')

                Hd = C.CalibrationData.filter;

                % Robust group-delay compensation (pre/post pad avoids start-up transient)
                gd = round(C.CalibrationData.filterGrpDelay);
                
                if gd > 0
                    xpad = [zeros(1,gd) obj.Signal zeros(1,gd)];
                    ypad = filter(Hd,xpad);
                    y = ypad(gd+1:gd+numel(obj.Signal));
                else
                    y = filter(Hd,obj.Signal);
                end
            end

            switch obj.Normalization
                case "absmax"
                    y = y ./ max(abs(y));
                case "max"
                    y = y ./ max(y);
                case "min"
                    y = y ./ min(y);
                case "rms"
                    y = y ./ sqrt(mean(y.^2));
            end


            % Apply level (scalar) calibration for the filtered waveform
            v = C.compute_adjusted_voltage(type,value,level);



            if v > 10
                warning('stimgen:StimType:apply_calibration:OutOfRange', ...
                    'Calculated voltage value > 10 V')
            end

            obj.Signal = v .* y;

        end


        function create_listeners(obj)
            m = metaclass(obj);
            p = m.PropertyList;
            ind = [p.SetObservable] & string({p.SetAccess}) == "public";
            p(~ind) = [];

            for i = 1:length(p)
                e(i) = addlistener(obj,p(i).Name,'PostSet',@obj.onPropertyChanged);
            end
            obj.els = e;
        end

        function onPropertyChanged(obj,~,~)
            % Listener callback: update signal and refresh plot if it exists.
            obj.update_signal; % subclass implementation handles args
            obj.refresh_plot_if_valid;
        end

        function refresh_plot_if_valid(obj)
            if ~isempty(obj.plotLineHandle) && isvalid(obj.plotLineHandle)
                if isempty(obj.Signal)
                    return
                end
                set(obj.plotLineHandle,'XData',obj.Time,'YData',obj.Signal);
                if ~isempty(obj.plotAxHandle) && isvalid(obj.plotAxHandle)
                    grid(obj.plotAxHandle,'on');
                    xlabel(obj.plotAxHandle,'time (s)');
                end
            end
        end

        function update_handle_value(obj,src,event)
            h = obj.GUIHandles;

            h.(src.Name).Value = obj.(src.Name);
        end

        function interpret_gui(obj,src,event)
            try
                obj.(src.Tag) = event.Value;
                obj.update_signal;
            catch
                obj.(src.Tag) = event.PreviousValue;
            end
        end
    end % methods (Access = protected)

    methods (Static)
        function c = list
            r = which('stimgen.StimType');
            pth = fileparts(r);
            d = dir(fullfile(pth,'*.m'));
            f = {d.name};
            f(ismember(f,{'StimType.m','StimPlay.m','donotsavedatafcn.m'})) = [];
            f(contains(f,'Calib')) = [];
            c = cellfun(@(a) a(1:end-2),f,'uni',0);
        end
    end % methods (Static)
end
