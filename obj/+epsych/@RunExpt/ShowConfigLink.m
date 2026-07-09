function ShowConfigLink(self)
% obj.ShowConfigLink
% Show the "epsych://" link for the currently loaded configuration, copy it
% to the clipboard, and register/unregister the OS URL protocol so the link
% is clickable from outside MATLAB (e.g. a subject's data-log Google Sheet).
%
% See also: epsych.RunExpt.buildConfigURL, epsych.RunExpt.registerURLProtocol

% Reuse an existing dialog if one is already open.
fig = findall(groot,'Type','figure','-and','Tag','RunExptConfigLink');
if ~isempty(fig) && isgraphics(fig(1))
    fig = fig(1);
    fig.Visible = 'on';
    movegui(fig,'onscreen');
    figure(fig);
    return
end

if strlength(self.CurrentConfigFile) > 0
    url = epsych.RunExpt.buildConfigURL(self.CurrentConfigFile);
    pathText = char(self.CurrentConfigFile);
else
    url = "";
    pathText = '(No configuration loaded — load a config first.)';
end

fig = uifigure('Name','EPsych Config Link', ...
    'Tag','RunExptConfigLink', ...
    'Position',[100 100 600 360], ...
    'Resize','off', ...
    'Color',[0.97 0.98 1.00]);
movegui(fig,'center');

rootGrid = uigridlayout(fig,[7 2]);
rootGrid.RowHeight   = {'fit','fit',64,'fit','fit','fit','1x'};
rootGrid.ColumnWidth = {'1x',140};
rootGrid.RowSpacing  = 10;
rootGrid.ColumnSpacing = 10;
rootGrid.Padding = [18 18 18 18];
rootGrid.BackgroundColor = fig.Color;

% Title
title = uilabel(rootGrid,'Text','Config Link','FontSize',20,'FontWeight','bold', ...
    'FontColor',[0.13 0.25 0.47]);
title.Layout.Row = 1; title.Layout.Column = [1 2];

% Current config path
lblPath = uilabel(rootGrid,'Text',['Configuration:  ' pathText],'WordWrap','on', ...
    'FontColor',[0.16 0.18 0.23]);
lblPath.Layout.Row = 2; lblPath.Layout.Column = [1 2];

% The link itself (read-only, selectable)
urlArea = uitextarea(rootGrid,'Value',char(url),'Editable','off','FontName','Consolas');
urlArea.Layout.Row = 3; urlArea.Layout.Column = [1 2];

% Copy button
copyBtn = uibutton(rootGrid,'push','Text','Copy to Clipboard', ...
    'ButtonPushedFcn', @(~,~) onCopy());
copyBtn.Layout.Row = 4; copyBtn.Layout.Column = 2;
copyBtn.Enable = matlab.lang.OnOffSwitchState(strlength(url) > 0);

% Registration status + toggle button
statusLabel = uilabel(rootGrid,'Text','','WordWrap','on','FontColor',[0.35 0.39 0.46]);
statusLabel.Layout.Row = 5; statusLabel.Layout.Column = 1;

regBtn = uibutton(rootGrid,'push','Text','','ButtonPushedFcn', @(~,~) onToggleRegistration());
regBtn.Layout.Row = 5; regBtn.Layout.Column = 2;

% Hint
hint = uilabel(rootGrid, ...
    'Text',['Paste this link into the subject''s data-log sheet. Clicking it loads ' ...
            'the config into an open RunExpt session (a running experiment is never interrupted). ' ...
            'Re-register if the EPsych folder is moved.'], ...
    'WordWrap','on','FontAngle','italic','FontColor',[0.35 0.39 0.46]);
hint.Layout.Row = 6; hint.Layout.Column = [1 2];

% Close
closeBtn = uibutton(rootGrid,'push','Text','Close','ButtonPushedFcn', @(~,~) delete(fig));
closeBtn.Layout.Row = 7; closeBtn.Layout.Column = 2;

refreshRegistration();

    function onCopy()
        if strlength(url) == 0, return, end
        clipboard('copy', char(url));
        uialert(fig,'Link copied to clipboard.','EPsych','Icon','success');
    end

    function onToggleRegistration()
        if ~ispc, return, end
        if epsych.RunExpt.isURLProtocolRegistered
            ok = epsych.RunExpt.unregisterURLProtocol;
            if ~ok
                uialert(fig,'Could not remove the registration. See the error log.','EPsych','Icon','error');
            end
        else
            ok = epsych.RunExpt.registerURLProtocol;
            if ~ok
                uialert(fig,'Could not register the epsych:// protocol. See the error log.','EPsych','Icon','error');
            end
        end
        refreshRegistration();
    end

    function refreshRegistration()
        if ~ispc
            statusLabel.Text = 'URL protocol registration is available on Windows only.';
            regBtn.Enable = 'off';
            regBtn.Text = 'Register';
            return
        end
        if epsych.RunExpt.isURLProtocolRegistered
            statusLabel.Text = 'epsych:// is registered on this machine.';
            regBtn.Text = 'Unregister';
        else
            statusLabel.Text = 'epsych:// is not registered on this machine.';
            regBtn.Text = 'Register';
        end
        regBtn.Enable = 'on';
    end
end
