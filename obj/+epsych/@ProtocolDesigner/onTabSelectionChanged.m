function onTabSelectionChanged(obj, evt)
    if ~isequal(evt.NewValue, obj.PreviewTab)
        return
    end

    obj.onCompile();
end

