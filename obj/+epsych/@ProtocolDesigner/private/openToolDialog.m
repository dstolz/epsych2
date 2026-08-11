function [dialog, isNew] = openToolDialog(obj, propertyName, name, dialogSize)
% [dialog, isNew] = openToolDialog(obj, propertyName, name, dialogSize)
% Open, or raise, the tool dialog tracked by one of the designer's figure
% properties.
%
% Parameters:
%	propertyName - Name of the ProtocolDesigner property holding the figure.
%	name         - Dialog title.
%	dialogSize   - [width height] in pixels.
%
% Returns:
%	dialog - The dialog figure.
%	isNew  - false when an existing dialog was raised instead of created.
%
% Tracking each dialog in a property keeps a second toolbar click from building
% a duplicate: the designer's control properties would then point at the newest
% copy and every older window would go stale, refreshing nothing.
    existing = obj.(propertyName);
    if ~isempty(existing) && isvalid(existing)
        figure(existing);
        dialog = existing;
        isNew = false;
        return
    end

    % Centre on the designer, but never off the bottom or left of the display.
    parentPos = obj.Figure.Position;
    left = max(10, parentPos(1) + round((parentPos(3) - dialogSize(1)) / 2));
    bottom = max(50, parentPos(2) + round((parentPos(4) - dialogSize(2)) / 2));

    dialog = uifigure( ...
        'Name', name, ...
        'Position', [left bottom dialogSize(1) dialogSize(2)], ...
        'Resize', 'off', ...
        'WindowKeyPressFcn', @(~, evt) obj.onFigureKeyPress(evt));

    obj.(propertyName) = dialog;
    isNew = true;
end
