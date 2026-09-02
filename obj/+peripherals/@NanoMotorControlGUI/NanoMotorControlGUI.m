classdef NanoMotorControlGUI < handle
%NANAMOTORCONTROLGUI GUI front-end for NanoMotorControl.
%
%   peripherals.NanoMotorControlGUI builds a compact uigridlayout-based
%   control panel for the peripherals.NanoMotorControl serial interface.
%
%   Capabilities
%     - Jog in either direction (click-to-toggle), each button carrying a
%       circular-arrow icon for the rotation it commands
%     - Menu option to swap which button reads CW and which reads CCW
%     - Set rotation speed (RPM)
%     - Send MOVEDEG commands using either degrees or rotations
%     - STOP (halts jogging and stops any active MOVE)
%     - Display current commanded position (degrees)
%     - Lamp + text status indicator (disconnected/connected/moving/error)
%     - Menu control of peripherals.NanoMotorControl.Verbosity
%     - Menu toggle to keep the figure always on top
%
%   See also peripherals.NanoMotorControl, uigridlayout, uifigure, timer, serialport, uilamp, uimenu

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

        % Swap which jog button reads CW and which reads CCW. Jog commands
        % (DIR/SPD/RPM) act in MOTOR direction, while moveDeg/positionDeg are
        % output-shaft degrees the firmware already corrects with its gear
        % OutputDirSign -- so on a drive that reverses, the jog buttons are the
        % half that reads backwards. A swap moves the labels, icons, tooltips
        % and status text only; MOVE and the position readout are untouched.
        % Left unstated, the GUI takes the controller's OutputDirSign at
        % connect; toggling it from the menu remembers the choice per machine.
        SwapDirectionLabels (1,1) logical = false

        FigurePosition (1,4) double {mustBeFinite} = [100 100 420 320]
        FigureName (1,1) string = "Nano Motor Control"
    end

    properties (SetAccess=private)
        Motor peripherals.NanoMotorControl = peripherals.NanoMotorControl.empty
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
        SwapExplicit_ (1,1) logical = false
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

        MenuDirection = []
        MiSwapLabels = []

        % UI
        LblStatus
        StatusGrid
        LampStatus
        LblStatusVal

        LblSpeed
        NumSpeed
        % Named for the MOTOR direction each button commands, never for what it
        % says: a swap moves text and icons, not the wiring.
        BtnJogNeg
        BtnJogPos

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

    properties (Constant, Access=private)
        PREF_GROUP = 'epsych2_peripherals_NanoMotorControlGUI'
        PREF_SWAP = 'SwapDirectionLabels'

        % Glyph edge in pixels, sized for the 110 px jog row rather than
        % gui.toolbarIcon's 16 px toolbar tools.
        ICON_SIZE = 58
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
                opts.SwapDirectionLabels (1,1) logical   % no default: unstated falls back to the saved choice, then the device
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

            obj.resolveSwapDirectionLabels(opts);

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

        function set.SwapDirectionLabels(obj, tf)
            obj.SwapDirectionLabels = logical(tf);

            % A set method may not touch another property, so what counts as a
            % deliberate choice is recorded where the choice is made
            % (resolveSwapDirectionLabels, onSwapLabelsToggled) rather than here.
            obj.applyDirectionLabels();
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

            obj.MenuDirection = uimenu(obj.MenuRoot, Text="Direction");
            obj.MiSwapLabels = uimenu(obj.MenuDirection, Text="Swap CW / CCW labels", ...
                MenuSelectedFcn=@(~,~)obj.onSwapLabelsToggled());

            obj.applyVerbosityChecks();
            obj.applyAlwaysOnTopChecks();

            obj.trySetTooltip(obj.MenuRoot, "GUI options for NanoMotorControl.");
            obj.trySetTooltip(obj.MenuVerbosity, "Select how much the driver prints to the Command Window.");
            obj.trySetTooltip(obj.MiVerbSilent, "Print nothing.");
            obj.trySetTooltip(obj.MiVerbInfo, "Print brief, human-readable messages.");
            obj.trySetTooltip(obj.MiVerbDetailed, "Print all commands and replies (serial transcript).");

            obj.trySetTooltip(obj.MenuWindow, "Figure behavior.");
            obj.trySetTooltip(obj.MiAlwaysOnTop, "Toggle WindowStyle between normal and alwaysontop.");

            obj.trySetTooltip(obj.MenuDirection, "How the two jog buttons are labelled.");
            obj.trySetTooltip(obj.MiSwapLabels, "Swap which jog button reads CW and which reads CCW. Labels, icons and status text only; MOVE and the position readout are unaffected.");

            obj.applyDirectionChecks();
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

            % Labels, icons and tooltips are applied together by
            % applyDirectionLabels so the swap has one place to reach them.
            obj.BtnJogNeg = uibutton(obj.Grid, FontSize=20, FontWeight="bold");
            obj.BtnJogNeg.Layout.Row = 3;
            obj.BtnJogNeg.Layout.Column = 1;
            obj.BtnJogNeg.BackgroundColor = obj.BaseBtnColor;
            obj.BtnJogNeg.IconAlignment = "top";
            obj.BtnJogNeg.ButtonPushedFcn = @(src,evt)obj.onJogDown(-1,src,evt);

            obj.BtnJogPos = uibutton(obj.Grid, FontSize=20, FontWeight="bold");
            obj.BtnJogPos.Layout.Row = 3;
            obj.BtnJogPos.Layout.Column = 2;
            obj.BtnJogPos.BackgroundColor = obj.BaseBtnColor;
            obj.BtnJogPos.IconAlignment = "top";
            obj.BtnJogPos.ButtonPushedFcn = @(src,evt)obj.onJogDown(+1,src,evt);

            obj.applyDirectionLabels();

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
            obj.Motor = peripherals.NanoMotorControl(Port=obj.Port, AutoDetect=obj.AutoDetect, Verbosity=obj.Verbosity);
            obj.Motor.connect(Port=obj.Port, AutoDetect=obj.AutoDetect);
            obj.Motor.mode("USB");
            obj.Motor.enable(true);

            obj.adoptSwapFromDevice();

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
                dirTxt = obj.directionName(obj.JogSign);
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
            obj.Motor = peripherals.NanoMotorControl.empty;

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
                b = obj.BtnJogNeg;
            else
                b = obj.BtnJogPos;
            end

            if isempty(b) || ~isvalid(b)
                return;
            end

            if tf
                b.BackgroundColor = obj.ActiveBtnColor;
            else
                b.BackgroundColor = obj.BaseBtnColor;
            end

            % The glyph's soft edge is blended against the button it sits on, so
            % it has to be redrawn whenever that button changes colour.
            obj.applyDirectionIcons();
        end

        function name = directionName(obj, sign)
            % A negative motor sign reads CCW unless the labels are swapped for
            % a drive that reverses the output shaft.
            if xor(sign < 0, obj.SwapDirectionLabels)
                name = "CCW";
            else
                name = "CW";
            end
        end

        function applyDirectionLabels(obj)
            signs = [-1 1];
            btns = {obj.BtnJogNeg, obj.BtnJogPos};

            for k = 1:numel(btns)
                b = btns{k};
                if isempty(b) || ~isvalid(b)
                    continue;
                end

                name = obj.directionName(signs(k));
                b.Text = name;
                b.Tooltip = "Jog " + name + " at Speed(RPM). Click to start; click again or press STOP to stop.";
            end

            obj.applyDirectionIcons();
            obj.applyDirectionChecks();

            % The status line names the direction too, so a swap mid-jog reaches
            % it without waiting for the next poll.
            if obj.JogActive
                [state, txt] = obj.inferMotionStatus();
                obj.setStatus(state, txt);
            end
        end

        function applyDirectionIcons(obj)
            signs = [-1 1];
            btns = {obj.BtnJogNeg, obj.BtnJogPos};

            for k = 1:numel(btns)
                b = btns{k};
                if isempty(b) || ~isvalid(b)
                    continue;
                end

                cw = obj.directionName(signs(k)) == "CW";
                b.Icon = obj.rotationIcon(cw, obj.ICON_SIZE, b.BackgroundColor);
            end
        end

        function applyDirectionChecks(obj)
            obj.setChecked(obj.MiSwapLabels, obj.SwapDirectionLabels);
        end

        function resolveSwapDirectionLabels(obj, opts)
            % Three sources, most specific first: what the caller stated, what
            % this machine last chose from the menu, and -- left to
            % adoptSwapFromDevice -- the controller's own OutputDirSign.
            obj.SwapExplicit_ = true;

            if isfield(opts, "SwapDirectionLabels")
                obj.SwapDirectionLabels = logical(opts.SwapDirectionLabels);
                return;
            end

            if ispref(obj.PREF_GROUP, obj.PREF_SWAP)
                obj.SwapDirectionLabels = logical(getpref(obj.PREF_GROUP, obj.PREF_SWAP));
            else
                % Nothing stated and nothing remembered: leave it to the device.
                obj.SwapExplicit_ = false;
            end
        end

        function adoptSwapFromDevice(obj)
            if obj.SwapExplicit_ || isempty(obj.Motor) || ~obj.Motor.IsConnected
                return;
            end

            % connect() has just read the firmware's gear configuration, and a
            % reversing drive is the case the swap exists for. This is a starting
            % point rather than a choice, so it never raises SwapExplicit_ and an
            % operator toggle still outranks it.
            obj.SwapDirectionLabels = obj.Motor.OutputDirSign < 0;
        end

        function onSwapLabelsToggled(obj)
            obj.SwapDirectionLabels = ~obj.SwapDirectionLabels;
            obj.SwapExplicit_ = true;

            % Which way a rig's gearbox turns is a fact about the bench, not
            % about this session, so the operator's answer is remembered.
            setpref(obj.PREF_GROUP, obj.PREF_SWAP, obj.SwapDirectionLabels);
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

    methods (Static, Access=private)
        function icon = rotationIcon(clockwise, sz, blendColor)
            % icon = rotationIcon(clockwise, sz, blendColor)
            % Circular-arrow glyph for one jog button.
            %
            % Drawn here rather than shipped as an image file, for
            % gui.toolbarIcon's reasons, but sized for a 110 px jog row instead
            % of a 16 px toolbar tool. Empty pixels are NaN, which uibutton
            % renders transparent; the partly covered edge has to be blended
            % against something, and the button it sits on is the only right
            % answer -- these buttons turn green while jogging.
            arguments
                clockwise (1,1) logical
                sz (1,1) double {mustBePositive}
                blendColor (1,3) double = [0.94 0.94 0.94]
            end

            glyph = [0.20 0.22 0.26];   % gui.toolbarIcon's outline colour

            ss = 3;                     % supersampling factor
            n = sz*ss;
            v = linspace(-1, 1, n);
            [X, Y] = meshgrid(v, v);
            Y = -Y;                     % image rows run top-down; draw with y up

            rMid = 0.57;
            halfWidth = 0.115;
            gapCenter = 90;             % opening at the top, as in the Unicode arrows
            gapHalf = 62;
            headSpan = 48;              % arrowhead length, degrees
            headHalf = 0.31;            % arrowhead half-height, normalized radius

            ang = mod(atan2(Y, X)*180/pi, 360);
            ring = abs(hypot(X, Y) - rMid) <= halfWidth;
            inGap = abs(mod(ang - gapCenter + 180, 360) - 180) < gapHalf;
            mask = ring & ~inGap;

            % Counter-clockwise travel ends where the gap begins, at the upper
            % right, and the head fills the gap from there, so the glyph reads as
            % travel rather than as a broken ring.
            aEnd = (gapCenter - gapHalf)*pi/180;
            aTip = (gapCenter - gapHalf + headSpan)*pi/180;
            p1 = (rMid + headHalf)*[cos(aEnd) sin(aEnd)];
            p2 = (rMid - headHalf)*[cos(aEnd) sin(aEnd)];
            p3 = rMid*[cos(aTip) sin(aTip)];

            s1 = (p2(1)-p1(1)).*(Y-p1(2)) - (p2(2)-p1(2)).*(X-p1(1));
            s2 = (p3(1)-p2(1)).*(Y-p2(2)) - (p3(2)-p2(2)).*(X-p2(1));
            s3 = (p1(1)-p3(1)).*(Y-p3(2)) - (p1(2)-p3(2)).*(X-p3(1));
            headMask = (s1 >= 0 & s2 >= 0 & s3 >= 0) | (s1 <= 0 & s2 <= 0 & s3 <= 0);

            mask = mask | headMask;

            if clockwise
                mask = fliplr(mask);    % the clockwise glyph is the mirror image
            end

            % Block-average the supersampled mask into per-pixel coverage.
            alpha = squeeze(mean(mean(reshape(double(mask), ss, sz, ss, sz), 1), 3));
            hit = alpha > 0;

            icon = nan(sz, sz, 3);
            for k = 1:3
                ch = nan(sz, sz);
                ch(hit) = glyph(k)*alpha(hit) + blendColor(k)*(1 - alpha(hit));
                icon(:,:,k) = ch;
            end
        end
    end
end
