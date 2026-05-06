function update_handle_value(obj, src, ~)
% update_handle_value(obj, src, event)
% Sync the GUI widget for src.Name to the current property value.

h = obj.GUIHandles;
h.(src.Name).Value = obj.(src.Name);
