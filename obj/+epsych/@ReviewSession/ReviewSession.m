classdef ReviewSession < handle
    % R = epsych.ReviewSession(datafile)
    % Reopen a finished session in the paradigm's own behavior GUI.
    %
    % A behavior GUI normally exists only while a session runs: RunExpt launches
    % it, its displays fill in from NewTrial/NewData as trials complete, and
    % ep_TimerFcn_Stop deletes the event hub on the way out. This class puts a
    % saved session back through the same door -- a real epsych.Runtime, a real
    % epsych.EventHub, real events -- so every display component works unchanged
    % and shows exactly what it showed when the session ended.
    %
    % What makes that cheap is that the consumers take the WHOLE DATA array out
    % of each payload and recompute from scratch (psychophysics.Psych.update_data,
    % gui.components.ParameterScatter, gui.components.History, gui.components.SessionPerformance all do). So one
    % notify carrying Data(1:k) is worth k notifies, and winding BACK to an
    % earlier trial costs exactly the same as going forward -- there is no
    % replay-from-the-start.
    %
    % Nothing is driven. The interfaces are hw.Replay, which answers every
    % parameter read from the record at the current trial and ignores writes;
    % RUNTIME.ReviewMode suppresses the first-trial dispatch in
    % epsych.Runtime.set.TRIALS; and the session is put into hw.DeviceState.Idle
    % once the window is built, which is what greys out every
    % gui.components.Parameter_Control through the mode listener it already has.
    %
    % Usage
    %   epsych.ReviewSession                     % pick a file
    %   R = epsych.ReviewSession('session.mat')  % open at the last trial
    %   R.seek(42); R.step(-1); R.play(4); R.pause()
    %
    % A file saved before epsych.SessionSnapshot existed carries no protocol.
    % It still opens: gui.BehaviorGUI.addControl skips parameters it cannot
    % resolve, so the data displays work and the control column is simply
    % absent. IsDegraded says so, and the window title says so to the operator.
    % Pass Protocol= to supply the .eprot and get the controls back.
    %
    % Properties
    %   Data      - The session's per-trial records, in chronological order.
    %   Snapshot  - What the file said about the session (epsych.SessionSnapshot).
    %   RUNTIME   - The offline epsych.Runtime the GUI is attached to.
    %   Position  - Trial the review is showing; 0 is before the first.
    %   GUI       - The behavior GUI object, when it returned one.
    %
    % Documentation: documentation/epsych/epsych_ReviewSession.md
    % See also: epsych.SessionSnapshot, hw.Replay, gui.ReviewTransport,
    %           gui.BehaviorGUI

    properties (SetAccess = private)
        DataFile (1,:) char = ''   % File being reviewed
        Data     struct = struct.empty(1,0) % Per-trial records, chronological
        Snapshot (1,1) struct = struct()    % Normalized session description
        RUNTIME                    % epsych.Runtime in ReviewMode
        Interfaces                 % hw.Replay array backing the parameters
        GUI                        % Behavior GUI object, or [] if it returned none
        Transport                  % gui.ReviewTransport, or []
        Position (1,1) double = 0  % Trial being shown; 0 = before the first
        BehaviorGUIName (1,:) char = ''  % What was launched
        SubjectIndex (1,1) double = 1
    end

    properties (Dependent)
        NumTrials   % Trials in the file
        IsDegraded  % True when the file carried no protocol, so there are no controls
    end

    properties (Access = private)
        PlayTimer_ = []             % timer driving play(); one per review
        OwnedFigures_ = []          % figures the behavior GUI opened but did not hand back
        TrialsTemplate_ (1,1) struct = struct() % TRIALS shape, everything but the per-seek fields
    end

    methods
        function obj = ReviewSession(datafile, options)
            % obj = epsych.ReviewSession(datafile, ...)
            %  datafile    - Session .mat, crash-recovery .mat, or .epj journal.
            %                Omitted or empty opens a file picker.
            %  BehaviorGUI - Function/class name to launch. Default: the one the
            %                snapshot names, else the configured session default.
            %  Protocol    - .eprot to take the parameter tree from, for a file
            %                that carries no snapshot.
            %  Transport   - Open the trial scrubber. Default true.
            %  Show        - Open any window at all. False loads headlessly,
            %                which is what the smoke test uses.
            %  SubjectIndex- Which subject of a multi-subject file. Default 1.
            arguments
                datafile (1,:) char = ''
                options.BehaviorGUI (1,:) char = ''
                options.Protocol (1,:) char = ''
                options.Transport (1,1) logical = true
                options.Show (1,1) logical = true
                options.SubjectIndex (1,1) double {mustBeInteger,mustBePositive} = 1
            end

            if isempty(datafile)
                datafile = epsych.ReviewSession.pickFile();
                if isempty(datafile)
                    vprintf(1, 'epsych.ReviewSession: cancelled')
                    if nargout == 0, clear obj; end
                    return
                end
            end

            obj.SubjectIndex = options.SubjectIndex;
            obj.load_(datafile, options.Protocol);

            if isempty(obj.Data)
                error('epsych:ReviewSession:NoTrials', ...
                    'No trial records found in "%s".', datafile)
            end

            obj.buildRuntime_();

            if ~options.Show
                obj.jumpToEnd();
                return
            end

            % Seat the session at its last trial BEFORE the window is built,
            % silently -- there are no listeners yet, and two components read
            % their state at construction rather than waiting for an event:
            % gui.components.Parameter_Control reads its parameter once and then waits for
            % a PostSet a review never fires, so whatever it seats from is what
            % it shows for good; and gui.components.NextTrial.seedFromRuntime_ reads
            % RUNTIME.TRIALS, which without this still has the empty
            % NextTrialID buildRuntime_ left there.
            % (gui.components.Parameter_Monitor and gui.ParameterDebugger poll, so those
            % DO follow the scrubber afterwards.)
            obj.seek(obj.NumTrials, Notify = false);

            obj.launchGUI_(options.BehaviorGUI);

            % After the window exists, not before: gui.components.Parameter_Control greys
            % itself out from a mode PostSet, and AbortSet means a repeated
            % value never fires. buildRuntime_ left the interfaces in Standby
            % so this is a real transition.
            obj.setIdle_();

            obj.jumpToEnd();

            if options.Transport
                obj.Transport = gui.ReviewTransport(obj);
            end

            if nargout == 0, clear obj; end
        end

        function delete(obj)
            % Destructor: stop playback, close the windows this review opened,
            % and drop the runtime. The behavior GUI is deleted before the hub
            % it listens to, so no listener fires into a half-torn-down object.
            vprintf(3, 'epsych.ReviewSession: destructor')

            obj.pause();
            try
                if ~isempty(obj.PlayTimer_) && isvalid(obj.PlayTimer_)
                    delete(obj.PlayTimer_);
                end
            catch
            end

            for h = {obj.Transport, obj.GUI}
                try
                    if ~isempty(h{1}) && isobject(h{1}) && isvalid(h{1})
                        delete(h{1});
                    end
                catch
                end
            end

            try
                f = obj.OwnedFigures_;
                delete(f(isgraphics(f)));
            catch
            end

            try
                if ~isempty(obj.RUNTIME) && isvalid(obj.RUNTIME)
                    if ~isempty(obj.RUNTIME.EVENTS) && isvalid(obj.RUNTIME.EVENTS)
                        delete(obj.RUNTIME.EVENTS);
                    end
                    delete(obj.RUNTIME);
                end
            catch
            end
        end

        function n = get.NumTrials(obj)
            n = numel(obj.Data);
        end

        function tf = get.IsDegraded(obj)
            % No parameters means the file named no protocol, so the paradigm's
            % controls could not be rebuilt.
            tf = isempty(obj.Interfaces);
        end

        seek(obj, k) % Show trial k, firing the events a live session would have.

        function step(obj, n)
            % step(obj, n)
            % Move n trials from here; negative goes back. Clamped at both ends.
            arguments
                obj
                n (1,1) double {mustBeInteger} = 1
            end
            obj.seek(obj.Position + n);
        end

        function jumpToStart(obj)
            % jumpToStart(obj)
            % Before the first trial: no data, and the first trial pending.
            obj.seek(0);
        end

        function jumpToEnd(obj)
            % jumpToEnd(obj)
            % The state the session ended in. This is what opening a review
            % lands on, since "as if it had just been run" is the default
            % question an operator is asking.
            obj.seek(obj.NumTrials);
        end

        play(obj, rate) % Advance through the trials on a timer.

        function pause(obj)
            % pause(obj)
            % Stop playback where it is. Safe to call when not playing.
            try
                if ~isempty(obj.PlayTimer_) && isvalid(obj.PlayTimer_) ...
                        && strcmp(obj.PlayTimer_.Running, 'on')
                    stop(obj.PlayTimer_);
                end
            catch ME
                vprintf(2, 'epsych.ReviewSession: could not stop playback (%s)', ME.message)
            end
        end

        function tf = isPlaying(obj)
            % tf = isPlaying(obj)
            tf = ~isempty(obj.PlayTimer_) && isvalid(obj.PlayTimer_) ...
                && strcmp(obj.PlayTimer_.Running, 'on');
        end

        function t = showTransport(obj)
            % t = showTransport(obj)
            % Open the trial scrubber, or raise the one already open. Closing
            % the transport only closes the transport, so this is how it comes
            % back.
            if ~isempty(obj.Transport) && isvalid(obj.Transport)
                figure(obj.Transport.h_figure);
            else
                obj.Transport = gui.ReviewTransport(obj);
            end
            t = obj.Transport;
            if nargout == 0, clear t; end
        end

        function s = describe(obj)
            % s = describe(obj)
            % One line naming the subject, the trial count and the file, for a
            % window title or a log entry.
            name = '(unknown subject)';
            try
                if ~isempty(obj.Snapshot.Subject)
                    name = char(string(obj.Snapshot.Subject.Name));
                end
            catch
            end

            [~, fn, ext] = fileparts(obj.DataFile);
            s = sprintf('%s — %d trials — %s%s', name, obj.NumTrials, fn, ext);
            if obj.IsDegraded
                s = [s '  [no protocol: data displays only]'];
            end
        end
    end

    methods (Access = private)
        load_(obj, datafile, protocolFile)  % Read the file into Data and Snapshot.
        buildRuntime_(obj)                  % Construct the offline runtime and its replay backends.
        launchGUI_(obj, guiName)            % Resolve and open the behavior GUI.

        function positionBackends_(obj, k)
            % Point every replay backend at trial k, so a parameter read
            % reports what the rig held then. Separate from seek so the
            % constructor can seat the controls before the window exists.
            for p = obj.Interfaces(:).'
                p.Position = max(0, min(k, obj.NumTrials));
            end
        end

        function setIdle_(obj)
            % Put the session in Idle and say so, in the order a real stop uses:
            % the interfaces first, then the broadcast. gui.components.Parameter_Control
            % watches the interface mode; gui.BehaviorGUI stops its registered
            % monitors on the broadcast.
            try
                for p = obj.Interfaces(:).'
                    p.mode = hw.DeviceState.Idle;
                end
            catch ME
                vprintf(2, 'epsych.ReviewSession: could not idle the replay backends (%s)', ME.message)
            end

            try
                obj.RUNTIME.EVENTS.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Idle));
            catch ME
                vprintf(2, 'epsych.ReviewSession: could not broadcast Idle (%s)', ME.message)
            end
        end
    end

    methods (Static)
        function f = pickFile(startPath)
            % f = epsych.ReviewSession.pickFile(startPath)
            % Ask for a session file. Returns '' if cancelled.
            arguments
                startPath (1,:) char = ''
            end

            filter = { ...
                '*.mat;*.epj', 'Session data (*.mat, *.epj)'; ...
                '*.mat',       'Session or recovery file (*.mat)'; ...
                '*.epj',       'Trial journal (*.epj)'; ...
                '*.*',         'All files'};

            if isempty(startPath)
                [fn, pn] = uigetfile(filter, 'Open Session for Review');
            else
                [fn, pn] = uigetfile(filter, 'Open Session for Review', startPath);
            end

            if isequal(fn, 0)
                f = '';
                return
            end
            f = fullfile(pn, fn);
        end
    end
end
