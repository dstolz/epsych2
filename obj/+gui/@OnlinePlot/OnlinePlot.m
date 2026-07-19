classdef OnlinePlot < handle
    % OnlinePlot: Real-time multi-parameter plotting for behavioral hardware.
    %   Plots and updates hardware parameters online for a single experimental box.
    %   Provides pause, context menus, time window, and trial-locked plotting.

    properties
        hax            (1,1)   % Axes handle for plotting
        watchedParams  (1,:)   % Array of hw.Parameter objects being plotted
        trialParam     (1,1)   % Parameter for trial-based (triggered) plotting
        lineWidth      (:,1) double {mustBePositive,mustBeFinite} % Line width per plot
        lineColors     (:,3) double {mustBeNonnegative,mustBeLessThanOrEqual(lineColors,1)} % Line RGB colors per plot
        yPositions     (:,1) double {mustBeFinite}   % Y offsets for each trace
        timeWindow     (1,2) duration = seconds([-10 3]); % Time axis window
        setZeroToNan   (1,1) logical = true;         % Replace 0s with NaN for visibility
        stayOnTop      (1,1) logical = false;        % Keep window always on top
        paused         (1,1) logical = false;        % If true, pause updating
        trialLocked    (1,1) logical = false;        % If true, plot is trial-locked
    end

    properties (SetAccess = private)
        figH        (1,1)  % Main figure handle
        figName     (1,:)  char % Name for figure window
        lineH       (:,1)  matlab.graphics.primitive.Line % Handles to plot lines
        nowLine     (1,1)  matlab.graphics.primitive.Line 
        N           (1,:)  double % Number of watched parameters
        startTime   (1,1) double % Session start time (serial date number from `now`)
        BoxID       (1,1) {mustBePositive,mustBeInteger} = 1;
    end

    properties (SetAccess = immutable)
        HW                 % Hardware interface (assigned at construction)
    end

    properties (SetAccess = private, Hidden)
        h_timer       (1,1)      % Update h_timer object
        Buffers     (:,:) single   % Plot data buffer [N, time]
        BufferIdx   (1,1) double = 1   % Next circular-buffer slot to write
        Time        (:,1) double  % Buffer for time values (elapsed seconds since startTime)
        nFilled     (1,1) double = 0   % Number of valid samples written so far (saturates at blockSize)
        writeCount  (1,1) double = 0   % Monotonic update() tick count, never wraps
        prevTrigValue (1,1) double = nan % Last trialParam value seen; enables O(1) edge detection
        lastOnsetTime (1,1) double = nan % Elapsed-seconds timestamp of the last detected trial onset
        lastOnsetWriteCount (1,1) double = nan % writeCount recorded at the last detected onset
        lastPlotTime (1,1) double = -inf % Elapsed-seconds timestamp of the last actual redraw
        periodNom   (1,1) double = 0.1  % Cached nominal timer period (seconds), used to size the plot window read
        hl_mode               % Listener for mode changes
    end

    methods
        function obj = OnlinePlot(RUNTIME,watchedParams,hax,BoxID)
            % Constructor: initializes online plot with chosen parameters and axes.
            narginchk(2,4);
            obj.HW = RUNTIME.HW;
            % Select parameters to plot if not provided
            if nargin < 2 || isempty(watchedParams)
                p = RUNTIME.filter_parameters('Access','Read',testFcn=@contains);
                [s,v] = listdlg('PromptString','Select parameters for plot', ...
                    'SelectionMode','multiple','ListString',p);
                if v == 0, delete(obj); return; end
                watchedParams = p(s);
            end
            if nargin < 3, hax = gca; end
            if nargin < 4 || isempty(BoxID), BoxID = 1; end
            obj.watchedParams = obj.find_parameter(watchedParams,includeInvisible=true);
            if isempty(hax)
                obj.setup_figure;
            else
                obj.hax = hax;
            end
            obj.add_context_menu;
            obj.BoxID = BoxID;
            obj.trialParam = obj.find_parameter(sprintf('_TrigState~%d',BoxID),includeInvisible=true);
            obj.h_timer = gui.GenericTimer(obj.figH,sprintf('epsych_gui_OnlinePlot~%d',BoxID));
            obj.h_timer.Timer.StartFcn = @obj.setup_plot;
            obj.h_timer.Timer.TimerFcn = @obj.update;
            obj.h_timer.Timer.ErrorFcn = @obj.error;
            obj.h_timer.Timer.Period = 0.1;
            obj.h_timer.Timer.start;
            obj.hl_mode = listener(RUNTIME.HW,'mode','PostSet',@obj.mode_change);
        end

        function delete(obj)
            % Destructor: Stops h_timer and cleans up resources.
            try
                stop(obj.h_timer);
                delete(obj.h_timer);
            end

            try
                obj.hl_mode.Enabled = 0;
                delete(obj.hl_mode);
            end
        end

        function pause(obj,varargin)
            % Toggle paused state, update menu label.
            obj.paused = ~obj.paused;
            c = obj.get_menu_item('uic_pause');
            if obj.paused
                c.Label = 'Catch up >';
            else
                c.Label = 'Pause ||';
            end
        end

        function c = get.figH(obj)
            % Get the ancestor figure handle from axes.
            c = ancestor(obj.hax,'figure');
        end

        function s = get.figName(obj)
            % Get name string for the figure window.
            s = sprintf('Online Plot | Box %d',obj.BoxID);
        end

        function set.yPositions(obj,y)
            % Set Y offsets for each trace, must match number of parameters.
            assert(length(y) == obj.N,'epsych:OnlinePlot:set.yPositions', ...
                'Must set all yPositions at once');
            obj.yPositions = y;
        end

        function y = get.yPositions(obj)
            % Return current or default Y offsets.
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
            % Get or set default line widths for all traces.
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

        function c = get.lineColors(obj)
            % Get or expand default RGB colors for lines.
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
            % Number of watched parameters.
            s = numel(obj.watchedParams);
        end

        function to = last_trial_onset(obj)
            % Elapsed-seconds timestamp (double) of the most recent trial onset.
            % Tracked incrementally in update() (see prevTrigValue/lastOnsetTime)
            % rather than rescanning a buffer every call.
            blockSize = 1000;
            if isnan(obj.lastOnsetTime) || (obj.writeCount - obj.lastOnsetWriteCount) > blockSize
                to = []; % no onset yet, or onset predates the retained buffer history
            else
                to = obj.lastOnsetTime;
            end
        end

        % Efficient circular buffer, throttled draw, and windowed plotting
        function update(obj,varargin)
            % --- 1. Initialize circular buffers if empty ---
            blockSize = 1000; % Set or store as a property for flexibility
            if isempty(obj.Buffers)
                obj.Buffers = nan(obj.N, blockSize, 'single');
                obj.Time = nan(blockSize, 1);
                obj.BufferIdx = 1;
                obj.nFilled = 0;
                obj.writeCount = 0;
                obj.prevTrigValue = nan;
                obj.lastOnsetTime = nan;
                obj.lastOnsetWriteCount = nan;
                obj.lastPlotTime = -inf;
                obj.periodNom = obj.h_timer.Timer.Period;
            end

            currentRawIdx = obj.BufferIdx;
            nowT = (now - obj.startTime) * 86400; % elapsed seconds; `now` is much faster than datetime("now")

            % --- 2. Trial onset detection: O(1) rising-edge check (never skipped) ---
            if ~isempty(obj.trialParam)
                try
                    v = obj.trialParam.Value;
                    if ~isnan(obj.prevTrigValue) && v > obj.prevTrigValue
                        obj.lastOnsetTime = nowT;
                        obj.lastOnsetWriteCount = obj.writeCount;
                    end
                    obj.prevTrigValue = v;
                catch
                    vprintf(0,1,'Unable to read the parameter: %s\nUpdate the trialParam to an existing parameter in the RPvds circuit', obj.trialParam)
                    c = obj.get_menu_item('uic_plotType');
                    delete(c);
                    obj.trialParam = '';
                end
            end

            % --- 3. Store watched parameter values and time ---
            obj.Buffers(:, currentRawIdx) = [obj.watchedParams.Value];
            obj.Time(currentRawIdx) = nowT;

            % --- 4. Optionally set zero to nan (only for new column) ---
            if obj.setZeroToNan
                newcol = obj.Buffers(:, currentRawIdx);
                obj.Buffers(newcol == 0, currentRawIdx) = nan;
            end

            % --- 5. Advance circular buffer pointer (single site) ---
            obj.BufferIdx = mod(obj.BufferIdx, blockSize) + 1;
            obj.nFilled = min(obj.nFilled + 1, blockSize);
            obj.writeCount = obj.writeCount + 1;

            % --- 6. Skip plotting while paused ---
            if obj.paused, return; end

            % --- 7. Throttle redraws to ~10 Hz wall-clock, independent of tick rate ---
            if (nowT - obj.lastPlotTime) < 0.1, return; end

            % --- 8. Only pull the recent samples the visible window actually needs ---
            lto = obj.last_trial_onset; % call once per tick
            winSec = seconds(obj.timeWindow);
            if obj.trialLocked && ~isempty(obj.trialParam) && ~isempty(lto)
                t0 = lto;
            elseif obj.trialLocked
                t0 = 0;
            else
                t0 = nowT;
            end

            neededSpanSec = max(0, nowT - (t0 + winSec(1)));
            Nlook = max(1, min([obj.nFilled, blockSize, ceil(neededSpanSec/obj.periodNom) + 5]));

            startRaw = currentRawIdx - Nlook + 1;
            if startRaw >= 1
                rawIdx = startRaw:currentRawIdx; % single contiguous piece
            else
                rawIdx = [(blockSize+startRaw):blockSize, 1:currentRawIdx]; % one wraparound piece
            end
            % rawIdx walks strictly backward from the write head, so it is
            % always chronologically ascending -- no sort needed.
            plotTime = obj.Time(rawIdx);
            plotBuf  = obj.Buffers(:, rawIdx);

            if obj.trialLocked && ~isempty(obj.trialParam) && ~isempty(lto)
                tspan = (plotTime >= (t0 + winSec(1))) & (plotTime <= (t0 + winSec(2)));
            elseif obj.trialLocked
                tspan = (plotTime >= winSec(1)) & (plotTime <= winSec(2));
            else
                tspan = (plotTime >= (t0 + winSec(1))) & (plotTime <= (t0 + winSec(2)));
            end
            plotTimeWin = plotTime(tspan);
            plotBuffersWin = plotBuf(:, tspan);

            % --- 9. Update line data for visible window ---
            yPos = obj.yPositions; % hoisted once per tick, not obj.N times
            for i = 1:obj.N
                obj.lineH(i).XData = seconds(plotTimeWin);
                obj.lineH(i).YData = yPos(i).*plotBuffersWin(i,:);
            end

            % --- 10. Adjust x-limits ---
            if obj.trialLocked && ~isempty(obj.trialParam) && ~isempty(lto)
                obj.hax.XLim = seconds(lto + winSec);
            elseif obj.trialLocked
                obj.hax.XLim = seconds(winSec);
            else
                obj.hax.XLim = seconds(nowT + winSec);
            end
            if ~isempty(plotTimeWin)
                obj.nowLine.XData = seconds(plotTimeWin(end)).*[1 1];
            end
            drawnow limitrate

            obj.lastPlotTime = nowT;
        end

        function error(obj,varargin)
            % Handles h_timer errors.
            vprintf(-1,'OnlinePlot closed with error')
            vprintf(-1,varargin{2}.Data.messageID)
            vprintf(-1,varargin{2}.Data.message)
        end
    end

    methods (Access = protected)
        function setup_plot(obj,varargin)
            % Create/recreate plot lines and initialize plot axes/labels.
            delete(obj.lineH);
            for i = 1:length(obj.watchedParams)
                obj.lineH(i) = line(obj.hax,seconds(0),obj.yPositions(i), ...
                    'color',obj.lineColors(i,:), ...
                    'linewidth',obj.lineWidth(i));
            end
            xtickformat(obj.hax,'mm:ss.S');
            grid(obj.hax,'on');
            obj.hax.YAxis.Limits = [.8 obj.yPositions(end)+.2];
            obj.hax.YAxis.TickValues = obj.yPositions;
            obj.hax.YAxis.TickLabelInterpreter = 'none';
            obj.hax.YAxis.TickLabels = {obj.watchedParams.Name};
            obj.hax.XMinorGrid = 'on';
            obj.hax.Box = 'on';
            obj.startTime = now; % `now` is much faster than datetime("now")
            obj.nowLine = line(obj.hax,seconds([0 0]),[-1e6 1e6],AffectAutoLimits="off");

        end

        function setup_figure(obj)
            % Create or reuse a figure/axes for plotting if none supplied.
            f = findobj('type','figure','-and', '-regexp','name',[obj.figName '*']);
            if isempty(f)
                f = figure('Name',obj.figName,'color','w','NumberTitle','off','visible','off');
            end
            clf(f); figure(f);
            f.Position([3 4]) = [800 175];
            obj.hax = axes(f);
            disableDefaultInteractivity(obj.hax);
            obj.hax.Toolbar = [];
            f.Visible = 'on';
        end

        function add_context_menu(obj)
            % Add right-click menu to axes for extra plot options.
            c = uicontextmenu(obj.figH);
            switch class(obj.hax)
                case 'matlab.ui.control.UIAxes'
                    obj.hax.ContextMenu = c;
                otherwise
                    c.Parent = obj.figH;
            end
            uimenu(c,'Tag','uic_stayOnTop','Label','Keep Window on Top','Callback',@obj.stay_on_top);
            uimenu(c,'Tag','uic_pause','Label','Pause ||','Callback',@obj.pause);
            uimenu(c,'Tag','uic_plotType','Label','Set Plot to Trial-Locked','Callback',{@obj.plot_type,true});
            uimenu(c,'Tag','uic_timeWindow','Label',sprintf('Time Window = [%.1f %.1f] seconds',obj.timeWindow2number),'Callback',@obj.update_window);
            obj.hax.UIContextMenu = c;
        end

        function stay_on_top(obj,varargin)
            % Toggle window always-on-top state and update menu/label.
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
            % Toggle between trial-locked and free-running plot x-axis.
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
            % Adjust time window for plot x-axis.
            figAlwaysOnTop(obj.figH,false); % temporarily disable stay-on-top
            r = inputdlg('Adjust time windpw (seconds)','Online Plot', 1, {sprintf('[%.1f %.1f]',obj.timeWindow2number)});
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
            % Helper to convert duration timeWindow to numeric vector.
            s = cellstr(char(obj.timeWindow));
            s = cellfun(@(a) str2double(a(1:find(a==' ',1,'last')-1)),s);
        end

        function c = get_menu_item(obj,tag)
            % Find context menu item by tag.
            C = obj.hax.ContextMenu.Children;
            c = C(ismember({obj.hax.ContextMenu.Children.Tag},tag));
        end

        function mode_change(obj,src,event)
            % Stop h_timer if hardware mode changes.
            if event.AffectedObject.mode < 2
                stop(obj.h_timer);
            end
        end
    end
end
