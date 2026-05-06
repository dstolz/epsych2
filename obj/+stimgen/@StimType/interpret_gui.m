function interpret_gui(obj, src, event)
% interpret_gui(obj, src, event)
% Parse and apply a widget value-change event to the corresponding property.
% Numeric expression fields are evaluated via evaluate_property_expression_.
% Invalid values are rejected and the widget is reverted to the prior value.

isNumExpr = isstruct(src.UserData) && isfield(src.UserData, 'isNumericExpression') && src.UserData.isNumericExpression;
try
    if isNumExpr
        value = obj.evaluate_property_expression_(src.Tag, char(string(event.Value)));
    else
        value = event.Value;
    end
    obj.(src.Tag) = value;
catch ME
    if isNumExpr
        src.Value = stimgen.StimType.localFormatPropertyValue_(obj.(src.Tag));
    else
        obj.(src.Tag) = event.PreviousValue;
    end
    fig = ancestor(src, 'matlab.ui.Figure');
    if ~isempty(fig) && isvalid(fig)
        uialert(fig, ME.message, sprintf('Invalid value for %s', src.Tag));
    end
    return
end
if isNumExpr
    src.Value = stimgen.StimType.localFormatPropertyValue_(obj.(src.Tag));
end
obj.on_gui_changed(src.Tag, event.Value);
obj.call_update_signal_with_variant_cycle_();
