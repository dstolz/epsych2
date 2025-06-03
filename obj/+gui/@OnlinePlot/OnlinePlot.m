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
        N           (1,:)  double % Number of watched parameters
        startTime   (1,1) datetime
        BoxID       (1,1) {mustBePositive,mustBeInteger} = 1;
    end

    properties (SetAccess = immutable)
        HW                 % Hardware interface (assigned at construction)
    end

    properties (SetAccess = private, Hidden)
        h_timer       (1,1)      % Update h_timer object
        Buffers     (:,:) single   % Plot data buffer [N, time]
        BufferIdx
        DrawCounter
        trialBuffer (1,:) single   % Buffer for trial trigger parameter
        Time        (:,1) duration % Buffer for time values
        hl_mode               % Listener for mode changes
    end

    methods
        function obj = OnlinePlot(RUNTIME,watchedParams,hax,BoxID)
            % Constructor: initializes online plot with chosen parameters and axes.
            narginchk(2,4);
            obj.HW = RUNTIME.HW;
            % Select parameters to plot if not provided
            if nargin < 2 || isempty(watchedParams)
                p = RUNTIME.HW.filter_parameters('Access','Read',testFcn=@contains);
                [s,v] = listdlg('PromptString','Select parameters for plot', ...
                    'SelectionMode','multiple','ListString',p);
                if v == 0, delete(obj); return; end
                watchedParams = p(s);
            end
            if nargin < 3, hax = gca; end
            if nargin < 4 || isempty(BoxID), BoxID = 1; end
            obj.watchedParams = obj.HW.find_parameter(watchedParams,includeInvisible=true);
            if isempty(hax)
                obj.setup_figure;
            else
                obj.hax = hax;
            end
            obj.add_context_menu;
            obj.BoxID = BoxID;
            obj.trialParam = obj.HW.find_parameter(sprintf('_TrigState~%d',BoxID),includeInvisible=true);
            obj.h_timer = gui.GenericTimer(obj.figH,sprintf('epsych_gui_OnlinePlot~%d',BoxID));
            obj.h_timer.Timer.StartFcn = @obj.setup_plot;
            obj.h_timer.Timer.TimerFcn = @obj.update;
            obj.h_timer.Timer.ErrorFcn = @obj.error;
            obj.h_timer.Timer.Period = 0.05;
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
            % Get last trial onset time from trialBuffer.
            B = obj.trialBuffer;
            idx = find(B(2:end) > B(1:end-1),1,'last');
            if isempty(idx)
                to = [];
            else
                to = obj.Time(idx);
            end
        end

        % function update(obj,varargin)
        %     % Update the plot with new hardware parameter values.
        %     if ~isempty(obj.trialParam)
        %         try
        %             obj.trialBuffer(end+1) = obj.trialParam.Value;
        %         catch me
        %             vprintf(0,1,'Unable to read the parameter: %s\nUpdate the trialParam to an existing parameter in the RPvds circuit', ...
        %                 obj.trialParam)
        %             c = obj.get_menu_item('uic_plotType');
        %             delete(c);
        %             obj.trialParam = '';
        %         end
        %     end
        %     obj.Buffers(:,end+1) = [obj.watchedParams.Value];
        %     if obj.setZeroToNan, obj.Buffers(obj.Buffers(:,end)==0,end) = nan; end
        %     obj.Time(end+1) = datetime("now")-obj.startTime;
        %     if obj.paused, return; end
        %     for i = 1:obj.N
        %         set(obj.lineH(i),'XData',obj.Time,'YData',obj.yPositions(i).*obj.Buffers(i,:));
        %     end
        %     if obj.trialLocked && ~isempty(obj.trialParam) && ~isempty(obj.last_trial_onset)
        %         obj.hax.XLim = obj.last_trial_onset + obj.timeWindow;
        %     elseif obj.trialLocked
        %         obj.hax.XLim = obj.timeWindow;
        %     else
        %         obj.hax.XLim = obj.Time(end) + obj.timeWindow;
        %     end
        %     drawnow limitrate
        % end
        % UPDATE: Efficient circular buffer, throttled draw, and windowed plotting
        function update(obj,varargin)
            % --- 1. Initialize circular buffers if empty ---
            blockSize = 1000; % Set or store as a property for flexibility
            if isempty(obj.Buffers)
                obj.Buffers = nan(obj.N, blockSize, 'single');
                obj.Time = duration(nan(blockSize, 1),0,0);
                obj.BufferIdx = 1;
                obj.DrawCounter = 0; % For throttling
            end

            % --- 2. Update trial buffer if trialParam available ---
            if ~isempty(obj.trialParam)
                try
                    % Grow trialBuffer if needed (use circular logic if long)
                    if ~isfield(obj, 'trialBuffer') || isempty(obj.trialBuffer)
                        obj.trialBuffer = zeros(1, blockSize, 'single');
                    end
                    obj.trialBuffer(obj.BufferIdx) = obj.trialParam.Value;
                catch
                    vprintf(0,1,'Unable to read the parameter: %s\nUpdate the trialParam to an existing parameter in the RPvds circuit', obj.trialParam)
                    c = obj.get_menu_item('uic_plotType');
                    delete(c);
                    obj.trialParam = '';
                end
            end

            % --- 3. Store watched parameter values and time ---
            obj.Buffers(:, obj.BufferIdx) = [obj.watchedParams.Value];
            obj.Time(obj.BufferIdx) = datetime("now") - obj.startTime;

            % --- 4. Optionally set zero to nan (only for new column) ---
            if obj.setZeroToNan
                newcol = obj.Buffers(:, obj.BufferIdx);
                if any(newcol == 0)
                    obj.Buffers(newcol == 0, obj.BufferIdx) = nan;
                end
            end

            % --- 5. Plot only if not paused ---
            if obj.paused
                obj.BufferIdx = mod(obj.BufferIdx, blockSize) + 1;
                return;
            end

            % --- 6. Choose data to plot (latest window, in time order) ---
            if obj.BufferIdx == 1
                idx = 1:blockSize; % buffer has wrapped, full window
            else
                idx = [obj.BufferIdx:blockSize 1:obj.BufferIdx-1]; % recent data
            end
            plotTime = obj.Time(idx);
            plotBuffers = obj.Buffers(:, idx);
            plotTrialBuffer = [];
            if isfield(obj, 'trialBuffer') && ~isempty(obj.trialBuffer)
                plotTrialBuffer = obj.trialBuffer(idx);
            end

            % --- 7. Plot update: only plot within visible time window ---
            win = obj.timeWindow;
            if obj.trialLocked && ~isempty(obj.trialParam) && ~isempty(obj.last_trial_onset)
                t0 = obj.last_trial_onset;
                tspan = (plotTime >= (t0 + win(1))) & (plotTime <= (t0 + win(2)));
            elseif obj.trialLocked
                t0 = 0;
                tspan = (plotTime >= win(1)) & (plotTime <= win(2));
            else
                t0 = plotTime(end);
                tspan = (plotTime >= (t0 + win(1))) & (plotTime <= (t0 + win(2)));
            end
            plotTimeWin = plotTime(tspan);
            plotBuffersWin = plotBuffers(:, tspan);

            % --- 8. Throttle graphics updates (e.g., only draw every 3 updates) ---
            obj.DrawCounter = obj.DrawCounter + 1;
            throttleRate = 1; % update plot every 3 h_timer ticks
            if mod(obj.DrawCounter, throttleRate) ~= 0
                obj.BufferIdx = mod(obj.BufferIdx, blockSize) + 1;
                return
            end

            % --- 9. Update line data for visible window ---
            for i = 1:obj.N
                set(obj.lineH(i),'XData',plotTimeWin,'YData',obj.yPositions(i).*plotBuffersWin(i,:));
            end

            % --- 10. Adjust x-limits ---
            try
                if obj.trialLocked && ~isempty(obj.trialParam) && ~isempty(obj.last_trial_onset)
                    obj.hax.XLim = obj.last_trial_onset + win;
                elseif obj.trialLocked
                    obj.hax.XLim = win;
                else
                    obj.hax.XLim = obj.Time(obj.BufferIdx) + win;
                end
                drawnow limitrate
            end
            % --- 11. Advance circular buffer pointer ---
            obj.BufferIdx = mod(obj.BufferIdx, blockSize) + 1;
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
            obj.startTime = datetime("now");
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
            FigOnTop(obj.figH,obj.stayOnTop);
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
            FigOnTop(obj.figH,false); % temporarily disable stay-on-top
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
            FigOnTop(obj.figH,obj.stayOnTop);
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
