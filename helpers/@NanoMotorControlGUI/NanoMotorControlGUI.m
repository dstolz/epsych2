classdef NanoMotorControlGUI < handle
%NANAMOTORCONTROLGUI GUI front-end for NanoMotorControl.
%
%   NanoMotorControlGUI builds a compact uigridlayout-based control panel for
%   the NanoMotorControl serial interface.
%
%   Capabilities
%     - Jog CW/CCW (click-to-toggle)
%     - Set rotation speed (RPM)
%     - Send MOVEDEG commands using either degrees or rotations
%     - STOP (halts jogging and stops any active MOVE)
%     - Display current commanded position (degrees)
%     - Lamp + text status indicator (disconnected/connected/moving/error)
%     - Menu control of NanoMotorControl.Verbosity
%     - Menu toggle to keep the figure always on top
%
%   See also NanoMotorControl, uigridlayout, uifigure, timer, serialport, uilamp, uimenu

    properties
        Parent = []
        Port (1,1) string = ""
        AutoDetect (1,1) logical = true
        UpdatePeriod (1,1) double {mustBePositive} = 0.25

        DefaultSpeedRPM (1,1) double {mustBeFinite} = 60
        DefaultMoveDeg (1,1) double {mustBeFinite} = 90
        DefaultMoveUnits (1,1) string = "deg"

        Verbosity (1,1) string = "SILENT"

        % If true, sets the hosting figure WindowStyle="alwaysontop".
        AlwaysOnTop (1,1) logical = false

        FigurePosition (1,4) double {mustBeFinite} = [100 100 420 320]
        FigureName (1,1) string = "Nano Motor Control"
    end

    properties (SetAccess=private)
        Motor NanoMotorControl = NanoMotorControl.empty
        Figure = []
        Grid = []
    end

    properties (Access=private)
        OwnsFigure (1,1) logical = false
        Busy (1,1) logical = false
        CleanupDone (1,1) logical = false

        Tmr = []
        Listeners = event.listener.empty

        JogActive (1,1) logical = false
        JogSign (1,1) double = 0
        PrevWinUpFcn = []
        PrevWinUpFcnStored (1,1) logical = false

        BaseBtnColor (1,3) double = [0.94 0.94 0.94]
        ActiveBtnColor (1,3) double = [0.80 0.90 0.80]

        ColorDisconnected (1,3) double = [0.60 0.60 0.60]
        ColorConnecting  (1,3) double = [0.95 0.80 0.20]
        ColorConnected   (1,3) double = [0.20 0.80 0.20]
        ColorMoving      (1,3) double = [0.20 0.40 0.90]
        ColorError       (1,3) double = [0.90 0.20 0.20]

        LastStatusState (1,1) string = ""
        LastStatusText (1,1) string = ""

        % Menus
        MenuRoot = []
        MenuVerbosity = []
        MiVerbSilent = []
        MiVerbInfo = []
        MiVerbDetailed = []

        MenuWindow = []
        MiAlwaysOnTop = []

        % UI
        LblStatus
        StatusGrid
        LampStatus
        LblStatusVal

        LblSpeed
        NumSpeed
        BtnCCW
        BtnCW

        BtnStop

        LblMove
        MoveGrid
        NumMoveDeg
        DdMoveUnits
        BtnMove

        MoveUnits (1,1) string = "deg"

        LblPos
        LblPosVal
    end

    methods
        function obj = NanoMotorControlGUI(opts)
            arguments
                opts.Parent = []
                opts.Port (1,1) string = ""
                opts.AutoDetect (1,1) logical = true
                opts.UpdatePeriod (1,1) double {mustBePositive} = 0.25
                opts.DefaultSpeedRPM (1,1) double {mustBeFinite} = 60
                opts.DefaultMoveDeg (1,1) double {mustBeFinite} = 90
                opts.DefaultMoveUnits (1,1) string = "deg"
                opts.Verbosity (1,1) string = "SILENT"
                opts.AlwaysOnTop (1,1) logical = false
                opts.FigurePosition (1,4) double {mustBeFinite} = [100 100 420 320]
                opts.FigureName (1,1) string = "Nano Motor Control"
            end

            obj.Parent = opts.Parent;
            obj.Port = opts.Port;
            obj.AutoDetect = opts.AutoDetect;
            obj.UpdatePeriod = opts.UpdatePeriod;
            obj.DefaultSpeedRPM = opts.DefaultSpeedRPM;
            obj.DefaultMoveDeg = opts.DefaultMoveDeg;
            obj.DefaultMoveUnits = lower(strtrim(opts.DefaultMoveUnits));
            mustBeMember(obj.DefaultMoveUnits, ["deg","rot"]);
            obj.MoveUnits = obj.DefaultMoveUnits;
            obj.FigurePosition = opts.FigurePosition;
            obj.FigureName = opts.FigureName;

            obj.Verbosity = upper(strtrim(string(opts.Verbosity)));
            mustBeMember(obj.Verbosity, ["SILENT","INFO","DETAILED"]);

            obj.AlwaysOnTop = logical(opts.AlwaysOnTop);

            obj.resolveParentAndFigure();
            obj.applyAlwaysOnTop();
            obj.buildMenus();
            obj.buildUI();

            try
                obj.setStatus("connecting", "(connecting...)");
                obj.connectMotor();
                obj.startTimer();
                obj.refreshUI();
            catch ME
                obj.setStatus("error", "Error: " + obj.shortMsg(ME.message));
                obj.cleanup();
                rethrow(ME);
            end
        end

        function delete(obj)
            obj.cleanup();
            if obj.OwnsFigure && ~isempty(obj.Figure) && isvalid(obj.Figure)
                delete(obj.Figure);
            end
        end
    end

    methods (Access=private)
        function resolveParentAndFigure(obj)
            if isempty(obj.Parent)
                obj.Figure = uifigure(Name=obj.FigureName, Position=obj.FigurePosition);
                obj.Parent = obj.Figure;
                obj.OwnsFigure = true;
                obj.Figure.CloseRequestFcn = @(src,evt)obj.onCloseRequest(src,evt);
                return;
            end

            if ~isgraphics(obj.Parent)
                error("NanoMotorControlGUI:InvalidParent", "Parent must be a valid graphics container handle.");
            end

            if isa(obj.Parent, "matlab.ui.Figure")
                obj.Figure = obj.Parent;
            else
                obj.Figure = ancestor(obj.Parent, "matlab.ui.Figure");
                if isempty(obj.Figure)
                    error("NanoMotorControlGUI:InvalidParent", "Could not find a parent uifigure for the provided container.");
                end
            end

            obj.OwnsFigure = false;

            obj.Listeners(end+1) = addlistener(obj.Figure, "ObjectBeingDestroyed", @(~,~)obj.cleanup());
            obj.Listeners(end+1) = addlistener(obj.Parent, "ObjectBeingDestroyed", @(~,~)obj.cleanup());
        end

        function buildMenus(obj)
            if isempty(obj.Figure) || ~isvalid(obj.Figure)
                return;
            end

            obj.MenuRoot = uimenu(obj.Figure, Text="NanoMotor");

            obj.MenuVerbosity = uimenu(obj.MenuRoot, Text="Verbosity");
            obj.MiVerbSilent = uimenu(obj.MenuVerbosity, Text="Silent", ...
                MenuSelectedFcn=@(~,~)obj.onVerbositySelected("SILENT"));
            obj.MiVerbInfo = uimenu(obj.MenuVerbosity, Text="Info", ...
                MenuSelectedFcn=@(~,~)obj.onVerbositySelected("INFO"));
            obj.MiVerbDetailed = uimenu(obj.MenuVerbosity, Text="Detailed", ...
                MenuSelectedFcn=@(~,~)obj.onVerbositySelected("DETAILED"));

            obj.MenuWindow = uimenu(obj.MenuRoot, Text="Window");
            obj.MiAlwaysOnTop = uimenu(obj.MenuWindow, Text="Always on top", ...
                MenuSelectedFcn=@(~,~)obj.onAlwaysOnTopToggled());

            obj.applyVerbosityChecks();
            obj.applyAlwaysOnTopChecks();

            obj.trySetTooltip(obj.MenuRoot, "GUI options for NanoMotorControl.");
            obj.trySetTooltip(obj.MenuVerbosity, "Select how much the driver prints to the Command Window.");
            obj.trySetTooltip(obj.MiVerbSilent, "Print nothing.");
            obj.trySetTooltip(obj.MiVerbInfo, "Print brief, human-readable messages.");
            obj.trySetTooltip(obj.MiVerbDetailed, "Print all commands and replies (serial transcript).");

            obj.trySetTooltip(obj.MenuWindow, "Figure behavior.");
            obj.trySetTooltip(obj.MiAlwaysOnTop, "Toggle WindowStyle between normal and alwaysontop.");
        end

        function onAlwaysOnTopToggled(obj)
            obj.AlwaysOnTop = ~obj.AlwaysOnTop;
            obj.applyAlwaysOnTop();
            obj.applyAlwaysOnTopChecks();
        end

        function applyAlwaysOnTop(obj)
            if isempty(obj.Figure) || ~isvalid(obj.Figure)
                return;
            end

            if obj.AlwaysOnTop
                obj.Figure.WindowStyle = "alwaysontop";
            else
                obj.Figure.WindowStyle = "normal";
            end
        end

        function applyAlwaysOnTopChecks(obj)
            obj.setChecked(obj.MiAlwaysOnTop, obj.AlwaysOnTop);
        end

        function onVerbositySelected(obj, level)
            level = upper(strtrim(string(level)));
            mustBeMember(level, ["SILENT","INFO","DETAILED"]);

            obj.Verbosity = level;
            obj.applyVerbosityChecks();

            if ~isempty(obj.Motor) && obj.Motor.IsConnected
                obj.Motor.Verbosity = obj.Verbosity;
            end
        end

        function applyVerbosityChecks(obj)
            v = upper(strtrim(string(obj.Verbosity)));

            obj.setChecked(obj.MiVerbSilent, v == "SILENT");
            obj.setChecked(obj.MiVerbInfo, v == "INFO");
            obj.setChecked(obj.MiVerbDetailed, v == "DETAILED");
        end

        function setChecked(obj, h, tf) %#ok<INUSD>
            if isempty(h) || ~isvalid(h)
                return;
            end
            if tf
                h.Checked = "on";
            else
                h.Checked = "off";
            end
        end

        function trySetTooltip(obj, h, txt) %#ok<INUSD>
            if isempty(h) || ~isvalid(h)
                return;
            end
            if isprop(h, "Tooltip")
                h.Tooltip = txt;
            end
        end

        function buildUI(obj)
            obj.Grid = uigridlayout(obj.Parent, [6 2]);
            obj.Grid.Padding = [10 10 10 10];
            obj.Grid.RowSpacing = 10;
            obj.Grid.ColumnSpacing = 10;
            obj.Grid.RowHeight = {22, 44, 110, 44, 44, 22};
            obj.Grid.ColumnWidth = {'1x','1x'};

            obj.LblStatus = uilabel(obj.Grid, Text="Status:", HorizontalAlignment="right");
            obj.LblStatus.Layout.Row = 1;
            obj.LblStatus.Layout.Column = 1;
            obj.LblStatus.Tooltip = "Controller status (lamp + text).";

            obj.StatusGrid = uigridlayout(obj.Grid, [1 2]);
            obj.StatusGrid.Layout.Row = 1;
            obj.StatusGrid.Layout.Column = 2;
            obj.StatusGrid.Padding = [0 0 0 0];
            obj.StatusGrid.ColumnSpacing = 6;
            obj.StatusGrid.RowSpacing = 0;
            obj.StatusGrid.ColumnWidth = {18, '1x'};
            obj.StatusGrid.RowHeight = {22};

            obj.LampStatus = uilamp(obj.StatusGrid);
            obj.LampStatus.Layout.Row = 1;
            obj.LampStatus.Layout.Column = 1;
            obj.LampStatus.Color = obj.ColorDisconnected;
            obj.LampStatus.Tooltip = "Gray=disconnected, Yellow=connecting/busy, Green=connected, Blue=moving, Red=error.";

            obj.LblStatusVal = uilabel(obj.StatusGrid, Text="(connecting...)", FontWeight="bold");
            obj.LblStatusVal.Layout.Row = 1;
            obj.LblStatusVal.Layout.Column = 2;
            obj.LblStatusVal.Tooltip = "Text status (port, motion state, or error message).";

            obj.LblSpeed = uilabel(obj.Grid, Text="Speed (RPM):", HorizontalAlignment="right");
            obj.LblSpeed.Layout.Row = 2;
            obj.LblSpeed.Layout.Column = 1;
            obj.LblSpeed.Tooltip = "Jog speed and optional MOVE speed.";

            obj.NumSpeed = uieditfield(obj.Grid, "numeric", Value=obj.DefaultSpeedRPM);
            obj.NumSpeed.Layout.Row = 2;
            obj.NumSpeed.Layout.Column = 2;
            obj.NumSpeed.Limits = [0 240];
            obj.NumSpeed.RoundFractionalValues = "off";
            obj.NumSpeed.ValueDisplayFormat = "%.3g";
            obj.NumSpeed.ValueChangedFcn = @(src,evt)obj.onSpeedChanged(src,evt);
            obj.NumSpeed.Tooltip = "Rotation speed in RPM. Used for jog and, if >0, passed to MOVE.";

            obj.BtnCCW = uibutton(obj.Grid, Text="CCW", FontSize=20, FontWeight="bold");
            obj.BtnCCW.Layout.Row = 3;
            obj.BtnCCW.Layout.Column = 1;
            obj.BtnCCW.BackgroundColor = obj.BaseBtnColor;
            obj.BtnCCW.ButtonPushedFcn = @(src,evt)obj.onJogDown(-1,src,evt);
            obj.BtnCCW.Tooltip = "Jog CCW at Speed(RPM). Click to start; click again or press STOP to stop.";

            obj.BtnCW = uibutton(obj.Grid, Text="CW", FontSize=20, FontWeight="bold");
            obj.BtnCW.Layout.Row = 3;
            obj.BtnCW.Layout.Column = 2;
            obj.BtnCW.BackgroundColor = obj.BaseBtnColor;
            obj.BtnCW.ButtonPushedFcn = @(src,evt)obj.onJogDown(+1,src,evt);
            obj.BtnCW.Tooltip = "Jog CW at Speed(RPM). Click to start; click again or press STOP to stop.";

            obj.BtnStop = uibutton(obj.Grid, Text="STOP", FontSize=16);
            obj.BtnStop.Layout.Row = 4;
            obj.BtnStop.Layout.Column = [1 2];
            obj.BtnStop.ButtonPushedFcn = @(src,evt)obj.onStopPressed(src,evt);
            obj.BtnStop.Tooltip = "Send STOP (halts jog and stops any active MOVE).";

            obj.LblMove = uilabel(obj.Grid, Text="Move:", HorizontalAlignment="right");
            obj.LblMove.Layout.Row = 5;
            obj.LblMove.Layout.Column = 1;
            obj.LblMove.Tooltip = "Move amount and units (degrees or rotations).";

            obj.MoveGrid = uigridlayout(obj.Grid, [1 3]);
            obj.MoveGrid.Layout.Row = 5;
            obj.MoveGrid.Layout.Column = 2;
            obj.MoveGrid.Padding = [0 0 0 0];
            obj.MoveGrid.ColumnSpacing = 6;
            obj.MoveGrid.RowSpacing = 0;
            obj.MoveGrid.ColumnWidth = {'1x', 70, 60};

            v0 = obj.DefaultMoveDeg;
            if obj.MoveUnits == "rot"
                v0 = v0/360;
            end

            obj.NumMoveDeg = uieditfield(obj.MoveGrid, "numeric", Value=v0);
            obj.NumMoveDeg.Layout.Row = 1;
            obj.NumMoveDeg.Layout.Column = 1;
            obj.NumMoveDeg.RoundFractionalValues = "off";
            obj.NumMoveDeg.ValueDisplayFormat = "%.6g";
            obj.NumMoveDeg.Tooltip = "Move magnitude in selected units. Rotations may be fractional; sign controls direction.";

            obj.DdMoveUnits = uidropdown(obj.MoveGrid, Items=["deg","rot"], Value=obj.MoveUnits);
            obj.DdMoveUnits.Layout.Row = 1;
            obj.DdMoveUnits.Layout.Column = 2;
            obj.DdMoveUnits.ValueChangedFcn = @(src,evt)obj.onMoveUnitsChanged(src,evt);
            obj.DdMoveUnits.Tooltip = "Select units: degrees or rotations (1 rot = 360 deg).";

            obj.BtnMove = uibutton(obj.MoveGrid, Text="Move");
            obj.BtnMove.Layout.Row = 1;
            obj.BtnMove.Layout.Column = 3;
            obj.BtnMove.ButtonPushedFcn = @(src,evt)obj.onMovePressed(src,evt);
            obj.BtnMove.Tooltip = "Send MOVE command using the value/units. Uses Speed(RPM) if > 0.";

            obj.applyMoveUnitsFormatting();

            obj.LblPos = uilabel(obj.Grid, Text="Position (deg):", HorizontalAlignment="right");
            obj.LblPos.Layout.Row = 6;
            obj.LblPos.Layout.Column = 1;
            obj.LblPos.Tooltip = "Commanded/open-loop position returned by POSD?.";

            obj.LblPosVal = uilabel(obj.Grid, Text="--", FontWeight="bold");
            obj.LblPosVal.Layout.Row = 6;
            obj.LblPosVal.Layout.Column = 2;
            obj.LblPosVal.Tooltip = "Commanded/open-loop position (deg) returned by POSD?.";

            obj.setStatus("disconnected", "(not connected)");
        end

        function connectMotor(obj)
            obj.Motor = NanoMotorControl(Port=obj.Port, AutoDetect=obj.AutoDetect, Verbosity=obj.Verbosity);
            obj.Motor.connect(Port=obj.Port, AutoDetect=obj.AutoDetect);
            obj.Motor.mode("USB");
            obj.Motor.enable(true);

            % Pull limits from device if available
            S = obj.Motor.status();
            if isfield(S, "LIMRPM")
                lim = double(S.LIMRPM);
                if isfinite(lim) && lim > 0
                    obj.NumSpeed.Limits = [0 lim];
                    if obj.NumSpeed.Value > lim
                        obj.NumSpeed.Value = lim;
                    end
                end
            end

            obj.applyVerbosityChecks();
            obj.setStatus("connected", obj.connectedText());
        end

        function startTimer(obj)
            obj.Tmr = timer(...
                ExecutionMode="fixedSpacing", ...
                Period=obj.UpdatePeriod, ...
                TimerFcn=@(~,~)obj.onTimerTick());
            start(obj.Tmr);
        end

        function onTimerTick(obj)
            if obj.CleanupDone || obj.Busy
                return;
            end
            if isempty(obj.Motor) || ~obj.Motor.IsConnected
                obj.setStatus("disconnected", "Disconnected");
                return;
            end

            obj.Busy = true;
            c = onCleanup(@()obj.clearBusy());

            try
                posDeg = obj.Motor.positionDeg();
                if ~isempty(obj.LblPosVal) && isvalid(obj.LblPosVal)
                    obj.LblPosVal.Text = sprintf("%.6g", posDeg);
                end

                [state, txt] = obj.inferMotionStatus();
                obj.setStatus(state, txt);
            catch ME
                obj.setStatus("error", "Error: " + obj.shortMsg(ME.message));
            end
        end

        function [state, txt] = inferMotionStatus(obj)
            state = "connected";
            txt = obj.connectedText();

            if obj.JogActive
                state = "moving";
                if obj.JogSign < 0
                    dirTxt = "CCW";
                else
                    dirTxt = "CW";
                end
                txt = sprintf("Jogging %s @ %.4g RPM", dirTxt, abs(obj.NumSpeed.Value));
                return;
            end

            try
                M = obj.Motor.moveQuery();
                if isfield(M,"Active") && islogical(M.Active) && M.Active
                    state = "moving";
                    txt = "Moving";
                    if isfield(M,"REMDEG")
                        try
                            txt = txt + sprintf(" | REM=%.3f deg", double(M.REMDEG));
                        catch
                        end
                    end
                end
            catch
            end
        end

        function onSpeedChanged(obj, src, evt) %#ok<INUSD>
            if obj.CleanupDone || isempty(obj.Motor) || ~obj.Motor.IsConnected
                return;
            end

            if obj.JogActive
                sgn = obj.JogSign;
                rpm = sgn * abs(src.Value);
                obj.safeSend(@()obj.Motor.setRPM(rpm));
            end
        end

        function onJogDown(obj, sign, src, evt) %#ok<INUSL>
            if obj.CleanupDone || isempty(obj.Motor) || ~obj.Motor.IsConnected
                return;
            end

            if obj.JogActive && obj.JogSign == sign
                obj.stopJog();
                return;
            end

            if obj.JogActive
                obj.stopJog();
            end

            obj.JogActive = true;
            obj.JogSign = sign;

            rpm = sign * abs(obj.NumSpeed.Value);
            if rpm == 0
                rpm = sign * 1;
            end

            obj.setJogVisual(sign, true);

            [state, txt] = obj.inferMotionStatus();
            obj.setStatus(state, txt);

            obj.safeSend(@()obj.Motor.setRPM(rpm));

            [state, txt] = obj.inferMotionStatus();
            obj.setStatus(state, txt);
        end

        function stopJog(obj)
            if ~obj.JogActive
                return;
            end

            obj.JogActive = false;
            sign = obj.JogSign;
            obj.JogSign = 0;

            obj.setJogVisual(sign, false);

            if isempty(obj.Motor) || ~obj.Motor.IsConnected
                obj.setStatus("disconnected", "Disconnected");
                return;
            end

            obj.safeSend(@()obj.Motor.setRPM(0));
            obj.setStatus("connected", obj.connectedText());
        end

        function onStopPressed(obj, src, evt) %#ok<INUSD>
            if obj.CleanupDone || isempty(obj.Motor) || ~obj.Motor.IsConnected
                return;
            end

            obj.stopJog();
            obj.safeSend(@()obj.Motor.stop());
            obj.setStatus("connected", obj.connectedText());
        end

        function onMoveUnitsChanged(obj, src, evt) %#ok<INUSD>
            if isempty(obj.DdMoveUnits) || ~isvalid(obj.DdMoveUnits)
                return;
            end

            newUnits = lower(strtrim(string(src.Value)));
            mustBeMember(newUnits, ["deg","rot"]);

            oldUnits = obj.MoveUnits;
            if oldUnits == ""
                oldUnits = newUnits;
            end

            if oldUnits ~= newUnits && ~isempty(obj.NumMoveDeg) && isvalid(obj.NumMoveDeg)
                v = obj.NumMoveDeg.Value;
                if oldUnits == "deg" && newUnits == "rot"
                    obj.NumMoveDeg.Value = v/360;
                elseif oldUnits == "rot" && newUnits == "deg"
                    obj.NumMoveDeg.Value = v*360;
                end
            end

            obj.MoveUnits = newUnits;
            obj.applyMoveUnitsFormatting();
        end

        function applyMoveUnitsFormatting(obj)
            if isempty(obj.LblMove) || ~isvalid(obj.LblMove) || isempty(obj.NumMoveDeg) || ~isvalid(obj.NumMoveDeg)
                return;
            end

            maxAbsDeg = 36000;
            units = obj.MoveUnits;

            if units == "rot"
                maxAbs = maxAbsDeg/360;
                obj.LblMove.Text = "Move (rot):";
            else
                maxAbs = maxAbsDeg;
                obj.LblMove.Text = "Move (deg):";
            end

            obj.NumMoveDeg.Limits = [-maxAbs maxAbs];

            if obj.NumMoveDeg.Value < -maxAbs
                obj.NumMoveDeg.Value = -maxAbs;
            elseif obj.NumMoveDeg.Value > maxAbs
                obj.NumMoveDeg.Value = maxAbs;
            end
        end

        function onMovePressed(obj, src, evt) %#ok<INUSD>
            if obj.CleanupDone || isempty(obj.Motor) || ~obj.Motor.IsConnected
                return;
            end

            amount = obj.NumMoveDeg.Value;
            deg = amount;
            if obj.MoveUnits == "rot"
                deg = amount * 360;
            end
            rpmMag = abs(obj.NumSpeed.Value);

            obj.stopJog();
            obj.safeSend(@()obj.Motor.stop());

            obj.setStatus("moving", "Moving");
            if rpmMag > 0
                obj.safeSend(@()obj.Motor.moveDeg(deg, rpmMag));
            else
                obj.safeSend(@()obj.Motor.moveDeg(deg));
            end
        end

        function onCloseRequest(obj, src, evt) %#ok<INUSD>
            obj.cleanup();
            delete(src);
        end

        function refreshUI(obj)
            if isempty(obj.Motor) || ~obj.Motor.IsConnected
                obj.setStatus("disconnected", "Disconnected");
                return;
            end

            obj.LblPosVal.Text = sprintf("%.6g", obj.Motor.positionDeg());

            obj.applyVerbosityChecks();
            obj.applyAlwaysOnTopChecks();
            obj.setStatus("connected", obj.connectedText());
        end

        function cleanup(obj)
            if obj.CleanupDone
                return;
            end
            obj.CleanupDone = true;

            obj.stopJog();

            if ~isempty(obj.Tmr) && isvalid(obj.Tmr)
                stop(obj.Tmr);
                delete(obj.Tmr);
            end
            obj.Tmr = [];

            if ~isempty(obj.Motor) && obj.Motor.IsConnected
                obj.Motor.stop();
                obj.Motor.disconnect();
            end
            obj.Motor = NanoMotorControl.empty;

            if ~isempty(obj.Listeners)
                L = obj.Listeners;
                L = L(isvalid(L));
                if ~isempty(L)
                    delete(L);
                end
            end
            obj.Listeners = event.listener.empty;

            if ~obj.OwnsFigure && ~isempty(obj.MenuRoot) && isvalid(obj.MenuRoot)
                delete(obj.MenuRoot);
            end

            obj.setStatus("disconnected", "Disconnected");
        end

        function safeSend(obj, fcn)
            if obj.CleanupDone || obj.Busy
                return;
            end
            obj.Busy = true;
            c = onCleanup(@()obj.clearBusy());
            try
                fcn();
            catch ME
                obj.setStatus("error", "Error: " + obj.shortMsg(ME.message));
            end
        end

        function clearBusy(obj)
            obj.Busy = false;
        end

        function setJogVisual(obj, sign, tf)
            if sign < 0
                if ~isempty(obj.BtnCCW) && isvalid(obj.BtnCCW)
                    obj.BtnCCW.BackgroundColor = tf*obj.ActiveBtnColor + (~tf)*obj.BaseBtnColor;
                end
            else
                if ~isempty(obj.BtnCW) && isvalid(obj.BtnCW)
                    obj.BtnCW.BackgroundColor = tf*obj.ActiveBtnColor + (~tf)*obj.BaseBtnColor;
                end
            end
        end

        function txt = connectedText(obj)
            port = "";
            if ~isempty(obj.Motor) && obj.Motor.IsConnected
                port = obj.Motor.Port;
            end

            if port ~= ""
                txt = "Connected (" + string(port) + ")";
            else
                txt = "Connected";
            end
        end

        function setStatus(obj, state, text)
            if nargin < 3
                text = "";
            end
            state = lower(strtrim(string(state)));
            text = string(text);

            if state == obj.LastStatusState && text == obj.LastStatusText
                return;
            end
            obj.LastStatusState = state;
            obj.LastStatusText = text;

            if ~isempty(obj.LampStatus) && isvalid(obj.LampStatus)
                obj.LampStatus.Color = obj.colorForState(state);
            end
            if ~isempty(obj.LblStatusVal) && isvalid(obj.LblStatusVal)
                obj.LblStatusVal.Text = text;
            end
        end

        function c = colorForState(obj, state)
            switch state
                case "disconnected"
                    c = obj.ColorDisconnected;
                case "connecting"
                    c = obj.ColorConnecting;
                case "connected"
                    c = obj.ColorConnected;
                case "moving"
                    c = obj.ColorMoving;
                case "error"
                    c = obj.ColorError;
                otherwise
                    c = obj.ColorDisconnected;
            end
        end

        function s = shortMsg(obj, msg)
            s = string(msg);
            s = replace(s, newline, " ");
            if strlength(s) > 90
                s = extractBefore(s, 90) + "...";
            end
        end
    end
end
