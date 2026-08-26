classdef ComponentToolbarBehaviorGUI < gui.BehaviorGUI
    % gui.BehaviorGUI subclass exercised by tmp/smoke_test_component_toolbar.m.
    % Registers two poppable components -- one anonymously, one under a
    % register name -- and declares two lazy entries, so the test can check
    % automatic discovery, labelling, lazy construction and the icon fallback
    % against one GUI. RestorePopOuts is forwarded so
    % tmp/smoke_test_popout_restore.m can exercise the layout memory over
    % both kinds of window against the same fixture.
    %
    % Toolbar options reach build through a static holder because build runs
    % inside the superclass constructor, before a subclass can set any
    % property. A real paradigm just writes its choice into the build call.

    properties
        Toolbar         % gui.components.ComponentToolbar under test
        Scatter         % registered with no name -> label from the class
        Upcoming        % registered as 'Upcoming'  -> label from the name
        LazyCalls (1,1) double = 0 % times the Performance factory has run
    end

    methods
        function obj = ComponentToolbarBehaviorGUI(RUNTIME, options)
            arguments
                RUNTIME
                options.Style (1,1) string = "push"
                options.Exclude (1,:) string = string.empty(1,0)
                options.AutoDiscover (1,1) logical = true
                options.PreferenceTag (1,:) char = 'smokeCT_GUI'
                options.RestorePopOuts (1,1) logical = false
            end
            ComponentToolbarBehaviorGUI.pendingOptions(options);
            obj@gui.BehaviorGUI(RUNTIME, Name='Component Toolbar GUI', ...
                PreferenceTag=options.PreferenceTag, ...
                RestorePopOuts=options.RestorePopOuts, ...
                DefaultPosition=[100 100 700 450], Visible=false);
            if nargout == 0, clear obj; end
        end
    end

    methods (Static)
        function s = pendingOptions(s_in)
            % Options for the next instance, read by build.
            persistent S
            if nargin, S = s_in; end
            if isempty(S)
                S = struct('Style',"push",'Exclude',string.empty(1,0),'AutoDiscover',true);
            end
            s = S;
        end
    end

    methods (Access = protected)
        function p = createPsych(obj, R)
            % A plotted Staircase is a display too, but it is this hook's
            % return value rather than something build registers, so it tests
            % the one discovery path the registry cannot cover.
            p = [];
            if isfield(obj.P, 'SmokeLevel')
                p = psychophysics.Staircase(R, obj.P.SmokeLevel);
            end
        end

        function build(obj, fig)
            o = ComponentToolbarBehaviorGUI.pendingOptions();

            % Asked for FIRST, before anything is registered: the point of
            % deferred discovery is that this still lists what follows.
            obj.Toolbar = obj.add('gui.components.ComponentToolbar', fig, Style=o.Style, ...
                Exclude=o.Exclude, AutoDiscover=o.AutoDiscover);

            obj.Toolbar.addLazyComponent('Performance', ...
                @(c) obj.makePerformance_(c), ...
                Icon='sessionperformance', WindowSize=[420 260]);

            % No glyph of this name exists: the generic one must stand in
            % rather than the tool failing to appear.
            obj.Toolbar.addLazyComponent('Mystery', ...
                @(c) gui.components.NextTrial(obj.RUNTIME, c, Fields="SmokeFreq", ...
                    PreferenceTag='smokeCT_mystery'), ...
                Icon='nosuchglyph');

            g = uigridlayout(fig, [2 1]);
            g.RowHeight = {'1x','1x'};

            p1 = uipanel(g);
            obj.Scatter = obj.register(gui.components.ParameterScatter(obj.RUNTIME, p1, ...
                PreferenceTag='smokeCT_scatter'));

            p2 = uipanel(g);
            obj.Upcoming = obj.register(gui.components.NextTrial(obj.RUNTIME, p2, ...
                Fields="SmokeFreq", PreferenceTag='smokeCT_next'), 'Upcoming');
        end
    end

    methods (Access = private)
        function h = makePerformance_(obj, container)
            obj.LazyCalls = obj.LazyCalls + 1;
            h = gui.components.SessionPerformance(obj.RUNTIME, container, ...
                PreferenceTag='smokeCT_perf');
        end
    end
end
