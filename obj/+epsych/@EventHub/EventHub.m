classdef EventHub < handle
    % h = epsych.EventHub()
    % Event broadcaster shared by the components of one session.
    %
    % The runtime owns one of these (epsych.Runtime.EVENTS) and every GUI,
    % psychophysics object, and trial selector that needs to know about a
    % trial listens to it rather than polling.
    %
    % Was named epsych.Helper until 2026-08; the old name said nothing about
    % what the class does and collided with the unrelated gui.Helper.
    %
    % Events:
    %   NewData, NewTrial, ModeChange
    %
    % DEFERRED DISPLAY WORK. NewData is delivered between a trial ending and
    % the next one being dispatched, and every listener runs to completion
    % before the dispatcher can start -- so a table rewrite and three plot
    % redraws were time the subject waited through, on every trial. A display
    % does not have to do that work there. It hands it to
    %
    %   hub.defer(owner, tag, @() ...)        or, from a component that holds
    %   epsych.EventHub.deferFor(source, owner, tag, @() ...)   a runtime or
    %                                                           an analysis
    %
    % and the hub runs it AT ONCE unless a trial boundary is open, in which
    % case it is queued and run by flushDeferred, which
    % epsych.Runtime.dispatchNextTrial calls the moment the NewTrial pulse has
    % gone out. Nothing is delivered late in any other sense: the work runs
    % in the same timer tick, in the order it was asked for, before the
    % NewTrial event. Work asked for twice under one owner and tag before a
    % flush runs once, with the later request.
    %
    % A boundary opens only when ep_TimerFcn_RunTime calls beginDeferral AND
    % the session has asked for deferral (DeferralEnabled -- a behavior GUI's
    % opt-in, see gui.BehaviorGUI.deferDisplayWork, or the rig preference
    % EPsych/DeferDisplays). So a hub nobody opted in, an offline analysis, a
    % component on its own, and an epsych.ReviewSession -- which notifies
    % NewData with no dispatch to follow -- all run deferred work immediately,
    % exactly as if defer were a plain call.
    %
    % ANALYSIS IS NOT DEFERRED. What the next trial may depend on -- a
    % psychophysics object's Results, an adaptive step, a paradigm's
    % onNewData hook -- still runs inside NewData, before the trial is
    % selected. Only drawing is handed over.
    %
    % Properties:
    %   DeferralEnabled - whether beginDeferral opens a boundary (default false)
    %   Deferring       - true while a boundary is open (read-only)
    %
    % Methods:
    %   beginDeferral   - open a boundary (the trial loop, at trial completion)
    %   defer           - run work now, or queue it until the boundary closes
    %   flushDeferred   - run what was queued and close the boundary
    %   deferFor        - (Static) defer through whichever hub a source leads to
    %   valid_psych_obj - Validate that an object is in the psychophysics package.
    %
    % See also: epsych.Runtime.dispatchNextTrial, ep_TimerFcn_RunTime,
    %           gui.BehaviorGUI, documentation/epsych/Event_Notifications.md

    properties
        % Whether a trial boundary defers display work at all. Off by
        % default: a session that has not asked for it behaves exactly as it
        % always did. gui.BehaviorGUI turns it on for a GUI whose
        % deferDisplayWork says so; RunExpt turns it on at Run when
        % preference EPsych/DeferDisplays is true.
        DeferralEnabled (1,1) logical = false
    end

    properties (SetAccess = private)
        Deferring (1,1) logical = false
    end

    properties (Access = private)
        queue_ = struct('Owner', {}, 'Tag', {}, 'Fcn', {})
    end

    events (ListenAccess = 'public', NotifyAccess = 'public')
        % eventually move these to a Runtime object, once it's built
        NewData
        NewTrial
        ModeChange
    end

    methods
        function beginDeferral(obj)
            % beginDeferral(obj)
            % Open a trial boundary: from here until flushDeferred, work
            % handed to defer is queued rather than run. A no-op unless
            % DeferralEnabled, and harmless to call twice.
            if obj.DeferralEnabled
                obj.Deferring = true;
            end
        end

        function defer(obj, owner, tag, fcn)
            % defer(obj, owner, tag, fcn)
            % Run fcn() now, or after the open trial boundary closes.
            %
            % Parameters:
            %   owner - the handle object the work belongs to. Queued work
            %           whose owner has been deleted by the time it would
            %           run is dropped.
            %   tag   - text naming the piece of work. A second request under
            %           the same owner and tag before a flush REPLACES the
            %           first: two boxes finishing in one tick redraw a
            %           shared display once.
            %   fcn   - function handle taking no arguments.
            if ~obj.Deferring
                fcn();
                return
            end

            Q = obj.queue_;
            for k = 1:numel(Q)
                if strcmp(Q(k).Tag, tag) && epsych.EventHub.sameHandle_(Q(k).Owner, owner)
                    obj.queue_(k).Fcn = fcn;
                    return
                end
            end
            obj.queue_(end+1) = struct('Owner', owner, 'Tag', char(tag), 'Fcn', fcn);
        end

        function flushDeferred(obj)
            % flushDeferred(obj)
            % Run what was queued, oldest first, and close the boundary.
            % Work asked for while the queue is being run is run at once.
            % One piece of work that throws is logged and does not stop the
            % rest, which is what a throwing event listener does too.
            obj.Deferring = false;
            if isempty(obj.queue_)
                return
            end
            Q = obj.queue_;
            obj.queue_ = Q([]);
            for k = 1:numel(Q)
                owner = Q(k).Owner;
                if isobject(owner) && isa(owner, 'handle') && ~isvalid(owner)
                    continue
                end
                try
                    Q(k).Fcn();
                catch ME
                    vprintf(0, 1, ME);
                end
            end
        end
    end

    methods (Static)
        function deferFor(source, owner, tag, fcn)
            % epsych.EventHub.deferFor(source, owner, tag, fcn)
            % defer through the session hub SOURCE leads to, or run fcn at
            % once when it leads to none.
            %
            % A display rarely holds the session's hub directly. It holds a
            % runtime, or an analysis object that follows one, or -- offline
            % -- neither. This resolves whichever it is:
            %   epsych.EventHub      the hub itself
            %   epsych.Runtime       its EVENTS
            %   psychophysics.Psych  its RUNTIME's EVENTS, when it has a runtime
            %   anything else, or [] no hub: fcn runs now
            hub = [];
            try
                if isa(source, 'epsych.EventHub')
                    hub = source;
                elseif isa(source, 'epsych.Runtime')
                    hub = source.EVENTS;
                elseif isa(source, 'psychophysics.Psych')
                    rt = source.RUNTIME;
                    if ~isempty(rt)
                        hub = rt.EVENTS;
                    end
                end
            catch
                hub = [];
            end

            if isempty(hub) || ~isa(hub, 'epsych.EventHub') || ~isvalid(hub)
                fcn();
            else
                hub.defer(owner, tag, fcn);
            end
        end

        function tf = valid_psych_obj(obj)
            tf = isobject(obj);
            if ~tf, return; end
            c = class(obj);
            tf = isequal(c(1:find(c=='.')-1),'psychophysics');
        end

    end

    methods (Static, Access = private)
        function tf = sameHandle_(a, b)
            % True when a and b are the same handle object. == across two
            % different handle classes errors, hence the class test first.
            tf = false;
            try
                tf = strcmp(class(a), class(b)) && isscalar(a) && isscalar(b) && a == b;
            catch
            end
        end
    end

end
