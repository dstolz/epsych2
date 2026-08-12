function update_graphical_(obj)
% update_graphical_(obj)
% Refresh the type="graphical" widgets from their parameters. Each widget
% performs exactly one parameter read per poll (Value for lamps/gauges,
% ValueStr for labels) and graphics properties are only assigned when the
% value actually changed, so an idle display costs no redraws.
%
% Value labels flash HighlightColor when their value changes
% (HighlightOnChange); the flash clears on the next poll in which the value
% is stable. The flash is suppressed for the first poll after a (re)build so
% the initial fill does not light up every widget.

W = obj.Widgets;
vals = strings(1,numel(W));
highlight = obj.HighlightOnChange && ~obj.suppressHighlight_;

for i = 1:numel(W)
    p = W(i).Parameter;
    h = W(i).ValueHandle;
    if ~isvalid(p) || ~isvalid(h), continue; end

    switch W(i).Style
        case "lamp"
            v = p.Value;
            state = false;
            if ~isempty(v)
                try
                    state = any(double(v(:)) ~= 0);
                catch
                    state = false; % non-numeric value; treat as off
                end
            end
            vals(i) = string(double(state));
            if ~isequal(state, W(i).LastValue)
                if state
                    h.Color = W(i).OnColor;
                else
                    h.Color = W(i).OffColor;
                end
                W(i).LastValue = state;
            end

        case "gauge"
            v = p.Value;
            if isnumeric(v) && isscalar(v) && isfinite(v)
                vals(i) = string(v);
                if ~isequal(v, W(i).LastValue)
                    h.Value = min(max(v, p.Min), p.Max);
                    W(i).LastValue = v;
                end
            end

        otherwise % "label"
            s = p.ValueStr;
            vals(i) = string(s);
            if ~strcmp(s, W(i).LastText)
                h.Text = s;
                W(i).LastText = string(s);
                if highlight
                    h.BackgroundColor = obj.HighlightColor;
                    W(i).HighlightOn = true;
                end
            elseif W(i).HighlightOn
                h.BackgroundColor = 'none';
                W(i).HighlightOn = false;
            end
    end
end

obj.Widgets = W;
obj.ParameterValues = vals;
obj.suppressHighlight_ = false;

end
