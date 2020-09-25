classdef OnlinePlotBM < gui.Helper & handle
    
    properties
        ax    (1,1)   % axes handle
        
        trialParam  (1,:) char
        
        lineWidth   (:,1) double {mustBePositive,mustBeFinite} % line plot width [obj.N,1]
        lineColors  (:,3) double {mustBeNonnegative,mustBeLessThanOrEqual(lineColors,1)} % line colors [obj.N,3]
        
        yPositions  (:,1) double {mustBeFinite}
        
        timeWindow  (1,2) duration = seconds([-10 3]);
        
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
        
        startTime   (1,6)  double % = clock
        
        BoxID       (1,1)  uint8 = 1;
        
        RPvdsBitmask (1,1)
    end
    
    properties (SetAccess = private,Hidden)
        Timer       (1,1)
        Buffers     (:,:) single
        trialBuffer (1,:) single
        Time        (:,1) duration
    end
    
    
    methods
        
        % Constructor
        function obj = OnlinePlotBM(TDTActiveX,BMBank,ax,BoxID)
            global RUNTIME
            
            narginchk(2,4);
            
            if nargin < 3, ax = []; end
            if nargin < 4 || isempty(BoxID), BoxID = 1; end
                       
            obj.TDTActiveX = TDTActiveX;
            
            obj.RPvdsBitmask = RPvdsBitmask(RUNTIME,TDTActiveX,BMBank);
            
            
            if isempty(ax)
                obj.setup_figure;
            else
                obj.ax = ax;
            end
            
            obj.add_context_menu;
            
            % set default trial-based parameter tag to use.
            % > #TrigState~1 is contained in the standard epsych RPvds
            % macros and is assigned an integer id after the ~ based on the
            % macros settings.  Default = 1.
            obj.BoxID = BoxID;
            obj.trialParam = sprintf('#TrigState~%d',BoxID);
            
            obj.Timer = ep_GenericGUITimer(obj.figH,sprintf('OnlinePlot~%d',BoxID));
            obj.Timer.StartFcn = @obj.setup_plot; % THESE MIGHT NEED TO BE STATIC FUNCTIONS?!
            obj.Timer.TimerFcn = @obj.update;
            obj.Timer.ErrorFcn = @obj.error;
            obj.Timer.Period = 0.05;
            
            start(obj.Timer);
            
        end
        
        % Destructor
        function delete(obj)
            try
                stop(obj.Timer);
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
                w = repmat(14,obj.N,1);
            else
                w = obj.lineWidth;
                if length(w) < obj.N
                    w = [w; repmat(10,obj.N-length(w),1)];
                else
                    w = w(1:obj.N);
                end
            end
        end
        
        function c = get.lineColors(obj)
            if isempty(obj.lineColors)
                c = lines(obj.N);
            else
                c = obj.lineColors;
                if size(c,1) < obj.N
                    x = lines(obj.N);
                    c = [c; x(size(c,1)+1:obj.N,:)];
                else
                    c = c(1:obj.N);
                end
            end
            
        end
        
        function s = get.N(obj)
            s = numel(obj.RPvdsBitmask.Bits);
        end
        
        function to = last_trial_onset(obj)
            B = obj.trialBuffer;
            idx = find(B(2:end) > B(1:end-1),1,'last'); % find onsets
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
            
            % stop if the program state has changed
            if ismember(PRGMSTATE,{'STOP','ERROR'}), stop(obj.Timer); return; end
            
            
            if ~isempty(obj.trialParam)
                try
                    obj.trialBuffer(end+1) = obj.getParamVals(obj.TDTActiveX,obj.trialParam);
                catch
                    vprintf(0,1,'Unable to read the RPvds parameter: %s\nUpdate the trialParam to an existing parameter in the RPvds circuit', ...
                        obj.trialParam)
                    c = obj.get_menu_item('uic_plotType');
                    delete(c);
                    obj.trialParam = '';
                end
            end
            
            BS = obj.RPvdsBitmask.BitStates;

            obj.Buffers(:,end+1) = [BS{:,2}];
            if obj.setZeroToNan, obj.Buffers(obj.Buffers(:,end)==0,end) = nan; end
            
            obj.Time(end+1) = seconds(etime(clock,obj.startTime));
            
            if obj.paused, return; end
            
            for i = 1:obj.N
                obj.lineH(i).XData = obj.Time;
                obj.lineH(i).YData = obj.yPositions(i).*obj.Buffers(i,:);
            end
            
            if obj.trialLocked && ~isempty(obj.trialParam) && ~isempty(obj.last_trial_onset)
                obj.ax.XLim = obj.last_trial_onset + obj.timeWindow;
            elseif obj.trialLocked
                obj.ax.XLim = obj.timeWindow;
            else
                obj.ax.XLim = obj.Time(end) + obj.timeWindow;
            end
            drawnow limitrate
            
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
            
            for i = 1:length(obj.RPvdsBitmask.Bits)
                obj.lineH(i) = line(obj.ax,seconds(0),obj.yPositions(i), ...
                    'color',obj.lineColors(i,:), ...
                    'linewidth',obj.lineWidth(i));
            end
            
            
            xtickformat(obj.ax,'mm:ss.S');
            grid(obj.ax,'on');
            
            obj.ax.YAxis.Limits = [.8 obj.yPositions(end)+.2];
            obj.ax.YAxis.TickValues = obj.yPositions;
            obj.ax.YAxis.TickLabelInterpreter = 'none';
            obj.ax.YAxis.TickLabels = obj.RPvdsBitmask.Labels;
            obj.ax.XMinorGrid = 'on';
            obj.ax.Box = 'on';
            
            %obj.ax.XAxis.Label.String = 'time since start (mm:ss)';
            
            obj.startTime = clock;
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
            
            uimenu(c,'Tag','uic_stayOnTop','Label','Keep Window on Top','Callback',@obj.stay_on_top);
            uimenu(c,'Tag','uic_pause','Label','Pause ||','Callback',@obj.pause);
            uimenu(c,'Tag','uic_plotType','Label','Set Plot to Trial-Locked','Callback',{@obj.plot_type,true});
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
            FigOnTop(obj.figH,obj.stayOnTop);
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
            FigOnTop(obj.figH,false);
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
            FigOnTop(obj.figH,obj.stayOnTop);
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










