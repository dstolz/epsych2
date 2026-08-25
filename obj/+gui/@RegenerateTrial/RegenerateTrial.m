classdef RegenerateTrial < handle
    % gui.RegenerateTrial
    % A button that re-arms the trial the rig is holding.
    %
    % The pending trial is dispatched again, from the top.
    %
    % One press runs epsych.Runtime.dispatchNextTrial for the box, which is
    % the same call the trial loop makes at every trial boundary -- it fires
    % ResetTrig, writes every per-trial parameter, fires NewTrial, and
    % broadcasts the NewTrial event. Two things therefore change even though
    % the trial row does not: parameters marked isRandom draw again, and
    % Expressions are re-evaluated against whatever the operator has since
    % typed and committed. That is what makes the button useful -- an ITI or
    % a stimulus delay that came out wrong is redrawn, and a parameter edited
    % mid-trial reaches the hardware without waiting for the next trial.
    %
    % ARMING. The button is dead until Ctrl+Alt+Shift are all held down, and
    % goes dead again the moment any of them is released. That is the whole
    % guard: this component assumes the operator knows what they are doing
    % and asks for no confirmation, so what stands between a running animal
    % and a restarted trial is a two-handed gesture no sleeve or stray click
    % can make. The combination is the one gui.Parameter_Update already uses
    % (held while clicking, to commit immediately instead of deferring), so
    % an operator on this rig has met it before. RequireArming=false removes
    % the requirement.
    %
    % *** IT INTERRUPTS THE TRIAL IN PROGRESS. *** There is no way for it to
    % tell a rig sitting in an ITI from one with an animal part way through a
    % response: the reset and the new-trial trigger go out either way.
    % Pressed mid-trial it will restart a response window
    % under the subject, and the DATA record eventually written for that
    % trial carries the parameter values from the LAST dispatch, so the
    % record no longer describes what the subject first heard. The trial
    % counter does not move -- the regenerated trial is still one trial and
    % still one record -- so nothing downstream can see that it happened.
    % Press the button and the session notes are what say so.
    %
    % WHAT IT DELIBERATELY DOES NOT DO. By default it does not re-run the
    % trial selector, only the dispatch. Selecting is where a paradigm's
    % state moves: a staircase steps, a catch hazard climbs, a one-shot
    % request is consumed. Re-running it would silently advance the schedule
    % to redraw a value. Reselect=true asks for that as well, for a paradigm
    % whose selector is where the values are made, and is safe only because
    % every epsych.TrialSelector must already tolerate being called twice for
    % one trial (any control that sets FORCE_TRIAL brings it round again).
    %
    % Never live in a review: epsych.ReviewSession replays a finished session
    % and must not write to hardware.
    %
    % Usage, through gui.BehaviorGUI:
    %
    %   function build(obj, fig)
    %       g = uigridlayout(fig, [2 1]);
    %       obj.addRegenerateTrial(g);
    %   end
    %
    % Standalone, in any container:
    %
    %   h = gui.RegenerateTrial(RUNTIME, panel, SubjectIndex=2);
    %   h.regenerate();     % the button's own callback; refuses unless armed
    %
    % Documentation: documentation/gui/gui_RegenerateTrial.md
    % See also gui.BehaviorGUI, epsych.Runtime, epsych.TrialSelector

    properties (SetAccess = private)
        ButtonH = []            % the uibutton

        % How many times the trial has been regenerated this session. A
        % session that needed it a dozen times is worth knowing about when
        % the data is read back.
        Count (1,1) double = 0

        % True while Ctrl+Alt+Shift are all held. The button is dead
        % otherwise, so the gesture is a deliberate two-handed act rather
        % than something a sleeve can do.
        Armed (1,1) logical = false
    end

    properties
        % Which box to regenerate. One button drives one subject; a
        % multi-box rig wants one per box.
        SubjectIndex (1,1) double {mustBeInteger, mustBePositive} = 1

        % Re-run the trial selector before dispatching, rather than
        % re-dispatching the row it already chose. Off by default: see the
        % class comment.
        Reselect (1,1) logical = false

        % Record each regeneration in the session notes, so the data file
        % says which trials were interfered with. On by default -- it is the
        % only trace the trial record keeps.
        Note (1,1) logical = true

        % Leave the button live outside a run. Off by default: dispatching
        % over a stopped rig writes parameters nothing is going to read, and
        % before the first trial there is no selected trial to dispatch.
        EnableWhenIdle (1,1) logical = false

        % Require the Ctrl+Alt+Shift hold. On by default. Turning it off
        % leaves an ordinary button that regenerates on a single click --
        % reasonable for a rig where the operator is the only one at the
        % keyboard, and exactly the mis-click the arming exists to prevent
        % everywhere else.
        RequireArming (1,1) logical = true
    end

    events
        % Fired after a successful regeneration, for a paradigm that has to
        % do something of its own (stamp a plot, mark the trial in a table).
        TrialRegenerated

        % Fired when the Ctrl+Alt+Shift hold is taken up or let go.
        ArmedStateChanged
    end

    properties (Access = private)
        RUNTIME_ = []
        Listener_ event.listener
        ReviewMode_ (1,1) logical = false
        Mode_ = hw.DeviceState.Idle

        % The gui.KeyBindings supplying the modifier state, and whether
        % this component resolved it itself (getOrCreate on the figure)
        % rather than being handed one. Only a self-resolved source is
        % re-claimed on ModeChange; a KeySource handed in belongs to
        % whoever supplied it.
        KeySource_ = []
        OwnsKeySource_ (1,1) logical = false
        ModifierListener_ event.listener

        ArmedColor_ (1,3) double = [0.96 0.78 0.36]
        DisarmedColor_ (1,3) double = [0.90 0.87 0.80]
    end

    properties (Constant)
        % The modifiers that arm the button. Ctrl+Alt+Shift is not an
        % arbitrary choice: gui.Parameter_Update already uses exactly this
        % combination held-while-clicking to mean "do it now, skip the
        % deferral", so an operator on this rig has met it before.
        ARM_MODIFIERS = {'control','alt','shift'}

        % Said in full on the button the operator is about to press, because
        % this is the one component whose whole risk is invisible from the
        % label.
        DEFAULT_TOOLTIP = ['Hold Ctrl+Alt+Shift to enable, then click: dispatches the ' ...
            'pending trial again, redrawing randomized parameters and re-applying ' ...
            'committed edits. WARNING: this interrupts a trial in progress and asks ' ...
            'no questions first.']
    end

    methods (Static)
        function s = getComponentSpec()
            % s = gui.RegenerateTrial.getComponentSpec()
            % KeySource is injected so this button joins the figure's one
            % gui.KeyBindings rather than claiming the key callbacks itself:
            % two hook-chaining components on one figure could chain each
            % other and recurse.
            %
            % No default chord ON PURPOSE -- holding the three modifiers IS
            % the gesture, and a chord that fired it outright would undo the
            % arming. See gui.ComponentSpec.
            s = gui.ComponentSpec();
            s.type             = 'RegenerateTrial';
            s.label            = 'Regenerate Trial';
            s.category         = 'Add-ons';
            s.description      = 'Re-arm the trial the rig is holding';
            s.shape            = ["runtime","parent"];
            s.inject.KeySource = "keys";
            s.placeable        = false; % deliberately off the builder palette
            s.options          = [ ...
                gui.ComponentSpecOption('name','Text','inputType','text','defaultValue','Regenerate Trial'), ...
                gui.ComponentSpecOption('name','SubjectIndex','inputType','numeric','defaultValue',1), ...
                gui.ComponentSpecOption('name','Reselect','inputType','logical','defaultValue',false)];
        end
    end

    methods

        function obj = RegenerateTrial(RUNTIME, parent, options)
            % obj = gui.RegenerateTrial(RUNTIME, parent, ...)
            % Create the button inside a container.
            %
            % Parameters:
            %   RUNTIME   - epsych.Runtime whose trial is regenerated.
            %   parent    - any UI container (uifigure, uipanel, grid cell).
            %   Text      - button label (default 'Regenerate Trial').
            %   Tooltip   - hover text. Empty keeps the warning default.
            %   SubjectIndex, Reselect, Note, EnableWhenIdle - see the
            %               properties of the same name.
            %   ShowIcon  - draw the circular-arrow glyph (default true).
            %   FontSize, FontWeight, BackgroundColor - appearance. The
            %               default is amber rather than the neutral grey of
            %               the buttons it sits beside, because an operator
            %               reaching for a trigger should not land on this.
            arguments
                RUNTIME
                parent (1,1)
                options.Text (1,:) char = 'Regenerate Trial'
                options.Tooltip (1,:) char = ''
                options.SubjectIndex (1,1) double {mustBeInteger, mustBePositive} = 1
                options.Reselect (1,1) logical = false
                options.Note (1,1) logical = true
                options.EnableWhenIdle (1,1) logical = false
                options.RequireArming (1,1) logical = true
                options.ShowIcon (1,1) logical = true
                options.FontSize (1,1) double {mustBePositive, mustBeFinite} = 12
                options.FontWeight (1,:) char {mustBeMember(options.FontWeight,{'normal','bold'})} = 'normal'
                options.BackgroundColor (1,3) double {mustBeNonnegative} = [0.96 0.78 0.36]
                options.KeySource = []
            end

            obj.SubjectIndex   = options.SubjectIndex;
            obj.Reselect       = options.Reselect;
            obj.Note           = options.Note;
            obj.EnableWhenIdle = options.EnableWhenIdle;
            obj.RequireArming  = options.RequireArming;
            obj.ArmedColor_    = options.BackgroundColor;
            % Washed out toward the window's own grey, so an unarmed button
            % reads as "not available yet" rather than as broken.
            obj.DisarmedColor_ = 1 - 0.45*(1 - options.BackgroundColor);

            tooltip = options.Tooltip;
            if isempty(tooltip), tooltip = gui.RegenerateTrial.DEFAULT_TOOLTIP; end

            obj.ButtonH = uibutton(parent, ...
                'Text',            options.Text, ...
                'Tooltip',         tooltip, ...
                'FontSize',        options.FontSize, ...
                'FontWeight',      options.FontWeight, ...
                'BackgroundColor', options.BackgroundColor, ...
                'ButtonPushedFcn', @(~,~) obj.regenerate());

            if options.ShowIcon
                obj.ButtonH.Icon = gui.toolbarIcon("refresh");
            end

            % Inside a behavior GUI the modifier state comes from the one
            % object that owns the figure's key callbacks. Standalone, the
            % component joins (or starts) the figure's shared
            % gui.KeyBindings rather than claiming the key-callback slot
            % itself: two components that each claimed and chained the slot
            % could chain each other, and every stray keystroke then
            % recursed to MATLAB's recursion limit.
            ks = options.KeySource;
            if isempty(ks)
                fig = ancestor(obj.ButtonH, 'figure');
                if ~isempty(fig) && isvalid(fig)
                    ks = gui.KeyBindings.getOrCreate(fig);
                    obj.OwnsKeySource_ = true;
                end
            end
            if ~isempty(ks)
                obj.KeySource_ = ks;
                obj.ModifierListener_ = listener(ks, 'ModifiersChanged', ...
                    @(src,~) obj.setArmed_(src.CurrentModifiers));
            end

            obj.attachRuntime(RUNTIME);
        end

        function delete(obj)
            delete(obj.Listener_)
            delete(obj.ModifierListener_)
        end

        function attachRuntime(obj, RUNTIME)
            % attachRuntime(obj, RUNTIME)
            % Bind the button to a session and follow its run mode, so the
            % button is live only while trials are actually going. Replaces
            % any previously attached listener.
            %
            % The mode is followed rather than read: gui.BehaviorGUI is
            % built from the PsychTimer's StartFcn, BEFORE RunExpt
            % broadcasts the run mode, so a button that seated itself at
            % construction would seat itself as Idle and stay there.
            arguments
                obj
                RUNTIME
            end

            delete(obj.Listener_)
            obj.RUNTIME_ = RUNTIME;

            if ~isa(RUNTIME, 'epsych.Runtime') || ~isvalid(RUNTIME)
                vprintf(2, 'gui.RegenerateTrial: no session supplied; the button is inert')
                obj.applyEnable_();
                return
            end

            obj.ReviewMode_ = RUNTIME.ReviewMode;
            obj.Listener_ = listener(RUNTIME.EVENTS, 'ModeChange', ...
                @(~,ev) obj.onModeChange_(ev));
            obj.applyEnable_();
        end

        function tf = regenerate(obj)
            % tf = regenerate(obj)
            % Dispatch the pending trial again, returning whether it went
            % out. This is the button's own callback; calling it by hand is
            % how a script or a keyboard shortcut regenerates.
            %
            % Everything that would stop it -- no session, no trial selected
            % yet, a review -- is logged and returns false rather than
            % throwing: this runs from a button callback beside a live
            % experiment.
            tf = false;
            if ~obj.canRegenerate_(), return; end

            R = obj.RUNTIME_;
            i = obj.SubjectIndex;
            fromID   = R.TRIALS(i).NextTrialID;
            trialIdx = R.TRIALS(i).TrialIndex;

            if obj.Reselect
                try
                    R.TRIALS(i).NextTrialID = R.TRIALS(i).selector.selectNext(R.TRIALS(i));
                catch ME
                    vprintf(0, 1, ME);
                    vprintf(0, 1, ['gui.RegenerateTrial: re-selection failed for box %d; ' ...
                        'the trial was left as it was'], i);
                    return
                end
            end

            try
                R.dispatchNextTrial(i);
            catch ME
                % A dispatch that throws part way has already fired ResetTrig
                % and written some parameters, so the box is in neither the
                % old trial nor the new one. Say so rather than reporting a
                % clean failure.
                vprintf(0, 1, ME);
                vprintf(0, 1, ['gui.RegenerateTrial: dispatch failed part way for box %d; ' ...
                    'the hardware may be holding a partly written trial'], i);
                return
            end

            toID = R.TRIALS(i).NextTrialID;
            obj.Count = obj.Count + 1;
            tf = true;

            % Level 1, not debug: this is an operator intervention that
            % changes what a trial record means, and the log is where anyone
            % reading the session back will look for it.
            if toID == fromID
                what = sprintf('trial %d (row %d)', trialIdx, toID);
            else
                what = sprintf('trial %d (row %d -> %d)', trialIdx, fromID, toID);
            end
            vprintf(1, 'gui.RegenerateTrial: operator regenerated %s on box %d', what, i);

            obj.addNote_(what);
            notify(obj, 'TrialRegenerated');
        end

        function set.EnableWhenIdle(obj, value)
            obj.EnableWhenIdle = value;
            obj.applyEnable_();
        end
    end

    methods (Access = private)

        function onModeChange_(obj, ev)
            obj.Mode_ = ev.NewMode;
            % Re-assert the shared KeyBindings' claim on the figure here as
            % well as at construction, for a component that resolved its own
            % KeySource: a neighbour built after this one may have assigned
            % the figure's key callbacks outright, and RunExpt broadcasts
            % the run mode only after the whole GUI is built, which makes
            % this the first moment every component has had its turn.
            % claimFigure chains what it finds, so that neighbour keeps
            % working. A KeySource handed in belongs to whoever supplied it
            % (gui.BehaviorGUI re-claims after build itself).
            if obj.OwnsKeySource_ && ~isempty(obj.KeySource_) && isvalid(obj.KeySource_)
                obj.KeySource_.claimFigure();
            end
            obj.applyEnable_();
        end

        function setArmed_(obj, mods)
            tf = all(ismember(gui.RegenerateTrial.ARM_MODIFIERS, mods));
            if tf == obj.Armed, return; end     % repaint only on a change
            obj.Armed = tf;
            obj.applyEnable_();
            notify(obj, 'ArmedStateChanged');
        end

        function applyEnable_(obj)
            % Live only during a run, and never in a review. Preview is
            % tested alongside Record because it is a distinct
            % hw.DeviceState and is not isIdle: a preview dispatches trials
            % like any other run.
            if isempty(obj.ButtonH) || ~isvalid(obj.ButtonH), return; end

            live = obj.EnableWhenIdle || ...
                any(obj.Mode_ == [hw.DeviceState.Preview, hw.DeviceState.Record]);
            if obj.RequireArming && ~obj.Armed, live = false; end
            if obj.ReviewMode_, live = false; end

            if live
                obj.ButtonH.Enable = 'on';
            else
                obj.ButtonH.Enable = 'off';
            end

            if obj.Armed || ~obj.RequireArming
                obj.ButtonH.BackgroundColor = obj.ArmedColor_;
            else
                obj.ButtonH.BackgroundColor = obj.DisarmedColor_;
            end
        end

        function tf = canRegenerate_(obj)
            tf = false;
            R = obj.RUNTIME_;

            if obj.ReviewMode_
                vprintf(1, ['gui.RegenerateTrial: ignored -- a review replays a finished ' ...
                    'session and must not write to hardware'])
                return
            end
            % Re-checked here and not only on the button's Enable state: the
            % button is one way in, and a script, a keyboard shortcut, or a
            % neighbour that stole the key callbacks (leaving the enable
            % state stale) are others. The gate has to fail closed.
            if obj.RequireArming && ~obj.Armed
                vprintf(1, ['gui.RegenerateTrial: ignored -- hold Ctrl+Alt+Shift to arm ' ...
                    'before regenerating a trial'])
                return
            end
            if ~isa(R, 'epsych.Runtime') || ~isvalid(R)
                vprintf(1, 'gui.RegenerateTrial: no session to regenerate a trial for')
                return
            end
            if isempty(R.TRIALS)
                vprintf(1, 'gui.RegenerateTrial: the session has no compiled trials')
                return
            end
            if numel(R.TRIALS) < obj.SubjectIndex
                vprintf(1, 'gui.RegenerateTrial: box %d is not in this session (%d running)', ...
                    obj.SubjectIndex, numel(R.TRIALS))
                return
            end
            if isempty(R.TRIALS(obj.SubjectIndex).NextTrialID)
                vprintf(1, ['gui.RegenerateTrial: box %d has no trial selected yet; ' ...
                    'there is nothing to regenerate'], obj.SubjectIndex)
                return
            end

            tf = true;
        end

        function addNote_(obj, what)
            % The regenerated trial writes one DATA record like any other, so
            % the note is the only place the intervention survives into the
            % data file. Tagged with the subject, so on a multi-box rig it
            % lands in the file of the animal it happened to.
            if ~obj.Note, return; end

            notes = obj.RUNTIME_.NOTES;
            if isempty(notes) || ~isvalid(notes), return; end

            notes.add(sprintf('Operator regenerated %s', what), Subject = obj.SubjectIndex);
        end
    end
end
