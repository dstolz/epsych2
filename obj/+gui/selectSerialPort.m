function port = selectSerialPort(options)
% port = gui.selectSerialPort(Name=Value)
% Modal dialog asking the operator which serial port a device is on.
%
% Built for the connect-failure path: a USB-serial adapter that renumbered,
% a device nobody switched on, a cable in the wrong socket. The port list is
% enumerated fresh every time Refresh is pressed, so a device plugged in or
% powered up while the dialog is open can be picked without restarting the
% session — that, not the picking, is the point of the button.
%
% Name=Value
%   Title       - Dialog title. Default 'Select Serial Port'
%   Prompt      - Explanatory text shown above the list. Default ''
%   CurrentPort - Port to preselect, if it is still present. Default ''
%   Parent      - Figure the dialog is modal to and centered on. Default []
%   Probe       - Function handle returning the port a device answers on, or
%                 '' when none does. Adds a detect button when supplied; the
%                 probe is what tells "wrong port" from "device is off".
%                 Default []
%   ProbeLabel  - Label for that button. Default 'Detect Device'
%
% Returns
%   port - Chosen port name, or '' when the operator cancelled.
%
% Ports already opened by another process are listed but not selectable:
% they are shown because a pump held open by a stale MATLAB is a likely
% reason for the failure that brought the operator here, and hiding it would
% make the port simply appear missing.
%
% Usage
%   p = gui.selectSerialPort(Parent = fig, CurrentPort = 'COM4', ...
%           Prompt = 'The pump did not answer on COM4.', ...
%           Probe = @() hw.NE1000.findPumpPort(BaudRate = 19200));
%
% See also: hw.Interface.recoverConnection, hw.NE1000.findPumpPort, serialportlist

arguments
    options.Title (1,:) char = 'Select Serial Port'
    options.Prompt (1,:) char = ''
    options.CurrentPort (1,:) char = ''
    options.Parent = []
    options.Probe = []
    options.ProbeLabel (1,:) char = 'Detect Device'
end

port = '';
selected = '';
available = strings(1, 0);

fig = uifigure(Name = options.Title, Resize = 'off', ...
    Position = local_placement_(options.Parent), WindowStyle = 'modal');
fig.CloseRequestFcn = @(~, ~) onCancel();

% Column 3 is the only elastic one, which puts the two rig actions (rescan,
% probe) on the left and the two dialog answers on the right. With no probe,
% its 'fit' column simply collapses.
grid = uigridlayout(fig, [4 5]);
grid.RowHeight = {'fit', '1x', 'fit', 'fit'};
grid.ColumnWidth = {'fit', 'fit', '1x', 'fit', 'fit'};
grid.RowSpacing = 8;

promptText = options.Prompt;
if isempty(promptText)
    promptText = 'Select the port the device is connected to.';
end
lbl = uilabel(grid, Text = promptText, WordWrap = 'on', VerticalAlignment = 'top');
lbl.Layout.Row = 1;
lbl.Layout.Column = [1 5];

list = uilistbox(grid, Items = {}, ItemsData = {}, ...
    ValueChangedFcn = @(src, ~) onSelect(src), ...
    DoubleClickedFcn = @(~, ~) onOK());
list.Layout.Row = 2;
list.Layout.Column = [1 5];

status = uilabel(grid, Text = '', WordWrap = 'on', FontAngle = 'italic');
status.Layout.Row = 3;
status.Layout.Column = [1 5];

btnRefresh = uibutton(grid, Text = 'Refresh', ...
    Tooltip = 'Re-scan for serial ports, picking up a device connected or powered on just now', ...
    ButtonPushedFcn = @(~, ~) onRefresh());
btnRefresh.Layout.Row = 4;
btnRefresh.Layout.Column = 1;

% The detect button only appears when the caller can actually identify its
% own device; a generic picker has no way to tell one silent port from another.
btnProbe = matlab.ui.control.Button.empty;
if ~isempty(options.Probe)
    btnProbe = uibutton(grid, Text = options.ProbeLabel, ...
        Tooltip = 'Query every available port and select the one the device answers on', ...
        ButtonPushedFcn = @(~, ~) onProbe());
    btnProbe.Layout.Row = 4;
    btnProbe.Layout.Column = 2;
end

btnOK = uibutton(grid, Text = 'OK', Enable = 'off', ButtonPushedFcn = @(~, ~) onOK());
btnOK.Layout.Row = 4;
btnOK.Layout.Column = 4;

btnCancel = uibutton(grid, Text = 'Cancel', ButtonPushedFcn = @(~, ~) onCancel());
btnCancel.Layout.Row = 4;
btnCancel.Layout.Column = 5;

refreshList(options.CurrentPort);

% A dialog closed before it ever blocks — by a caller, a test driver, or the
% window being dismissed as it appears — has already delivered its answer
% through the callbacks; waiting on the deleted handle would only throw.
if isvalid(fig)
    uiwait(fig);
end


    function refreshList(preferPort)
        % Rebuild the list from a fresh enumeration, keeping preferPort
        % selected when it is still there and selectable.
        try
            all_ = string(serialportlist('all'));
            available = string(serialportlist('available'));
        catch ME
            vprintf(0, 1, ME);
            all_ = strings(1, 0);
            available = strings(1, 0);
        end

        % Enumerating ports queries the OS and yields, so a timer callback --
        % gui.SyringePump polls at 4 Hz, and a rig has several such -- can
        % close this dialog in the middle of the scan. Anything below would
        % then be writing to deleted widgets.
        if ~isvalid(fig)
            return
        end

        items = cell(1, numel(all_));
        for k = 1:numel(all_)
            if ismember(all_(k), available)
                items{k} = char(all_(k));
            else
                items{k} = sprintf('%s  (in use by another program)', all_(k));
            end
        end

        list.Items = items;
        list.ItemsData = cellstr(all_);

        if isempty(all_)
            status.Text = 'No serial ports found. Connect the device, then press Refresh.';
            selected = '';
        else
            status.Text = sprintf('%d port(s) found, %d available.', ...
                numel(all_), numel(available));
            if ~isempty(preferPort) && ismember(string(preferPort), all_)
                list.Value = char(preferPort);
            else
                list.Value = list.ItemsData{1};
            end
            selected = char(list.Value);
        end
        updateOK();
    end

    function onSelect(src)
        selected = char(src.Value);
        updateOK();
    end

    function updateOK()
        % An in-use port cannot be opened, so OK stays off rather than
        % handing back a choice that is guaranteed to fail on retry.
        ok = ~isempty(selected) && ismember(string(selected), available);
        btnOK.Enable = matlab.lang.OnOffSwitchState(ok);
        if ~isempty(selected) && ~ok
            status.Text = sprintf(['%s is open in another program. Close it ' ...
                '(or the other MATLAB session), then press Refresh.'], selected);
        end
    end

    function onProbe()
        setBusy(true, 'Querying each available port for the device...');
        found = '';
        try
            found = char(string(options.Probe()));
        catch ME
            vprintf(0, 1, ME);
        end
        setBusy(false, '');
        if ~isvalid(fig)
            return          % closed while the probe held the ports open
        end

        if isempty(found)
            refreshList(selected);
            status.Text = ['No device answered on any available port. Check that it ' ...
                'is powered on and cabled, then press Refresh and try again.'];
        else
            refreshList(found);
            status.Text = sprintf('Device answered on %s.', found);
        end
    end

    function setBusy(tf, message)
        % The probe opens and times out on every port in turn, which takes
        % seconds; without this the dialog looks hung and gets clicked again.
        if ~isvalid(fig)
            return
        end
        state = matlab.lang.OnOffSwitchState(~tf);
        btnRefresh.Enable = state;
        btnCancel.Enable = state;
        list.Enable = state;
        if ~isempty(btnProbe), btnProbe.Enable = state; end
        if tf
            btnOK.Enable = 'off';
            status.Text = message;
        else
            updateOK();
        end
        drawnow
    end

    function onRefresh()
        refreshList(selected);
    end

    function onOK()
        if ~isempty(selected) && ismember(string(selected), available)
            port = selected;
            delete(fig);
        end
    end

    function onCancel()
        port = '';
        delete(fig);
    end
end


function pos = local_placement_(parent)
% Center the dialog on parent when there is one, else on screen.
w = 380;
h = 300;
if ~isempty(parent) && isgraphics(parent)
    p = parent.Position;
    pos = [p(1) + (p(3) - w) / 2, p(2) + (p(4) - h) / 2, w, h];
else
    s = get(groot, 'ScreenSize');
    pos = [(s(3) - w) / 2, (s(4) - h) / 2, w, h];
end
end
