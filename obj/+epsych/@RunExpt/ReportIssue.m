function ReportIssue(self)
% obj.ReportIssue
% Open a GitHub bug report prefilled with this session's environment and the
% tail of the day's error log, after the operator has reviewed both.
%
% The report travels in the URL of the repository's issue form
% (.github/ISSUE_TEMPLATE/bug_report.yml): nothing is uploaded from MATLAB and
% no credentials are involved. That is also the limit -- a link cannot attach a
% file, and an over-long URL is refused -- so only as much of the log as fits
% is prefilled, while the FULL log is offered on the clipboard and revealed in
% the file browser for the operator to paste or drag into the issue.
%
% The preview is not a formality. A log line routinely carries subject names
% and data paths, the tracker is public, and the operator is the only one who
% can judge which of those may be published: both sections are editable, the
% excerpt can be dropped entirely, and nothing opens until Open Issue.
%
% See also: epsych.RunExpt.OpenCurrentErrorLog, epsych.RunExpt.issueURL,
%           epsych.RunExpt.issueReportFields

fig = findall(groot,'Type','figure','-and','Tag','RunExptReportIssue');
if ~isempty(fig) && isgraphics(fig(1))
    fig = fig(1);
    fig.Visible = 'on';
    fig.Position = gui.fitPositionToMonitor(fig.Position);   % not onto the primary
    figure(fig);
    return
end

fields = self.issueReportFields();
hasLog = ~isempty(fields.logPath);

fig = uifigure('Name','Report an Issue on GitHub', ...
    'Tag','RunExptReportIssue', ...
    'Position',[100 100 780 740]);
movegui(fig,'center');

g = uigridlayout(fig,[8 1]);
% The environment block is sized to show all of itself: it is short, fixed, and
% the operator is being asked to vouch for it, so it must not need scrolling.
g.RowHeight = {'fit',18,240,'fit','1x','fit',18,32};
g.ColumnWidth = {'1x'};
g.RowSpacing = 6;
g.Padding = [16 14 16 14];

uilabel(g, ...
    'Text',['This opens GitHub with the form already filled in. Everything below ' ...
            'becomes public the moment you submit it there, so edit or delete ' ...
            'anything you would rather not publish -- log lines routinely contain ' ...
            'subject names and data paths. Nothing is sent from MATLAB itself.'], ...
    'WordWrap','on', ...
    'FontColor',[0.45 0.20 0.05]);

uilabel(g,'Text','Environment','FontWeight','bold');
% WordWrap on both areas: a line the operator cannot see is a line they cannot
% vouch for, and the toolbox list and log paths are both wider than the window.
envArea = uitextarea(g, ...
    'Value',cellstr(splitlines(string(fields.environment))), ...
    'FontName','Consolas', ...
    'WordWrap','on', ...
    'ValueChangedFcn',@(~,~) updateSize());

% --- log excerpt header: the opt-in and what it covers -------------------
hdr = uigridlayout(g,[1 2]);
hdr.ColumnWidth = {260,'1x'};
hdr.RowHeight = {'fit'};
hdr.Padding = [0 0 0 0];
hdr.ColumnSpacing = 8;

includeLog = uicheckbox(hdr, ...
    'Text','Include this error log excerpt', ...
    'Value',hasLog, ...
    'Enable',matlab.lang.OnOffSwitchState(hasLog), ...
    'FontWeight','bold', ...
    'ValueChangedFcn',@(src,~) onIncludeChanged(src));

if hasLog
    hdrText = sprintf('last %d of %d lines  |  %s', ...
        fields.logLines, fields.logTotalLines, fields.logPath);
else
    hdrText = 'File logging is disabled for this session, so there is no log to include.';
end
uilabel(hdr, ...
    'Text',hdrText, ...
    'FontColor',[0.35 0.39 0.46], ...
    'WordWrap','on');

logArea = uitextarea(g, ...
    'Value',cellstr(splitlines(string(fields.logs))), ...
    'FontName','Consolas', ...
    'WordWrap','on', ...
    'Enable',matlab.lang.OnOffSwitchState(hasLog), ...
    'ValueChangedFcn',@(~,~) updateSize());

% --- what to do with the part that does not fit in a URL -----------------
optGrid = uigridlayout(g,[1 2]);
optGrid.ColumnWidth = {'1x','1x'};
optGrid.RowHeight = {'fit'};
optGrid.Padding = [0 0 0 0];

copyBox = uicheckbox(optGrid, ...
    'Text','Copy the full log to the clipboard', ...
    'Tooltip','Paste it into the issue when the excerpt does not reach far enough back.', ...
    'Value',hasLog, ...
    'Enable',matlab.lang.OnOffSwitchState(hasLog), ...
    'ValueChangedFcn',@(~,~) updateSize());
revealBox = uicheckbox(optGrid, ...
    'Text','Show the log file so I can attach it', ...
    'Tooltip','Opens the folder with the log selected, ready to drag onto the issue.', ...
    'Value',hasLog, ...
    'Enable',matlab.lang.OnOffSwitchState(hasLog));

sizeLabel = uilabel(g,'Text','','FontColor',[0.35 0.39 0.46]);

footer = uigridlayout(g,[1 3]);
footer.ColumnWidth = {'1x',150,90};
footer.RowHeight = {'1x'};
footer.Padding = [0 0 0 0];
uilabel(footer,'Text','');
uibutton(footer,'push','Text','Open Issue', ...
    'ButtonPushedFcn',@(~,~) onOpen());
uibutton(footer,'push','Text','Cancel', ...
    'ButtonPushedFcn',@(~,~) delete(fig));

updateSize();

% -------------------------------------------------------------------
    function s = currentFields()
        % The edited text, not what was gathered: the operator's redactions
        % are the point of the preview.
        s = fields;
        s.environment = char(join(string(envArea.Value(:)), newline));
        if includeLog.Value
            s.logs = char(join(string(logArea.Value(:)), newline));
        else
            s.logs = '';
        end
    end

% -------------------------------------------------------------------
    function updateSize()
        % Report the URL budget as it stands, so an operator who pastes a
        % second stack trace in sees the trimming coming rather than
        % discovering it on GitHub.
        [url, trimmed] = epsych.RunExpt.issueURL(currentFields());
        if trimmed > 0
            % Say where the dropped lines end up, or the note reads as a loss
            % rather than as the reason the clipboard offer is there.
            if copyBox.Value
                where = 'they stay in the full log going to your clipboard';
            else
                where = 'tick "Copy the full log to the clipboard" to keep them';
            end
            sizeLabel.Text = sprintf(['Link: %d characters. The %d oldest excerpt ' ...
                'line(s) do not fit in a URL -- %s.'], numel(url), trimmed, where);
            sizeLabel.FontColor = [0.65 0.35 0.05];
        else
            sizeLabel.Text = sprintf('Link: %d characters. The whole report fits.', numel(url));
            sizeLabel.FontColor = [0.35 0.39 0.46];
        end
    end

% -------------------------------------------------------------------
    function onIncludeChanged(src)
        % Greying the excerpt rather than clearing it: unticking is reversible,
        % and an operator who ticks it back expects the text to still be there.
        logArea.Enable = matlab.lang.OnOffSwitchState(src.Value);
        updateSize();
    end

% -------------------------------------------------------------------
    function onOpen()
        s = currentFields();
        [url, trimmed] = epsych.RunExpt.issueURL(s);

        if copyBox.Value
            localCopyFullLog_(fields.logPath);
        end
        if revealBox.Value
            localRevealFile_(fields.logPath);
        end

        try
            web(url,'-browser');
        catch ME
            vprintf(0,1,ME);
            uialert(fig, sprintf(['Unable to open the browser.\n\n' ...
                'Report the issue at %s instead; the log is on your clipboard ' ...
                'if you asked for it.'], EPsychInfo.IssuesURL), 'Report an Issue');
            return
        end

        vprintf(1,'Issue report opened in browser (%d URL characters, %d excerpt line(s) dropped)', ...
            numel(url), trimmed);
        self.setStatus('Issue report opened in your browser.');
        delete(fig);
    end
end

% -----------------------------------------------------------------------
function localCopyFullLog_(logPath)
% Put the whole log on the clipboard. Failure is reported and shrugged off:
% the report itself is still fine without it.
try
    clipboard('copy', fileread(logPath));
catch ME
    vprintf(0,1,ME);
end
end

% -----------------------------------------------------------------------
function localRevealFile_(logPath)
% Show the log file in the OS file browser, selected where the platform can do
% so, so it can be dragged onto the issue -- the only route to a real
% attachment, since a URL cannot carry one.
try
    if ispc
        % explorer returns 1 even when it succeeds, so its status is ignored
        % here rather than checked.
        system(sprintf('explorer /select,"%s"', logPath));
    elseif ismac
        system(sprintf('open -R "%s" &', logPath));
    else
        system(sprintf('xdg-open "%s" &', fileparts(logPath)));
    end
catch ME
    vprintf(0,1,ME);
end
end
