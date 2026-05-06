function refresh_plot_if_valid(obj)
% refresh_plot_if_valid(obj)
% Update the live plot line with current Signal data if the handle is still valid.

if ~isempty(obj.plotLineHandle) && isvalid(obj.plotLineHandle)
    if isempty(obj.Signal)
        return
    end
    set(obj.plotLineHandle,'XData',obj.Time,'YData',obj.Signal);
    if ~isempty(obj.plotAxHandle) && isvalid(obj.plotAxHandle)
        grid(obj.plotAxHandle,'on');
        xlabel(obj.plotAxHandle,'time (s)');
    end
end
