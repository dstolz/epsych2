classdef MicrophonePlot < handle
 
    properties (SetAccess=immutable)
        Parent
        ParentFigure
        axes
    end

    properties (AbortSet)
        Parameter

    end

    properties (SetAccess=protected)
        h_line
        h_timer
    end

    methods
        function obj = MicrophonePlot(Parameter,Parent)
            arguments
                Parameter 
                Parent (1,1) = gcf
            end

            obj.ParentFigure = ancestor(Parent,'figure');

            if contains(class(Parent),'axes',IgnoreCase=true)
                obj.axes = Parent;
            else
                % to do: determine if ancestor is figure() or uifigure()
                obj.axes = axes(Parent);
            end

            obj.Parent = Parent;
            obj.Parameter = Parameter;

            obj.create;
            
            obj.create_timer;
        end

        function delete(obj)
            delete(obj.h_timer);
        end

    end

    methods (Access = protected)
        function create(obj)
            obj.h_line = line(obj.axes,[0 0],[0 1]);
            obj.h_line.Color = 'y';
            obj.h_line.LineWidth = 15;
            obj.h_line.XData = 0;
            obj.h_line.YData = 0;

            obj.axes.YLim = [0 10];
            obj.axes.XLim = [-1 1];
            obj.axes.XAxis.TickValues = [];
            obj.axes.YAxis.FontSize = 10;
            grid(obj.axes,'on');
        end

        function create_timer(obj)
            obj.h_timer = gui.GenericTimer(obj.ParentFigure,'MicrophonePlot');
            obj.h_timer.Period = 0.2;
            obj.h_timer.TimerFcn = @obj.update;
            obj.h_timer.start;
        end

        function update(obj,varargin)
            obj.h_line.YData = obj.Parameter.Value;
            drawnow limitrate
        end
    end

end