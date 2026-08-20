classdef ReviewTransport < handle
    % T = gui.ReviewTransport(review)
    % Trial scrubber for an epsych.ReviewSession.
    %
    % A window of its own rather than a strip added to the behavior GUI: that
    % layout belongs to the paradigm's build method, and gui.BehaviorGUI offers
    % no seam for inserting into it. Keeping the transport separate also means a
    % paradigm needs to know nothing about review to be reviewable.
    %
    % Two controls sit apart from the transport itself, at the right:
    %
    %   camera  - copies a picture of the BEHAVIOR GUI to the clipboard, not of
    %             this window. A picture of a scrubber is of no use in a
    %             notebook, and the reason the transport lives in a window of
    %             its own is to stay out of the paradigm's layout -- which
    %             means staying out of its screenshots too. Same
    %             gui.ScreenCapture a behavior GUI would add for itself, just
    %             aimed elsewhere.
    %   On Top  - pins the window above other applications, so a review stays
    %             readable while the operator works in a notebook or a
    %             spreadsheet. The state is remembered per window through
    %             gui.PopOut, and the button reports what actually happened
    %             rather than what was asked: a platform that will not honour
    %             WindowStyle leaves the window unpinned and the button pops
    %             back out.
    %
    % Closing it closes only the transport; the review and its behavior GUI
    % carry on, and R.showTransport() brings it back. Closing the BEHAVIOR GUI,
    % on the other hand, takes the transport with it: there is nothing left to
    % scrub.
    %
    % Usage
    %   R = epsych.ReviewSession('session.mat');   % opens one automatically
    %   T = gui.ReviewTransport(R);                % or make one by hand
    %
    % See also: epsych.ReviewSession, gui.PopOut

    properties (SetAccess = private)
        Review          % epsych.ReviewSession being driven
        h_figure        % The transport window
    end

    properties (Constant, Hidden)
        PREFERENCE_TAG = 'gui_ReviewTransport'
        DEFAULT_SIZE = [760 148]
    end

    properties (Access = private)
        Slider_    = []
        TrialLabel_ = []
        TimeLabel_ = []
        PlayButton_ = []
        RateField_ = []
        Buttons_ = []
        Capture_ = []               % gui.ScreenCapture aimed at the behavior GUI
        OnTopButton_ = []           % Always-on-top state button
        GUIWatcher_ = []   % listener closing this window when the GUI goes
        Refreshing_ (1,1) logical = false % suppresses the slider callback while we set it
    end

    methods
        function obj = ReviewTransport(review)
            % obj = gui.ReviewTransport(review)
            %  review - epsych.ReviewSession to drive.
            arguments
                review (1,1) epsych.ReviewSession
            end

            obj.Review = review;

            obj.closeExistingInstance_();

            fig = uifigure( ...
                'Tag',             obj.PREFERENCE_TAG, ...
                'Name',            sprintf('Session Review — %s', review.describe()), ...
                'CloseRequestFcn', @(src,~) obj.onClose_(src), ...
                'Resize',          'on', ...
                'UserData',        obj);
            fig.Position = obj.startPosition_();
            movegui(fig, 'onscreen');
            obj.h_figure = fig;

            % Before the contents, as gui.PopOut.popOut does: it restores the
            % pinned state onto the figure.
            gui.PopOut.markStandaloneWindow(fig, obj.PREFERENCE_TAG);

            % The transport window keeps the review alive too, so a review
            % whose behavior GUI opened no window of its own still survives its
            % constructor returning (see epsych.ReviewSession.launchGUI_).
            setappdata(fig, 'epsych_ReviewSession', review);

            obj.build_(fig);
            obj.watchBehaviorGUI_();
            obj.refresh();

            if nargout == 0, clear obj; end
        end

        function delete(obj)
            vprintf(3, 'gui.ReviewTransport: destructor')
            try
                if ~isempty(obj.GUIWatcher_) && isvalid(obj.GUIWatcher_)
                    delete(obj.GUIWatcher_);
                end
            catch
            end

            % Explicitly, before the figure goes: gui.ScreenCapture owns a
            % one-shot confirmation timer that deleting the graphics alone
            % would leave running.
            try
                if ~isempty(obj.Capture_) && isvalid(obj.Capture_)
                    delete(obj.Capture_);
                end
            catch
            end
            try
                if ~isempty(obj.h_figure) && isvalid(obj.h_figure)
                    obj.savePosition_();
                    obj.h_figure.CloseRequestFcn = '';
                    delete(obj.h_figure);
                end
            catch
            end
        end

        function refresh(obj)
            % refresh(obj)
            % Redraw from the review's current position. Called for you after
            % every seek, including seeks made from code or from playback, so
            % the slider never disagrees with what the displays show.
            if ~isvalid(obj) || isempty(obj.h_figure) || ~isvalid(obj.h_figure), return; end

            R = obj.Review;
            if isempty(R) || ~isvalid(R), return; end

            obj.Refreshing_ = true;
            restoreFlag = onCleanup(@() obj.clearRefreshing_());

            try
                k = R.Position;
                n = R.NumTrials;

                obj.Slider_.Value = min(max(k, obj.Slider_.Limits(1)), obj.Slider_.Limits(2));

                if k == 0
                    obj.TrialLabel_.Text = sprintf('Before trial 1  of %d', n);
                else
                    obj.TrialLabel_.Text = sprintf('Trial %d  of %d', k, n);
                end

                obj.TimeLabel_.Text = obj.timestampText_(k);

                if R.isPlaying()
                    obj.PlayButton_.Text = 'Pause';
                    obj.PlayButton_.Tooltip = 'Stop playback';
                else
                    obj.PlayButton_.Text = 'Play';
                    obj.PlayButton_.Tooltip = 'Play through the trials';
                end
            catch ME
                vprintf(2, 'gui.ReviewTransport: refresh failed (%s)', ME.message)
            end
        end
    end

    methods (Access = private)
        function build_(obj, fig)
            g = uigridlayout(fig, [2 1]);
            % A uislider needs room for its track AND the tick labels hanging
            % below it. At the 32 px an ordinary control gets, those labels ran
            % straight into the button row underneath.
            g.RowHeight = {56, 38};
            g.ColumnWidth = {'1x'};
            g.Padding = [10 10 10 8];
            g.RowSpacing = 6;

            n = max(1, obj.Review.NumTrials);

            % Ticks spanning 0..n rather than 0 plus a run starting at 1: the
            % latter puts "0" and "1" on top of each other at the left end,
            % which is where the label that matters least is.
            obj.Slider_ = uislider(g, ...
                'Limits',          [0 n], ...
                'MajorTicks',      unique(round(linspace(0, n, min(n + 1, 6)))), ...
                'MinorTicks',      [], ...
                'Tooltip',         'Drag to any trial', ...
                'ValueChangedFcn', @(src,~) obj.onSlider_(src));
            obj.Slider_.Layout.Row = 1;

            % Deliberately ValueChanged, not ValueChanging: a seek re-notifies
            % every display, and each one recomputes the whole session from the
            % DATA array. Scrubbing live would recompute on every pixel of
            % drag, which on a long session is slower than it is useful.

            row = uigridlayout(g, [1 10]);
            row.Layout.Row = 2;
            %  |<   <   Play  >   >|   trial-label  rate  elapsed  camera  on-top
            row.ColumnWidth = {38, 38, 66, 38, 38, '1x', 60, 116, 34, 74};
            row.Padding = [0 0 0 0];
            row.ColumnSpacing = 5;

            obj.Buttons_ = [ ...
                obj.button_(row, '|<', 'First trial',    @(~,~) obj.Review.jumpToStart()), ...
                obj.button_(row, '<',  'Previous trial', @(~,~) obj.stepAndRefresh_(-1))];

            obj.PlayButton_ = obj.button_(row, 'Play', 'Play through the trials', ...
                @(~,~) obj.onPlay_());
            obj.PlayButton_.FontWeight = 'bold';

            obj.Buttons_ = [obj.Buttons_, ...
                obj.button_(row, '>',  'Next trial', @(~,~) obj.stepAndRefresh_(1)), ...
                obj.button_(row, '>|', 'Last trial', @(~,~) obj.jumpAndRefresh_())];

            obj.TrialLabel_ = uilabel(row, ...
                'Text', '', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

            obj.RateField_ = uieditfield(row, 'numeric', ...
                'Value', 4, 'Limits', [0.1 60], 'ValueDisplayFormat', '%g/s', ...
                'Tooltip', 'Playback rate, trials per second');

            obj.TimeLabel_ = uilabel(row, ...
                'Text', '', 'HorizontalAlignment', 'right', 'FontColor', [0.35 0.35 0.35]);

            % Captures the BEHAVIOR GUI, not this window: a picture of a
            % scrubber is of no use in a notebook, and the whole point of
            % parking the transport in a window of its own is that it stays out
            % of the paradigm's layout -- including out of its screenshots.
            obj.Capture_ = gui.ScreenCapture(row, ...
                Target  = obj.behaviorFigure_(), ...
                Tooltip = 'Copy a picture of the behavior GUI to the clipboard');
            if isempty(obj.Capture_.Target)
                obj.Capture_.Button.Enable = 'off';
                obj.Capture_.Button.Tooltip = 'No behavior GUI window to capture';
            end

            % A review is something an operator reads while working in another
            % application -- a notebook, a spreadsheet -- so the transport has
            % to be able to stay visible. The state is remembered per window by
            % gui.PopOut, and markStandaloneWindow (called before this runs)
            % has already restored it onto the figure, so the button seats
            % itself from the figure rather than from the preference.
            obj.OnTopButton_ = uibutton(row, 'state', ...
                'Text',            'On Top', ...
                'Tooltip',         'Keep this window above other windows', ...
                'Value',           gui.PopOut.isAlwaysOnTop(obj.h_figure), ...
                'ValueChangedFcn', @(src,~) obj.onAlwaysOnTop_(src));
        end

        function f = behaviorFigure_(obj)
            % f = behaviorFigure_(obj)
            % The behavior GUI's window, or [] when the review has none -- a
            % paradigm whose GUI failed to open, or one launched with Show off.
            f = [];
            try
                g = obj.Review.GUI;
                if isobject(g) && isvalid(g) && isprop(g, 'h_figure') && isgraphics(g.h_figure)
                    f = g.h_figure;
                end
            catch ME
                vprintf(3, 'gui.ReviewTransport: no behavior GUI to capture (%s)', ME.message)
            end
        end

        function onAlwaysOnTop_(obj, src)
            % Pin or unpin, and let gui.PopOut remember the choice. It reports
            % what actually happened rather than what was asked for: a release
            % or platform that will not honour WindowStyle leaves the window
            % unpinned, and the button must not claim otherwise.
            gui.PopOut.setAlwaysOnTop(obj.h_figure, src.Value);
            src.Value = gui.PopOut.isAlwaysOnTop(obj.h_figure);
        end

        function h = button_(~, parent, text, tip, fcn)
            h = uibutton(parent, 'Text', text, 'Tooltip', tip, 'ButtonPushedFcn', fcn);
        end

        function onSlider_(obj, src)
            if obj.Refreshing_, return; end
            obj.Review.pause();
            obj.Review.seek(round(src.Value));
            obj.refresh();
        end

        function stepAndRefresh_(obj, n)
            obj.Review.pause();
            obj.Review.step(n);
            obj.refresh();
        end

        function jumpAndRefresh_(obj)
            obj.Review.pause();
            obj.Review.jumpToEnd();
            obj.refresh();
        end

        function onPlay_(obj)
            if obj.Review.isPlaying()
                obj.Review.pause();
            else
                obj.Review.play(obj.RateField_.Value);
            end
            obj.refresh();
        end

        function onClose_(obj, src)
            % Closing the transport ends the scrubbing, not the review: the
            % behavior GUI stays up with whatever trial it is showing, which is
            % what an operator wanting an uncluttered screenshot is after.
            obj.savePosition_();
            try
                obj.Review.pause();
            catch
            end
            delete(obj);
            try
                delete(src);
            catch
            end
        end

        function clearRefreshing_(obj)
            if isvalid(obj), obj.Refreshing_ = false; end
        end

        function watchBehaviorGUI_(obj)
            % A transport with nothing to scrub is not worth leaving on screen,
            % so it follows the behavior GUI's window out.
            try
                g = obj.Review.GUI;
                if isempty(g) || ~isobject(g) || ~isvalid(g) || ~isprop(g, 'h_figure')
                    return
                end
                obj.GUIWatcher_ = listener(g.h_figure, 'ObjectBeingDestroyed', ...
                    @(~,~) obj.onGUIClosed_());
            catch ME
                vprintf(3, 'gui.ReviewTransport: cannot watch the behavior GUI (%s)', ME.message)
            end
        end

        function onGUIClosed_(obj)
            if ~isvalid(obj), return; end
            vprintf(2, 'gui.ReviewTransport: the behavior GUI closed; closing the transport')
            delete(obj);
        end

        function s = timestampText_(obj, k)
            % When the trial happened, so a scrub through the session reads as
            % a session rather than as an index. Elapsed rather than absolute:
            % "17 min in" is the question being asked, and it is comparable
            % between sessions in a way a wall clock is not.
            s = '';
            if k < 1, return; end
            try
                D = obj.Review.Data;
                if ~isfield(D, 'computerTimestamp'), return; end
                t0 = D(1).computerTimestamp;
                s = sprintf('%s elapsed', string(D(k).computerTimestamp - t0));
            catch ME
                vprintf(3, 'gui.ReviewTransport: no timestamp for trial %d (%s)', k, ME.message)
            end
        end

        function closeExistingInstance_(obj)
            % One transport at a time. A second review opened over a first would
            % otherwise leave a window driving a deleted object.
            f = findall(groot, 'Type', 'figure', '-and', 'Tag', obj.PREFERENCE_TAG);
            for i = 1:numel(f)
                try
                    ud = f(i).UserData;
                    f(i).UserData = [];
                    f(i).CloseRequestFcn = '';
                    delete(f(i));
                    if isobject(ud) && isvalid(ud), delete(ud); end
                catch
                end
            end
        end

        function p = startPosition_(obj)
            % Where the window opens: where the operator last left it, else
            % tucked under the behavior GUI, else centred by movegui.
            p = getpref(obj.PREFERENCE_TAG, 'FigurePosition', []);
            if isnumeric(p) && numel(p) == 4 && all(isfinite(p))
                p = double(reshape(p, 1, []));
                % Keep where the operator put it, but never a size smaller than
                % the contents need: a position remembered from an earlier
                % layout would otherwise crowd the row it was saved before.
                p(3:4) = max(p(3:4), obj.DEFAULT_SIZE);
                return
            end

            p = [100 100 obj.DEFAULT_SIZE];
            try
                g = obj.Review.GUI;
                if isobject(g) && isvalid(g) && isprop(g, 'h_figure') && isgraphics(g.h_figure)
                    gp = g.h_figure.Position;
                    p = [gp(1), max(40, gp(2) - obj.DEFAULT_SIZE(2) - 44), obj.DEFAULT_SIZE];
                end
            catch
            end
        end

        function savePosition_(obj)
            try
                if isempty(obj.h_figure) || ~isvalid(obj.h_figure), return; end
                setpref(obj.PREFERENCE_TAG, 'FigurePosition', double(obj.h_figure.Position));
            catch ME
                vprintf(3, 'gui.ReviewTransport: could not save the window position (%s)', ME.message)
            end
        end
    end
end
