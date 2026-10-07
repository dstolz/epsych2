classdef (Abstract) View < handle
    % gui.behavior.View  What every tab of epsych.BehaviorAnalysis is.
    %
    % A view owns ITS graphics inside a container the window gives it, reads
    % everything it shows from a behavior.Study, and changes nothing but
    % through the Study's methods -- so the Study's events are the only way a
    % view learns that something changed, and two views can never disagree.
    % The base class gives each view the Study, the container, a handle
    % struct H, a subscription to the Study's events that calls refresh with
    % the event's name, a status line it can post to, and a teardown that
    % releases its listeners and graphics.
    %
    % Subclasses implement:
    %   build(obj)            - create the graphics under obj.Parent into obj.H;
    %                           obj.H.root must be the one top-level container
    %   refresh(obj, reason)  - redraw for a Study event name ("CatalogChanged",
    %                           "ProjectChanged", "SettingsChanged",
    %                           "SelectionChanged", "ResultsChanged") or for
    %                           "show" (the window asked), never throwing for a
    %                           session that cannot be drawn
    %
    % Properties:
    %   Study     - the behavior.Study
    %   Parent    - the container the window gave this view
    %   H         - graphics handles
    %   StatusFcn - @(text) the window's status line ([] = log only)
    %
    % See also: epsych.BehaviorAnalysis, behavior.Study

    properties (SetAccess = protected)
        Study
        Parent
        H (1,1) struct = struct()
    end

    properties
        StatusFcn = []
    end

    properties (Access = protected)
        Listeners_ = event.listener.empty
        Refreshing_ (1,1) logical = false
    end

    methods
        function obj = View(parent, study)
            arguments
                parent
                study (1,1) behavior.Study
            end
            obj.Parent = parent;
            obj.Study = study;
            obj.build();
            obj.listen_();
        end

        function delete(obj)
            % Release the Study listeners first, then the graphics, so a late
            % event cannot reach a view whose widgets are gone.
            try
                L = obj.Listeners_;
                L = L(isvalid(L));
                if ~isempty(L), delete(L); end
                obj.Listeners_ = event.listener.empty;
            catch ME
                vprintf(2, ME);
            end
            try
                if isfield(obj.H, 'root') && isgraphics(obj.H.root)
                    delete(obj.H.root);
                end
            catch ME
                vprintf(2, ME);
            end
        end

        function setStatus(obj, text)
            % setStatus(obj, text)
            % Post a line to the window's status bar, or log it without one.
            arguments
                obj
                text (1,1) string
            end
            if isempty(obj.StatusFcn)
                vprintf(2, '%s: %s', class(obj), text);
            else
                try
                    obj.StatusFcn(text);
                catch ME
                    vprintf(2, ME);
                end
            end
        end
    end

    methods (Abstract)
        build(obj)
        refresh(obj, reason)
    end

    methods (Access = protected)
        function listen_(obj)
            names = ["CatalogChanged" "ProjectChanged" "SettingsChanged" "SelectionChanged" "ResultsChanged"];
            for name = names
                obj.Listeners_(end+1) = addlistener(obj.Study, name, @(~,~) obj.onStudyEvent_(name));
            end
        end

        function onStudyEvent_(obj, name)
            % A view that throws from a listener would stop the event reaching
            % the other views; it reports instead. A refresh that triggers the
            % event it is listening to (mirroring a plot's menu into Settings)
            % is not re-entered.
            if obj.Refreshing_ || ~isvalid(obj)
                return
            end
            obj.Refreshing_ = true;
            cleanup = onCleanup(@() obj.doneRefreshing_());
            try
                obj.refresh(name);
            catch ME
                vprintf(0, 1, ME);
            end
            delete(cleanup);
        end

        function doneRefreshing_(obj)
            if isvalid(obj)
                obj.Refreshing_ = false;
            end
        end
    end
end
