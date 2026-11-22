classdef (Sealed) Helper < handle
    % gui.Helper
    % Small static GUI utilities (highlighting, timed color changes, metrics).
    %
    % Methods (static):
    %   update_highlight     - Update alternating row colors + highlight rows.
    %   timed_color_change   - Temporarily set a color-like property then reset.
    %   dprime2AFC, criterion, percent_correct - Common SDT helpers.



    methods (Static)
    
        function update_highlight(tableH,row,highlightColor)
            if nargin < 3 || isempty(highlightColor), highlightColor = [0.2 0.6 1]; end
            n = size(tableH.Data,1);
            c = repmat([1 1 1; 0.9 0.9 0.9],ceil(n/2),1);
            c(n+1:end,:) = [];
            if ~isempty(row)
                c(row,:) = repmat(highlightColor,numel(row),1);
            end
            tableH.BackgroundColor = c;
        end




        function timed_color_change(obj, newColor, options)
            % gui.Helper.timed_color_change(obj, newColor)
            % gui.Helper.timed_color_change(obj, newColor, duration=1, postColor=c)
            % Flash a widget: set its colour now and put it back later.
            %
            % Parameters:
            %   obj      - graphics object with a BackgroundColor, Color or
            %              FontColor property (the first of those it has)
            %   newColor - colour to show now
            % Name=Value:
            %   duration  - seconds before the colour is put back. Default 1
            %   postColor - colour to put back. Default: what it was before
            %
            % ONE timer serves every pending flash, made when the first is
            % asked for and deleted when the last has been put back. Each
            % flash used to make, start and delete a timer of its own --
            % about 9 ms a time, paid inside the trial dispatch for every
            % control whose value changed -- and a widget deleted before its
            % timer fired left an "Invalid or deleted object" error behind.
            % A flash asked for again before the first has cleared keeps the
            % ORIGINAL colour to go back to, rather than taking the flash
            % colour for the widget's own.
            arguments
                obj
                newColor
                options.duration (1,1) double = 1 % second
                options.postColor (1,:) = 'default'
            end

            if isempty(obj) || ~isscalar(obj) || ~isvalid(obj)
                return
            end

            if isprop(obj,'BackgroundColor')
                SF = 'BackgroundColor';
            elseif isprop(obj,'Color')
                SF = 'Color';
            elseif isprop(obj,'FontColor')
                SF = 'FontColor';
            else
                return
            end

            gui.Helper.flashQueue_('add', obj, SF, newColor, options.postColor, options.duration);
        end




        % The three below forward to psychophysics.Metrics, which owns the
        % signal-detection arithmetic. They stay because gui.Helper is a
        % mixin that lab BehaviorGUIs outside this repository inherit, and
        % removing a superclass method breaks those silently; the hard-coded
        % [0.01 0.99] bounds are preserved for the same reason. New code
        % should call psychophysics.Metrics directly, where the correction is
        % named rather than implied.

        function d = dprime2AFC(HR)
            d = psychophysics.Metrics.dprime2AFC(HR, Correction="clamp", Bounds=[0.01 0.99]);
        end

        function c = criterion(HR,FR)
            c = psychophysics.Metrics.criterion(HR, FR, Correction="clamp", Bounds=[0.01 0.99]);
        end

        function pc = percent_correct(HR,FR)
            pc = psychophysics.Metrics.percentCorrect(HR, FR);
        end


    end

    methods (Static, Access = private)
        function flashQueue_(cmd, obj, prop, newColor, postColor, duration)
            % flashQueue_('add', obj, prop, newColor, postColor, duration)
            % flashQueue_('tick')
            % The pending flashes behind timed_color_change and the one timer
            % that clears them.
            persistent Q
            if isempty(Q)
                Q = struct('H', {{}}, 'Prop', {{}}, 'Post', {{}}, ...
                    'Start', zeros(1,0,'uint64'), 'Dur', zeros(1,0), 'Timer', []);
            end

            switch cmd
                case 'add'
                    k = 0;
                    for i = 1:numel(Q.H)
                        if Q.H{i} == obj && strcmp(Q.Prop{i}, prop)
                            k = i;
                            break
                        end
                    end
                    if k == 0
                        if isequal(postColor, 'default')
                            postColor = obj.(prop);
                        end
                        k = numel(Q.H) + 1;
                        Q.H{k} = obj;
                        Q.Prop{k} = prop;
                        Q.Post{k} = postColor;
                    elseif ~isequal(postColor, 'default')
                        Q.Post{k} = postColor;
                    end
                    Q.Start(k) = tic;
                    Q.Dur(k) = duration;

                    obj.(prop) = newColor;

                    if isempty(Q.Timer) || ~isvalid(Q.Timer)
                        Q.Timer = timer('Name', 'epsych_FlashTimer', ...
                            'ExecutionMode', 'fixedSpacing', 'Period', 0.1, ...
                            'StartDelay', 0.1, 'BusyMode', 'drop', ...
                            'TimerFcn', @(~,~) gui.Helper.flashQueue_('tick'));
                        start(Q.Timer);
                    end

                case 'tick'
                    keep = true(1, numel(Q.H));
                    for i = 1:numel(Q.H)
                        h = Q.H{i};
                        if ~isvalid(h)
                            keep(i) = false;    % the widget went first
                            continue
                        end
                        if toc(Q.Start(i)) >= Q.Dur(i)
                            try
                                h.(Q.Prop{i}) = Q.Post{i};
                            catch ME
                                vprintf(2, 'gui.Helper: could not restore a flashed colour (%s)', ME.message)
                            end
                            keep(i) = false;
                        end
                    end
                    Q.H = Q.H(keep);
                    Q.Prop = Q.Prop(keep);
                    Q.Post = Q.Post(keep);
                    Q.Start = Q.Start(keep);
                    Q.Dur = Q.Dur(keep);

                    % Nothing left to clear: the timer goes, so a session
                    % that is not flashing anything holds no timer for it.
                    if isempty(Q.H) && ~isempty(Q.Timer)
                        t = Q.Timer;
                        Q.Timer = [];
                        if isvalid(t)
                            stop(t);
                            delete(t);
                        end
                    end
            end
        end
    end
end

