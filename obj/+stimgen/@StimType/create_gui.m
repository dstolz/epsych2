function h = create_gui(obj, src, ~)
% create_gui(obj, src) - Auto-build parameter GUI from propMeta().
% Creates a two-column label+widget grid for each property returned
% by propMeta(). Widget type is inferred from the property class
% (double->numeric editfield, logical->checkbox, string->text
% editfield) unless overridden via the 'widget' metadata field.
%
% Parameters:
%   src - parent UI container (e.g. uipanel)
%
% Returns:
%   h - struct of widget handles keyed by property name

meta   = obj.propMeta();
fields = fieldnames(meta);
nRows  = numel(fields);

mc = metaclass(obj);
pl = mc.PropertyList;

g = uigridlayout(src);
g.ColumnWidth = {'1x', '1x'};
g.RowHeight   = repmat({25}, 1, nRows);

h = struct();
for i = 1:nRows
    propName = fields{i};
    pm = meta.(propName);

    lbl = uilabel(g, 'Text', pm.label);
    lbl.Layout.Column = 1;
    lbl.Layout.Row    = i;
    lbl.HorizontalAlignment = 'right';

    wt = stimgen.StimType.resolve_widget_type(propName, pm, pl);

    switch wt
        case 'numeric'
            if obj.is_non_vectorizable_property_(propName)
                x = uieditfield(g, 'numeric', 'Tag', propName);
                x.Value = obj.(propName);
                if isfield(pm, 'format')
                    x.ValueDisplayFormat = pm.format;
                end
                if isfield(pm, 'limits')
                    x.Limits = pm.limits;
                end
            else
                x = uieditfield(g, 'Tag', propName);
                x.Value = stimgen.StimType.localFormatPropertyValue_(obj.(propName));
                x.UserData = struct('isNumericExpression', true, 'propMeta', pm);
            end
        case 'checkbox'
            x = uicheckbox(g, 'Tag', propName, 'Text', '');
            x.Value = obj.(propName);
        case 'dropdown'
            x = uidropdown(g, 'Tag', propName);
            x.Items = pm.items;
            if isfield(pm, 'itemsData')
                x.ItemsData = pm.itemsData;
            end
            x.Value = obj.(propName);
        otherwise % 'text'
            x = uieditfield(g, 'Tag', propName);
            x.Value = char(obj.(propName));
    end

    x.Layout.Column = 2;
    x.Layout.Row    = i;
    h.(propName)    = x;
end

structfun(@(a) set(a, 'ValueChangedFcn', @obj.interpret_gui), h);
obj.GUIHandles = h;
