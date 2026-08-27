function showHelp(obj)
% showHelp(obj)
% List every binding in a modal window, grouped by the component that owns
% it, in the order the bindings were made.
%
% The operator cannot change a binding, so this is the only place the set
% is visible: a paradigm decides what the keys do, and this says what it
% decided.

L = obj.list();

if isempty(L)
    lines = {'No keyboard shortcuts are bound in this window.'};
else
    % Widest chord sets the description column, so the list reads as two
    % columns whatever the longest chord happens to be.
    width = max(cellfun(@numel, {L.Display}));
    lines = {};
    groups = unique({L.Group}, 'stable');
    for g = 1:numel(groups)
        sel = strcmp({L.Group}, groups{g});
        lines{end+1} = [upper(groups{g}) ':'];
        entries = L(sel);
        for i = 1:numel(entries)
            lines{end+1} = sprintf('  %-*s   %s', width, entries(i).Display, entries(i).Description);
        end
        if g < numel(groups)
            lines{end+1} = '';
        end
    end
end

% Centred on the window the shortcuts belong to, so it opens where the
% operator is looking rather than wherever the last figure was placed.
dlgWidth  = 520;
dlgHeight = min(620, max(200, 90 + 20 * numel(lines)));
dlgPos    = [100 100 dlgWidth dlgHeight];
try
    p = obj.Figure.Position;
    dlgPos(1:2) = [p(1) + round((p(3) - dlgWidth) / 2), p(2) + round((p(4) - dlgHeight) / 2)];
catch ME
    vprintf(3, 'gui.KeyBindings: could not centre the shortcut list (%s)', ME.message)
end

% Fitted rather than movegui'd onscreen: centring on a GUI that sits near the
% edge of a secondary monitor puts part of the dialog off that screen, and
% movegui would answer by moving it to the primary one, away from the window
% whose shortcuts it lists.
dlgPos = gui.fitPositionToMonitor(dlgPos);

dlg = uifigure('Name', obj.Title, 'Position', dlgPos, 'Resize', 'off', 'WindowStyle', 'modal');

uitextarea(dlg, ...
    'Value',           lines, ...
    'Editable',        'off', ...
    'Position',        [15 55 dlgWidth-30 dlgHeight-70], ...
    'FontName',        'Courier New', ...
    'BackgroundColor', dlg.Color);

uibutton(dlg, 'push', ...
    'Text',            'Close', ...
    'Position',        [dlgWidth/2-50 15 100 30], ...
    'ButtonPushedFcn', @(~,~) close(dlg));
