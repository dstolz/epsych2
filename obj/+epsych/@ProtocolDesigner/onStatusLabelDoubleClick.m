function onStatusLabelDoubleClick(obj)
% onStatusLabelDoubleClick(obj)
% Copy the current status message to the clipboard on double-click and
% briefly flash the label green to confirm the copy.
% Called from Figure.WindowButtonDownFcn; guards against non-double-clicks
% and clicks outside the label bounds.
    if ~strcmp(obj.Figure.SelectionType, 'open')
        return
    end

    % Hit-test: check whether the click landed inside the label.
    pt  = obj.Figure.CurrentPoint;   % [x y] pixels from figure bottom-left
    pos = obj.LabelStatus.Position;  % [x y w h]
    if pt(1) < pos(1) || pt(1) > pos(1)+pos(3) || ...
       pt(2) < pos(2) || pt(2) > pos(2)+pos(4)
        return
    end

    clipboard('copy', obj.LabelStatus.Text);

    savedBg    = obj.LabelStatus.BackgroundColor;
    savedColor = obj.LabelStatus.FontColor;
    savedText  = obj.LabelStatus.Text;

    obj.LabelStatus.BackgroundColor = [0.72 0.96 0.72];
    obj.LabelStatus.FontColor       = [0.05 0.40 0.05];
    obj.LabelStatus.Text            = sprintf('\x2713  Copied to clipboard');

    t = timer( ...
        'StartDelay', 1.5, ...
        'TimerFcn', @(t, ~) localRestore_(t, obj, savedBg, savedColor, savedText));
    start(t);
end

function localRestore_(t, obj, bg, fg, txt)
    stop(t);
    delete(t);
    if isvalid(obj) && isvalid(obj.LabelStatus)
        obj.LabelStatus.BackgroundColor = bg;
        obj.LabelStatus.FontColor       = fg;
        obj.LabelStatus.Text            = txt;
    end
end
