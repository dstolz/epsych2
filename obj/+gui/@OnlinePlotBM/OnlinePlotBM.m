classdef OnlinePlotBM < handle
    
    properties
        ax    (1,1)   % axes handle
        
        trialParam  (1,:) char
        
        lineWidth   (:,1) double {mustBePositive,mustBeFinite} % line plot width [obj.N,1]
        lineColors  (:,3) double {mustBeNonnegative,mustBeLessThanOrEqual(lineColors,1)} % line colors [obj.N,3]
        
        yPositions  (:,1) double {mustBeFinite}
        
        timeWindow  (1,2) duration = seconds([-1 10]);
        
        setZeroToNan (1,1) logical = true;
        
        stayOnTop   (1,1) logical = false;
        paused      (1,1) logical = false;
        
        trialLocked (1,1) logical = false;
    end
    
    properties (SetAccess = private)
        figH        (1,1)  %matlab.ui.Figure
        figName     (1,:)  char
        lineH       (:,1)  matlab.graphics.primitive.Line % handles to line objects [obj.N,1]
        
        N           (1,:)  double % number of watched parameters
        
        startTime   (1,1)  datetime
        
        BoxID       (1,1)  double {mustBePositive,mustBeInteger,mustBeFinite} = 1;
        
        BM   % a structure of bitmask parameters
    end
    
    properties (SetAccess = private,Hidden)
        Timer       (1,1)
        Buffers     (:,:) single
        trialBuffer (1,:) single
        Time        (:,1) single
    end
    
    properties (Constant)
        BufferLength = 200;
    end
    
    
    methods
        
        % Constructor
        function obj = OnlinePlotBM(RUNTIME,BMBank,ax,BoxID)            
            narginchk(2,4);
            
            if nargin >= 3, obj.ax = ax; end
            if nargin == 4, obj.BoxID=BoxID; end
            
            BMBank = cellstr(BMBank);
            pattern = '#(\d+)\^(.+)';
            

            
            for i = 1:length(BMBank)

                p0 = RUNTIME.HW.filter_parameters('Name',sprintf('~BMid-%s',BMBank{i}),...
                    testFcn = @isequal, ...
                    includeInvisible=true);

                if isempty(p0)
                    vprintf(0,1,'BM Bank Not Found: %s',BMBank{i});
                    return
                end
                
                p = RUNTIME.HW.filter_parameters('Name',sprintf('~BM-%s',BMBank{i}), ...
                    testFcn = @startsWith, ...
                    includeInvisible=true);

                if isempty(p)
                    vprintf(0,1,'No bitmask parameters found for bank: %s',BMBank{i});
                    return
                end
                
                strs = {p.Name};
                tokens = regexp(strs, pattern, 'tokens','once');

                n = numel(strs);
                id = NaN(n,1);        % numeric result (NaN when no match)
                label = cell(n,1);      % text result ('' when no match)

                for j = 1:n
                    % tk is a 1x2 cell: {numberStr, textStr}
                    id(j)  = str2double(tokens{j}{1});
                    label{j} = tokens{j}{2};
                end

                obj.BM(i).Bank = p0;                
                obj.BM(i).Label = label;
                obj.BM(i).Bit = id;
                obj.BM(i).N = n;
            end
            obj.N = sum([obj.BM.N]);
            
            % set buffer size
            obj.Buffers     = nan(obj.BufferLength,obj.N,'single');
            obj.Time        = zeros(obj.BufferLength,1,'single');
            obj.trialBuffer = zeros(obj.BufferLength,1,'single');
            
            obj.lineColors = jet(obj.N);
            
            if isempty(obj.ax)
                obj.setup_figure;
            end
            
            disableDefaultInteractivity(ax)
            ax.Toolbar.Visible = false;
            
            obj.add_context_menu;
            
            % set default trial-based parameter tag to use.
            % > _TrigState~1 is contained in the standard epsych RPvds
            % macros and is assigned an integer id after the ~ based on the
            % macros settings.  Default = 1.

            % obj.trialParam = sprintf('#TrigState~%d',BoxID);
            obj.trialParam = sprintf('_TrigState~%d',BoxID);
            
            
            obj.Timer = timer(Tag = sprintf('OnlinePlotBM~%d',BoxID));
            obj.Timer.TasksToExecute = inf;
            obj.Timer.BusyMode = 'drop';
            obj.Timer.ExecutionMode = 'fixedRate';
            obj.Timer.StartFcn = @obj.setup_plot;
            obj.Timer.TimerFcn = @obj.update;
            obj.Timer.ErrorFcn = @obj.error;
            obj.Timer.Period = 0.05; % seconds
            
            start(obj.Timer);
        end
        
        % Destructor
        function delete(obj)
            try
                stop(obj.Timer);
                delete(obj.Timer);
            end
        end
        
        function pause(obj,varargin)
            obj.paused = ~obj.paused;
            
            c = obj.get_menu_item('uic_pause');
            if obj.paused
                c.Label = 'Catch up >';
            else
                c.Label = 'Pause ||';
            end
        end
        
        function c = get.figH(obj)
            c = ancestor(obj.ax,'figure');
        end
        
        function s = get.figName(obj)
            s = sprintf('Online Plot | Box %d',obj.BoxID);
        end
        
        function set.yPositions(obj,y)
            assert(length(y) == obj.N,'epsych:OnlinePlot:set.yPositions', ...
                'Must set all yPositions at once');
            obj.yPositions = y;
        end
        
        function y = get.yPositions(obj)
            if isempty(obj.yPositions)
                y = 1:obj.N;
            else
                y = obj.yPositions;
                if length(y) < obj.N
                    y = [y; y(end)+(1:obj.N-length(y))'+max(diff(y))];
                else
                    y = y(1:obj.N);
                end
                
            end
        end
        
        
        function w = get.lineWidth(obj)
            if isempty(obj.lineWidth)
                w = repmat(10,obj.N,1);
            else
                w = obj.lineWidth;
                if length(w) < obj.N
                    w = [w; repmat(10,obj.N-length(w),1)];
                else
                    w = w(1:obj.N);
                end
            end
        end
        
        
        function set.lineColors(obj,c)
            if isempty(c), c = [.2 .2 .2]; end
            
            if size(c,1) == 1
                c = repmat(c,obj.N,1);
            end
            obj.lineColors = c(1:obj.N,:);
            
            if isempty(obj.lineH), return; end
            for i = 1:obj.N
                obj.lineH(i).Color = c(i,:);
            end
        end
        
        
        function to = last_trial_onset(obj)
            idx = find(obj.trialBuffer(2:end) > obj.trialBuffer(1:end-1),1,'last'); % find onsets
            if isempty(idx)
                %to = obj.Time(end);
                to = [];
            else
                to = obj.Time(idx);
            end                
        end
        
        % -------------------------------------------------------------
        function update(obj,varargin)
            global PRGMSTATE
            
            persistent LTO % last trial onset
            persistent lastPlotTime

            
            
            % stop if the program state has changed
            if ismember(PRGMSTATE,{'STOP','ERROR'}), stop(obj.Timer); return; end
            
            
            if ~isempty(obj.trialParam)
                try
                    obj.trialBuffer(1:end-1) = obj.trialBuffer(2:end);
                    obj.trialBuffer(end) = obj.HW.get_parameter(obj.trialParam);
                catch
                    vprintf(0,1,'Unable to read the parameter: %s\nUpdate the trialParam to an existing parameter in the RPvds circuit', ...
                        obj.trialParam)
                    c = obj.get_menu_item('uic_plotType');
                    delete(c);
                    obj.trialParam = '';
                end
            end
            
            % convert bitmasks
            for i = 1:length(obj.BM)
                obj.BM(i).Mask = obj.BM(i).Bank.Value;
                obj.BM(i).State = bitget(obj.BM(i).Mask,obj.BM(i).Bit+1);
            end

            % combine bitmasks
            bms = cat(1,obj.BM(:).State);

            % shift and update Buffers
            obj.Buffers(1:end-1,:) = obj.Buffers(2:end,:);
            obj.Buffers(end,:) = single(bms);
            if obj.setZeroToNan, obj.Buffers(end,obj.Buffers(end,:)==0) = nan; end
            
            
            obj.Time(1:end-1,:) = obj.Time(2:end,:);
            obj.Time(end) = single(seconds(datetime('now')-obj.startTime));
            
            if obj.paused, return; end
            
            if isempty(lastPlotTime), lastPlotTime = datetime('now') - seconds(1); end 
            if seconds(datetime('now') - lastPlotTime) < 0.1, return; end
            vprintf(5,'Updating Online Plot')
            
            for i = 1:obj.N
                obj.lineH(i).XData = obj.Time;
                obj.lineH(i).YData = obj.yPositions(i).*obj.Buffers(:,i);
            end
            
            
            lto = obj.last_trial_onset;
            if obj.trialLocked && ~isempty(obj.trialParam) && ~isempty(lto) && ~isequal(lto,LTO)
                obj.ax.XLim = lto + obj.timeWindow;

                
                % w = obj.timeWindow2number;
                % s = seconds(diff(w)/10);
                % obj.ax.XAxis.TickValues = lto-s:s:lto+seconds(w(2));
                
            elseif obj.trialLocked && ~isequal(lto,LTO)
                obj.ax.XLim = obj.timeWindow;
                
            elseif ~obj.trialLocked
                obj.ax.XLim = seconds(obj.Time(end) + [-6 1]);
                obj.ax.XAxis.TickValuesMode = 'auto';
                
            end
            
            if ~isequal(lto,LTO)
                obj.plot_trialMarker(lto);
            end
            
            drawnow limitrate
            lastPlotTime = datetime('now');

            LTO = lto;

        end
        
        function plot_trialMarker(obj,t)
            if isempty(t), return; end
            line(obj.ax,[1 1]*t,obj.ax.YLim,'Color',[1 0 0],'LineWidth',2);
            
            
            tn = obj.getParamVals(obj.TDTActiveX,'_TrialNum~1');
            tn = tn - 1;
            text(obj.ax,t,obj.N+0.5,num2str(tn,'%d'),'FontWeight','Bold','FontSize',15);
        end
        
        function error(obj,varargin)
            vprintf(-1,'OnlinePlot closed with error')
            vprintf(-1,varargin{2}.Data.messageID)
            vprintf(-1,varargin{2}.Data.message)
        end
    end
    
    
    
    
    
    
    
    
    
    
    methods (Access = protected)
        
        function setup_plot(obj,varargin)
            delete(obj.lineH);
            
            for i = 1:obj.N
                obj.lineH(i) = line(obj.ax,seconds(0),obj.yPositions(i), ...
                    'color',obj.lineColors(i,:), ...
                    'linewidth',obj.lineWidth(i));
            end
            
            
            xtickformat(obj.ax,'mm:ss.S');
            grid(obj.ax,'on');
            
            obj.ax.YAxis.Limits = [.8 obj.yPositions(end)+.2];
            obj.ax.YAxis.TickValues = obj.yPositions;
            obj.ax.YAxis.TickLabelInterpreter = 'none';
            lbl = cat(1,obj.BM(:).Label);
            obj.ax.YAxis.TickLabels = lbl;
            obj.ax.XMinorGrid = 'on';
            obj.ax.Box = 'on';
            
            %obj.ax.XAxis.Label.String = 'time since start (mm:ss)';
            
            obj.startTime = datetime('now');
        end
        
        
        
        function setup_figure(obj)
            f = findobj('type','figure','-and', ...
                '-regexp','name',[obj.figName '*']);
            if isempty(f)
                f = figure('Name',obj.figName,'color','w','NumberTitle','off','visible','off');
            end
            clf(f);
            figure(f);
            f.Position([3 4]) = [800 175];
            
            obj.ax = axes(f);
            
            f.Visible = 'on';
        end
        
        function add_context_menu(obj)
            c = uicontextmenu(obj.figH);
            
            switch class(obj.ax)
                case 'matlab.ui.control.UIAxes'
                    obj.ax.ContextMenu = c; 
                otherwise
                    c.Parent = obj.figH;
            end
            
            if obj.trialLocked
                lbl = 'Set Plot to Free-Running';
            else
                lbl = 'Set Plot to Trial-Locked';
            end
            
            uimenu(c,'Tag','uic_stayOnTop','Label','Keep Window on Top','Callback',@obj.stay_on_top);
            uimenu(c,'Tag','uic_pause','Label','Pause ||','Callback',@obj.pause);
            uimenu(c,'Tag','uic_plotType','Label',lbl,'Callback',{@obj.plot_type,true});
            uimenu(c,'Tag','uic_timeWindow','Label',sprintf('Time Window = [%.1f %.1f] seconds',obj.timeWindow2number),'Callback',@obj.update_window);
            obj.ax.UIContextMenu = c;
        end
        
        function stay_on_top(obj,varargin)
            obj.stayOnTop = ~obj.stayOnTop;
            
            c = obj.get_menu_item('uic_stayOnTop');
            if obj.stayOnTop
                c.Label = 'Don''t Keep Window on Top';
                obj.figH.Name = [obj.figName ' - *On Top*'];
            else
                c.Label = 'Keep Window on Top';
                obj.figH.Name = obj.figName;
            end
            figAlwaysOnTop(obj.figH,obj.stayOnTop);
        end
        
        function plot_type(obj,src,event,toggle)
            if nargin > 1 && isequal(class(src),'logical')
                obj.trialLocked = src;
            elseif nargin == 4 && toggle
                obj.trialLocked = ~obj.trialLocked; 
            end

            c = obj.get_menu_item('uic_plotType');
            atw = abs(obj.timeWindow);
            if isempty(obj.trialParam)
                vprintf(0,1,'Unable to set the plot to Trial-Locked mode because the trialParam is empty')
            elseif obj.trialLocked
                obj.timeWindow = [-min(atw) max(atw)];
                c.Label = 'Set Plot to Free-Running';
            else
                obj.timeWindow = [-max(atw) min(atw)];
                c.Label = 'Set Plot to Trial-Locked';
            end
        end
        
        function update_window(obj,varargin)
            % temporarily disable stay on top if selected
            figAlwaysOnTop(obj.figH,false);
            r = inputdlg('Adjust time windpw (seconds)','Online Plot', ...
                1,{sprintf('[%.1f %.1f]',obj.timeWindow2number)});
            if isempty(r), return; end
            r = str2num(char(r)); %#ok<ST2NM>
            if numel(r) ~= 2
                vprintf(0,1,'Must enter 2 values for the time window')
                return
            end
            obj.timeWindow = seconds(r(:)');
            

            c = obj.get_menu_item('uic_timeWindow');
            c.Label = sprintf('Time Window = [%.1f %.1f] seconds',obj.timeWindow2number);
            figAlwaysOnTop(obj.figH,obj.stayOnTop);
        end
        
        function s = timeWindow2number(obj)
            s = cellstr(char(obj.timeWindow));
            s = cellfun(@(a) str2double(a(1:find(a==' ',1,'last')-1)),s);
        end
        
        function c = get_menu_item(obj,tag) 
            C = obj.ax.ContextMenu.Children;
            c = C(ismember({obj.ax.ContextMenu.Children.Tag},tag));
        end
    end
    
    
end










