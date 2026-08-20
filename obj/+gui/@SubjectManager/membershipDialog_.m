function M = membershipDialog_(self, seed, options)
% M = membershipDialog_(self, seed)
% M = membershipDialog_(self, seed, Title = 'Session Settings')
% Modal dialog for the session settings one membership carries.
%
% The membership editor: where one subject deliberately diverges from its
% project's template -- a longer timer period for a slow animal, a different
% saving function for a pilot. The field grid is sessionDefaultsGrid_, shared
% with the project dialog, so the two can never disagree about what a session
% setting is; here the fields are tagged MembershipDlg_* and there is no
% Default Protocol row (a membership's protocol goes through the
% protocol-memory workflow instead).
%
% It refuses blanks exactly as the template dialog does: every membership it
% opens on is stamped complete or seeded from built-ins, so the all-inherit
% state can arise only from scripts and pre-pivot rosters, never from here.
%
% Parameters:
%   seed - membership record (or any struct carrying the SESSION_FIELDS).
%
% Options:
%   Title - window title; default 'Session Settings'.
%
% Returns:
%   M - struct with the SESSION_FIELDS, or [] when cancelled. The caller
%       commits it with epsych.SubjectRoster.updateMembership.
%
% See also: gui.SubjectManager.sessionDefaultsGrid_, gui.SubjectManager.projectDialog_,
%   epsych.SubjectRoster.updateMembership, epsych.SubjectRoster.reapplyTemplate
arguments
    self
    seed (1,1) struct
    options.Title (1,:) char = 'Session Settings'
end

M = [];
accepted = false;
result = struct();
title = options.Title;

dlg = uifigure('Name', title, 'Position', [0 0 620 480], ...
    'Resize','off', 'WindowStyle','modal', ...
    'WindowKeyPressFcn', @(~,evt) onKey(evt), ...
    'CloseRequestFcn', @(~,~) onCancel());
movegui(dlg, 'center');

gOuter = uigridlayout(dlg, [2 1]);
gOuter.RowHeight = {'1x', 32};
gOuter.Padding = [12 12 12 12];
gOuter.RowSpacing = 8;

pnl = uipanel(gOuter, 'BorderType','none');
pnl.Layout.Row = 1; pnl.Layout.Column = 1;
S = self.sessionDefaultsGrid_(pnl, seed, 'MembershipDlg_', IncludeProtocol = false);

gButtons = uigridlayout(gOuter, [1 3]);
gButtons.Layout.Row = 2; gButtons.Layout.Column = 1;
gButtons.ColumnWidth = {'1x', 90, 90};
gButtons.Padding = [0 0 0 0];
uilabel(gButtons, 'Text','');
uibutton(gButtons, 'Text','OK', 'ButtonPushedFcn', @(~,~) onOK());
uibutton(gButtons, 'Text','Cancel', 'ButtonPushedFcn', @(~,~) onCancel());

uiwait(dlg);

if accepted
    M = result;
end

if isgraphics(dlg)
    dlg.CloseRequestFcn = '';
    delete(dlg);
end

% -------------------------------------------------------------------
    function onOK()
        [vals, okv, vmsg] = S.collect();
        if ~okv
            uialert(dlg, vmsg, title, 'Icon','warning');
            return
        end

        result = vals;
        S.remember(vals);

        accepted = true;
        uiresume(dlg);
    end

% -------------------------------------------------------------------
    function onCancel()
        accepted = false;
        uiresume(dlg);
    end

% -------------------------------------------------------------------
    function onKey(evt)
        if strcmp(evt.Key, 'escape')
            onCancel();
        elseif strcmp(evt.Key, 'return') && any(strcmp(evt.Modifier, 'control'))
            onOK();
        end
    end

end
