classdef SessionGate < handle
    %SESSIONGATE Hold a session at a "Begin Experiment" button.
    %   gui.SessionGate is the arming control for a rig that must not start
    %   dispatching trials the moment the session does: the syringe line has
    %   to be purged, the animal placed, the headstage seated. The window
    %   opens with the button live, the session waits, and one press releases
    %   it.
    %
    %   The button is pressed once and never again, so it does not stay on
    %   screen as a dead control: releasing RETIRES it into a status line
    %   ("Experiment Running", "Preview Running", "Session Complete") in the
    %   space it already occupies. An operator glancing at the window can
    %   therefore always tell which of the three a session is in, which a
    %   button that merely greyed out could not say.
    %
    %   Typical use is through gui.BehaviorGUI, which owns both halves --
    %   the button belongs in build, the wait belongs after the base
    %   constructor has returned and the window exists to be clicked:
    %
    %       function obj = MyGUI(RUNTIME, options)
    %           arguments
    %               RUNTIME (1,1)
    %               options.WaitForBegin (1,1) logical = true
    %           end
    %           obj@gui.BehaviorGUI(RUNTIME, Name='My Task');
    %           if options.WaitForBegin, obj.waitForSessionGate(); end
    %       end
    %       function build(obj, fig)
    %           g = uigridlayout(fig, [2 1]);
    %           obj.addSessionGate(g);
    %           ...
    %       end
    %
    %   WHY BLOCKING WORKS. epsych.RunExpt builds the behavior GUI from the
    %   PsychTimer's StartFcn; start() does not return until that callback
    %   does, and a MATLAB timer will not fire its TimerFcn during another of
    %   its own callbacks. Blocking in the constructor therefore holds the
    %   whole trial loop, without the runtime needing to know a gate exists.
    %
    %   The wait pauses rather than spins, so every other component keeps
    %   working while it holds -- the pump panel's readout timer, its port
    %   picker, and the manual prime controls are most of what the operator
    %   is doing during the hold.
    %
    %   NEVER IN A REVIEW. There is no session to hold open in
    %   epsych.ReviewSession, and blocking would hang it inside feval with a
    %   half-built window and no reachable button. gui.BehaviorGUI's
    %   waitForSessionGate returns immediately in ReviewMode; a caller
    %   driving this class directly must make the same check.
    %
    % Documentation: documentation/gui/gui_SessionGate.md
    % See also gui.BehaviorGUI, gui.ModeIndicator, epsych.RunExpt

    properties (SetAccess = private)
        % True once the session has been released, by a press, by a script
        % calling release, or by a run mode arriving that says trials are
        % already going.
        Released (1,1) logical = false

        ButtonH = []    % the uibutton, retired into a status line on release
    end

    properties
        % Text the button carries once released. Record and Preview are
        % distinct hw.DeviceStates and are worth telling apart: an operator
        % who cannot see that a run is a preview will believe data is being
        % saved.
        RunningText  (1,:) char = 'Experiment Running'
        PreviewText  (1,:) char = 'Preview Running'
        CompleteText (1,:) char = 'Session Complete'
    end

    properties (Access = private)
        Listener_ event.listener % ModeChange listener from attachRuntime
    end

    properties (Constant, Access = private)
        RETIRED_COLOR = [0.90 0.90 0.90]
    end

    events
        % Fired once, when the gate opens. A host GUI that has to do
        % something at the true start of a session (arm a rig timer, stamp a
        % note) listens for this rather than polling Released.
        GateOpened
    end

    methods (Static)
        function s = getComponentSpec()
            % s = gui.SessionGate.getComponentSpec()
            % No default key chord ON PURPOSE: this button starts a session,
            % which is not something a stray keystroke over the wrong window
            % should be able to do. See gui.ComponentSpec.
            s = gui.ComponentSpec();
            s.type          = 'SessionGate';
            s.label         = 'Session Gate';
            s.category      = 'Add-ons';
            s.description   = 'Begin Experiment button; the session holds until the operator presses it';
            s.shape         = "parent";
            s.attachRuntime = true;
            s.options       = [ ...
                gui.ComponentSpecOption('name','Text','inputType','text','defaultValue','Begin Experiment'), ...
                gui.ComponentSpecOption('name','Tooltip','inputType','text'), ...
                gui.ComponentSpecOption('name','FontSize','inputType','numeric','defaultValue',14)];
        end
    end

    methods
        function obj = SessionGate(parent, options)
            % obj = gui.SessionGate(parent, Name=Value)
            % Create the Begin Experiment button inside a container.
            %
            % Parameters:
            %   parent        - any UI container (uifigure, uipanel, grid cell).
            %   Text          - button label (default 'Begin Experiment').
            %   RunningText, PreviewText, CompleteText - the retired labels.
            %   Tooltip       - hover text.
            %   FontSize      - label font size (default 14).
            %   FontWeight    - 'bold' (default) or 'normal'.
            %   BackgroundColor - button color while it is still live.
            arguments
                parent (1,1)
                options.Text (1,:) char = 'Begin Experiment'
                options.RunningText (1,:) char = 'Experiment Running'
                options.PreviewText (1,:) char = 'Preview Running'
                options.CompleteText (1,:) char = 'Session Complete'
                options.Tooltip (1,:) char = 'Start the session; no trial runs until this is pressed'
                options.FontSize (1,1) double {mustBePositive, mustBeFinite} = 14
                options.FontWeight (1,:) char {mustBeMember(options.FontWeight,{'normal','bold'})} = 'bold'
                options.BackgroundColor (1,3) double {mustBeNonnegative} = [0.45 0.75 0.45]
            end

            obj.RunningText  = options.RunningText;
            obj.PreviewText  = options.PreviewText;
            obj.CompleteText = options.CompleteText;

            obj.ButtonH = uibutton(parent, ...
                'Text', options.Text, ...
                'FontSize', options.FontSize, ...
                'FontWeight', options.FontWeight, ...
                'BackgroundColor', options.BackgroundColor, ...
                'Tooltip', options.Tooltip, ...
                'ButtonPushedFcn', @(~,~) obj.release());
        end

        function delete(obj)
            delete(obj.Listener_)
        end

        function attachRuntime(obj, RUNTIME)
            % attachRuntime(obj, RUNTIME)
            % Watch the session's run mode so the button never stands there
            % live over a session that is already running, and reads
            % "Session Complete" once one has finished. Replaces any
            % previously attached listener.
            %
            % A gate normally opens by being pressed, and this listener only
            % catches up with what the press already did. It matters for the
            % other route: a caller that skipped the wait (a script, a
            % headless test) leaves an armed button in front of a running
            % trial loop.
            arguments
                obj
                RUNTIME % epsych.Runtime
            end
            delete(obj.Listener_)
            obj.Listener_ = listener(RUNTIME.EVENTS, 'ModeChange', ...
                @(~,ev) obj.onModeChange_(ev));
        end

        function release(obj)
            % release(obj)
            % Open the gate. This is the button's own callback; calling it by
            % hand is how a script starts a run without a click. Releasing an
            % already-open gate does nothing, so the GateOpened event fires at
            % most once.
            if obj.Released, return; end
            obj.Released = true;
            obj.retire_(obj.RunningText);
            vprintf(1, 'gui.SessionGate: operator began the experiment')
            notify(obj, 'GateOpened')
        end

        function tf = wait(obj, timeout)
            % tf = wait(obj, timeout)
            % Block until the gate opens, returning whether it did. Closing
            % the window is the operator's way of calling the run off and
            % returns false.
            %  timeout - seconds to wait. Default Inf.
            arguments
                obj
                timeout (1,1) double {mustBePositive} = Inf
            end
            if obj.Released, tf = true; return; end

            % RunExpt has already painted "Starting..." by now, so say why
            % nothing is happening.
            vprintf(0, 'Holding: press "%s" to start the session.', obj.buttonText_())
            t = tic;
            % isvalid first on every pass: closing the window deletes obj out
            % from under this loop.
            while isvalid(obj) && ~obj.Released && toc(t) < timeout
                pause(0.05)
                drawnow limitrate
            end
            tf = isvalid(obj) && obj.Released;
        end
    end

    methods (Access = private)
        function onModeChange_(obj, ev)
            % Preview is tested alongside Record because it is a DISTINCT
            % hw.DeviceState (RunExpt.PsychTimerStart picks it from
            % RUNTIME.isTest) and is not isIdle: matching only Record leaves
            % the button live and inert through every preview run.
            switch ev.NewMode
                case hw.DeviceState.Record
                    obj.Released = true;
                    obj.retire_(obj.RunningText);
                case hw.DeviceState.Preview
                    obj.Released = true;
                    obj.retire_(obj.PreviewText);
                otherwise
                    if ev.NewMode.isIdle() && obj.Released
                        % Only once something ran: an idle mode arriving
                        % before the gate opens is the session waiting, not a
                        % session that finished.
                        obj.retire_(obj.CompleteText);
                    end
            end
        end

        function retire_(obj, text)
            % The gate opens once and never closes, so the button spends the
            % rest of the session as a status line.
            if isempty(obj.ButtonH) || ~isvalid(obj.ButtonH), return; end
            obj.ButtonH.Text = text;
            obj.ButtonH.Enable = 'off';
            obj.ButtonH.BackgroundColor = obj.RETIRED_COLOR;
        end

        function t = buttonText_(obj)
            t = 'Begin Experiment';
            if ~isempty(obj.ButtonH) && isvalid(obj.ButtonH)
                t = obj.ButtonH.Text;
            end
        end
    end
end
