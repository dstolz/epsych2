classdef NanoMotor < gui.PopOut
    % obj = gui.components.NanoMotor(source, container, Name=Value)
    % Operator panel for the Arduino Nano DM320T stepper controller
    % (peripherals.NanoMotorControl) -- the motorized commutator -- built to
    % sit inside a gui.BehaviorGUI rather than in a window of its own.
    %
    % It is peripherals.NanoMotorControlGUI's job in a component's shape,
    % and it differs from that class in three ways:
    %
    %   1. It NEVER opens the serial port on its own. The constructor makes
    %      the driver object and stops there; the link opens when the
    %      operator presses Connect (or a paradigm calls connect). A rig
    %      whose commutator is switched off, unplugged, or being driven from
    %      another MATLAB still gets its behavior GUI -- the old window
    %      connected from its constructor and rethrew, so a missing
    %      controller took the window with it.
    %   2. The layout is one column of short rows with no label column:
    %      units live inside the fields ("60 RPM"), the port row doubles as
    %      the connection status, and the whole panel is ~150 px tall
    %      against the old window's 320. Every row is individually hideable,
    %      so a rig that only ever nudges the commutator can show two.
    %   3. It is a gui.PopOut, so the same panel opens in a window of its
    %      own -- and with ButtonOnly=true it IS just that button, for a GUI
    %      with no room to spare.
    %
    % The panel drives a controller handed to it, or one it constructs
    % itself, so it opens with or without hardware anywhere near it.
    %
    % Properties:
    %   SpeedRPM     - Jog speed, and the speed a Move is sent at (motor RPM)
    %   MoveAmount   - Move magnitude, in MoveUnits
    %   MoveUnits    - 'deg' (output-shaft degrees) or 'rot' (1 rot = 360 deg)
    %   Port         - Serial port selected in the panel
    %   Verbosity    - Driver print level: 'SILENT', 'INFO', 'DETAILED'
    %   SwapDirectionLabels - Exchange what the jog buttons SAY, for a drive
    %                  that reverses the output shaft (never what they send)
    %   Sections     - Parts of the panel currently shown (see SECTIONS)
    %   Motor        - The peripherals.NanoMotorControl being driven
    %   IsConnected  - True while the serial link is open (Dependent)
    %   IsJogging    - True while a jog is running (Dependent)
    %   PositionDeg  - Output-shaft position as of the last poll
    %   Status       - Status text as of the last poll
    %   ContextMenu  - The right-click menu; host GUIs may append items
    %
    % Methods:
    %   connect / disconnect  - Open or close the link on the selected port
    %   detectPort            - Probe the serial ports for a controller
    %   refreshPorts          - Re-read the serial port list into the dropdown
    %   jog / stopJog         - Start or stop continuous rotation
    %   stopMotion            - STOP: end a jog and cancel any running move
    %   move                  - Send MOVEDEG for MoveAmount in MoveUnits
    %   zeroPosition          - Set the position counter to zero
    %   show / hide           - Show or hide parts of the panel by name
    %   startPolling / stopPolling - Resume / pause the position readout
    %
    % Examples:
    %   % Inside a gui.BehaviorGUI build method
    %   obj.add('gui.components.NanoMotor', panelRig);
    %
    %   % Just a button; the panel lives in the window it opens
    %   obj.add('gui.components.NanoMotor', toolRow, ButtonOnly=true);
    %
    %   % Only the link and the jog controls, on a known port
    %   obj.add('gui.components.NanoMotor', panelRig, ...
    %       Port='COM6', Sections=["Link","Status","Jog","Stop"]);
    %
    %   % Standalone, no session
    %   f = uifigure('Name','Commutator');
    %   m = gui.components.NanoMotor([], f);
    %
    % See also: documentation/gui/gui_NanoMotor.md,
    % peripherals.NanoMotorControl, gui.BehaviorGUI.add, gui.PopOut,
    % gui.components.SyringePump

    properties
        % Jog speed in MOTOR RPM, and the speed a Move is sent at. Zero
        % means "the controller's own default" for a move; a jog at zero
        % would not turn, so it is sent as 1 RPM.
        SpeedRPM (1,1) double {mustBeNonnegative, mustBeFinite} = 60

        % Move magnitude in MoveUnits. Signed: negative moves the other way.
        MoveAmount (1,1) double {mustBeFinite} = 90

        % Units the move is expressed in. Output-shaft degrees, or whole
        % output revolutions (1 rot = 360 deg). Changing them converts
        % MoveAmount, so the move stays the same size.
        MoveUnits (1,:) char {mustBeMember(MoveUnits, {'deg','rot'})} = 'deg'

        % How much the driver prints while this panel drives it. 'DETAILED'
        % is the full serial transcript, which is what to turn on when the
        % controller is answering something unexpected.
        Verbosity (1,:) char {mustBeMember(Verbosity, {'SILENT','INFO','DETAILED'})} = 'SILENT'

        % Exchange what the two jog buttons SAY. A jog commands the motor,
        % while the position readout and a move are output-shaft quantities
        % the firmware has already corrected for a drive that reverses -- so
        % on such a drive the jog labels are the half that reads backwards.
        % A swap moves text and tooltips only: each button keeps commanding
        % the motor direction it always did, and jog(+1) is still motor CW.
        SwapDirectionLabels (1,1) logical = false

        % Parts of the panel that are shown, as a string array of section
        % names (see SECTIONS). Assign it -- or call show/hide -- at any
        % time; the panel reflows and no control loses its state. Group
        % aliases are expanded on assignment, so this always reads back as
        % the individual names it resolved to.
        Sections (1,:) string = gui.components.NanoMotor.SECTIONS
    end

    properties (SetAccess = private)
        Parent                             % Hosting container supplied at construction
        Motor = []                         % peripherals.NanoMotorControl this panel drives
        UpdatePeriod (1,1) double = 0.5    % position readout period, seconds

        PositionDeg (1,1) double = NaN     % output-shaft degrees, last poll
        Status (1,:) char = ''             % status text, last poll

        Timer = []                         % readout timer
        ContextMenu = []                   % right-click menu
    end

    properties (Dependent)
        IsConnected  % True while the serial link is open
        IsJogging    % True while a jog is running
        IsButtonOnly % True when this instance is just a button
        Port         % Serial port selected in the panel
    end

    properties (Access = private)
        OwnsMotor_ (1,1) logical = false  % close and delete the driver on teardown
        ButtonOnly_ (1,1) logical = false % this instance is one button, no panel
        ReviewMode_ (1,1) logical = false % a reviewed session drives no hardware
        Runtime_ = []                     % session the actions are recorded against

        StagedPort_ (1,:) char = ''       % port chosen in the dropdown
        JogSign_ (1,1) double = 0         % -1 CCW, +1 CW, 0 stopped
        MovePending_ (1,1) logical = false % a MOVEDEG is believed to be running
        Busy_ (1,1) logical = false       % a transaction is in flight (one reader at a time)
        PollFailures_ (1,1) double = 0    % consecutive failed polls
        LimitRPM_ (1,1) double = 240      % speed ceiling, from the controller when it says

        PreferenceTag_ (1,:) char = ''
        FontSize_ (1,1) double = 12
        H_ (1,1) struct = struct()        % graphics handles
        Rows_ (1,1) struct = struct()     % one container handle per ROW_NAMES entry
        DefaultSections_ (1,:) string = string.empty(1,0) % what "Reset to Default" restores
        UserPrefs_ (1,1) struct = struct()% the operator's remembered configuration
        FromUI_ (1,1) logical = false     % the change came from the panel, so remember it
        Applying_ (1,1) logical = false   % suppress hardware writes from set methods

        SwapExplicit_ (1,1) logical = false % somebody chose; stop following the device

        ShowMenuH_ = []
        PortMenuH_ = []
        VerbMenuH_ = []
        SwapMenuH_ = []
        LastLogged_ (1,:) char = ''       % last message logged, so a dead link says it once
        DestroyListener_ = event.listener.empty
        SelfDeleteListener_ = event.listener.empty
    end

    properties (Constant)
        % Individually hideable parts of the panel, in layout order.
        SECTIONS = ["Link", "Detect", "Status", "Position", "Zero", ...
                    "Speed", "Jog", "Stop", "Move"]
    end

    properties (Constant, Access = private)
        PREF_GROUP = 'epsych2_gui_NanoMotor'

        % Which way the drive turns is a fact about the BENCH, not about one
        % window, so the label swap is remembered machine-wide and in
        % peripherals.NanoMotorControlGUI's group rather than this panel's
        % per-tag one -- flipping it in either place must not leave the two
        % disagreeing about the same rig. (Its PREF_GROUP is private, so the
        % name is spelled out here; the two must be changed together.)
        SWAP_PREF_GROUP = 'epsych2_peripherals_NanoMotorControlGUI'
        SWAP_PREF_NAME  = 'SwapDirectionLabels'

        % Group names accepted wherever a section name is, and what each
        % expands to. 'All' and 'None' are handled in normalizeSections_.
        ALIAS_NAMES = {'Connection', 'Readout', 'Motion'}
        ALIAS_MEMBERS = {["Link","Detect"], ["Status","Position","Zero"], ...
                         ["Speed","Jog","Stop","Move"]}

        % The panel's rows, in order, with their heights in pixels and the
        % sections that keep each one on screen. A row whose sections are
        % all hidden collapses to zero height rather than being destroyed.
        ROW_NAMES    = {'Link', 'Status', 'Position', 'Jog', 'Move'}
        ROW_HEIGHTS  = [24, 18, 30, 26, 26]
        ROW_SECTIONS = {["Link","Detect"], "Status", ["Position","Zero"], ...
                        ["Speed","Jog","Stop"], "Move"}

        COLOR_OFF    = [0.60 0.60 0.60]
        COLOR_WAIT   = [0.95 0.80 0.20]
        COLOR_ON     = [0.20 0.80 0.20]
        COLOR_MOVING = [0.20 0.40 0.90]
        COLOR_ERROR  = [0.90 0.20 0.20]

        COLOR_JOG_ON = [0.80 0.90 0.80]  % a jog button while its jog runs
        COLOR_STOP   = [0.96 0.85 0.85]

        % Beyond this many consecutive failed polls the readout gives up and
        % says so. Each failure costs a serial timeout (2 s by default), so a
        % controller that has gone away would otherwise stall the GUI once
        % per period for as long as the window is open.
        MAX_POLL_FAILURES = 3
    end


    methods (Static)
        function s = getComponentSpec()
            % s = gui.components.NanoMotor.getComponentSpec()
            % No default key chord ON PURPOSE: these controls turn a motor,
            % and a keystroke is the wrong way to start one.
            %
            % Port, SpeedRPM, MoveAmount, MoveUnits, Sections and Verbosity
            % are declared WITHOUT a default, so an option the caller does
            % not name is not passed at all and the operator's own
            % remembered configuration fills the gap.
            % See gui.ComponentSpec.
            s = gui.ComponentSpec();
            s.type        = 'NanoMotor';
            s.label       = 'Motor Control';
            s.category    = 'Add-ons';
            s.description = 'Commutator/stepper panel; connects to the controller only when asked';
            s.shape       = ["runtime","parent"];
            s.options     = [ ...
                gui.ComponentSpecOption('name','Port','inputType','text', ...
                    'description','Serial port to preselect (no connection is made)'), ...
                gui.ComponentSpecOption('name','SpeedRPM','inputType','numeric'), ...
                gui.ComponentSpecOption('name','MoveAmount','inputType','numeric'), ...
                gui.ComponentSpecOption('name','MoveUnits','inputType','choice', ...
                    'choices',{{'deg','rot'}}), ...
                gui.ComponentSpecOption('name','Verbosity','inputType','choice', ...
                    'choices',{{'SILENT','INFO','DETAILED'}}), ...
                gui.ComponentSpecOption('name','SwapDirectionLabels','inputType','logical', ...
                    'description','Exchange what the jog buttons say, for a drive that reverses'), ...
                gui.ComponentSpecOption('name','Sections','inputType','text','isList',true), ...
                gui.ComponentSpecOption('name','ButtonOnly','inputType','logical','defaultValue',false), ...
                gui.ComponentSpecOption('name','Text','inputType','text','defaultValue','Motor'), ...
                gui.ComponentSpecOption('name','UpdatePeriod','inputType','numeric','defaultValue',0.5), ...
                gui.ComponentSpecOption('name','FontSize','inputType','numeric','defaultValue',12), ...
                gui.ComponentSpecOption('name','PreferenceTag','inputType','text')];
        end
    end


    methods

        function obj = NanoMotor(source, container, options)
            % obj = gui.components.NanoMotor(source, container, ...)
            %  source    - peripherals.NanoMotorControl to drive, an
            %              epsych.Runtime (whose review state is honoured and
            %              whose notes record what the operator does here),
            %              or [] to have the panel construct a driver of its
            %              own. Nothing is connected either way.
            %  container - Figure, panel, tab, or layout hosting the panel.
            %  Port          - Serial port to preselect. Default: the
            %                  driver's, else the one last used here.
            %  SpeedRPM      - Jog/move speed in motor RPM. Default 60.
            %  MoveAmount    - Move magnitude in MoveUnits. Default 90.
            %  MoveUnits     - 'deg' (default) or 'rot'.
            %  Verbosity     - Driver print level. Default 'SILENT'.
            %  SwapDirectionLabels - Exchange what the jog buttons say.
            %                  Unstated it follows this machine's remembered
            %                  choice, else the controller's OutputDirSign.
            %  Sections      - Parts of the panel to show; see SECTIONS and
            %                  the group aliases. Default "All". This is the
            %                  DEFAULT layout: a selection the operator made
            %                  from the right-click menu in an earlier
            %                  session wins, and "Reset to Default" in that
            %                  menu comes back to this.
            %  ButtonOnly    - Build just a button that opens the panel in a
            %                  window of its own. Default false.
            %  Text          - Label on that button. Default 'Motor'.
            %  UpdatePeriod  - Position readout period, seconds. Default 0.5.
            %                  Only ever polls while the link is open.
            %  FontSize      - Base font size. Default 12.
            %  PreferenceTag - Key for the remembered configuration
            %                  (defaults to the hosting figure Tag/Name).
            arguments
                source = []
                container (1,1) = uifigure(Name = 'Motor Control')
                options.Port (1,:) char
                options.SpeedRPM (1,1) double {mustBeNonnegative, mustBeFinite}
                options.MoveAmount (1,1) double {mustBeFinite}
                options.MoveUnits (1,:) char {mustBeMember(options.MoveUnits, {'deg','rot'})}
                options.Verbosity (1,:) char {mustBeMember(options.Verbosity, ...
                    {'SILENT','INFO','DETAILED'})}
                options.SwapDirectionLabels (1,1) logical
                options.Sections (1,:) string
                options.ButtonOnly (1,1) logical = false
                options.Text (1,:) char = 'Motor'
                options.UpdatePeriod (1,1) double {mustBePositive} = 0.5
                options.FontSize (1,1) double {mustBePositive} = 12
                options.PreferenceTag (1,:) char = ''
            end

            obj.Parent         = container;
            obj.ButtonOnly_    = options.ButtonOnly;
            obj.UpdatePeriod   = options.UpdatePeriod;
            obj.FontSize_      = options.FontSize;
            obj.PreferenceTag_ = options.PreferenceTag;

            % Five short rows; the mixin's 780x560 default is a window sized
            % for a plot and this one would be mostly empty space.
            obj.PopOutSize  = [320 230];
            obj.PopOutLabel = 'Motor Control';

            saved = obj.loadPreferences_();
            obj.UserPrefs_ = saved;

            % Settings: what the caller asked for, else what the operator
            % left behind, else the built-in default. Seeded behind
            % Applying_ so nothing is written to a controller that is not
            % even connected yet.
            obj.Applying_ = true;
            obj.seedSetting_('Verbosity', ...
                char(gui.components.NanoMotor.pick_(options, saved, 'Verbosity', 'SILENT')), 'SILENT');
            obj.seedSetting_('SpeedRPM', ...
                gui.components.NanoMotor.pick_(options, saved, 'SpeedRPM', 60), 60);
            obj.seedSetting_('MoveUnits', ...
                char(gui.components.NanoMotor.pick_(options, saved, 'MoveUnits', 'deg')), 'deg');
            obj.seedSetting_('MoveAmount', ...
                gui.components.NanoMotor.pick_(options, saved, 'MoveAmount', 90), 90);
            obj.Applying_ = false;

            obj.resolveSwapDirectionLabels_(options);

            obj.DefaultSections_ = obj.normalizeSections_( ...
                gui.components.NanoMotor.pick_(options, [], 'Sections', "All"));
            obj.Sections = gui.components.NanoMotor.pick_(options, saved, 'Sections', ...
                obj.DefaultSections_);

            obj.resolveMotor_(source);
            obj.StagedPort_ = obj.initialPort_(options, saved);

            if obj.ButtonOnly_
                % No panel of its own: the window the button opens is the
                % display, and it drives the same controller.
                obj.buildButton_(container, options.Text);
                return
            end

            obj.buildUI_(container);
            obj.createTimer_();
            obj.updateLinkUI_();
            obj.renderPosition_();

            if obj.ReviewMode_
                obj.setStatus_('Review (hardware offline)', obj.COLOR_OFF);
            elseif obj.IsConnected
                % A controller handed in already open: show it, and start
                % reading. Connecting one is still the operator's business.
                obj.startPolling();
            end
        end

        function delete(obj)
            % Stop the readout, drop the menu, and release the controller --
            % but only when this panel created it; one borrowed from a
            % session (or from the panel a pop-out came from) outlives the
            % window.
            try
                if ~isempty(obj.Timer) && isvalid(obj.Timer)
                    stop(obj.Timer);
                    delete(obj.Timer);
                end
            catch
            end
            try
                delete(obj.DestroyListener_);
                delete(obj.SelfDeleteListener_);
            catch
            end
            try
                if ~isempty(obj.ContextMenu) && isvalid(obj.ContextMenu)
                    delete(obj.ContextMenu);
                end
            catch
            end

            if ~obj.OwnsMotor_, return; end
            try
                if ~isempty(obj.Motor) && isvalid(obj.Motor)
                    if obj.Motor.IsConnected
                        obj.Motor.stop();
                    end
                    delete(obj.Motor);   % its destructor closes the port
                end
            catch ME
                vprintf(2, 'gui.components.NanoMotor: releasing the controller failed: %s', ME.message)
            end
        end

        % --- Dependent properties -------------------------------------------

        function tf = get.IsConnected(obj)
            tf = ~isempty(obj.Motor) && isvalid(obj.Motor) && obj.Motor.IsConnected;
        end

        function tf = get.IsJogging(obj)
            tf = obj.JogSign_ ~= 0;
        end

        function tf = get.IsButtonOnly(obj)
            tf = obj.ButtonOnly_;
        end

        function p = get.Port(obj)
            p = obj.StagedPort_;
        end

        function set.Port(obj, value)
            obj.selectPort_(value);
        end

        % --- Settings -------------------------------------------------------

        function set.SpeedRPM(obj, value)
            obj.SpeedRPM = value;
            obj.onSettingChanged_('SpeedRPM');
        end

        function set.MoveAmount(obj, value)
            obj.MoveAmount = value;
            obj.onSettingChanged_('MoveAmount');
        end

        function set.MoveUnits(obj, value)
            was = obj.MoveUnits;
            obj.MoveUnits = value;
            obj.onMoveUnitsChanged_(was);
        end

        function set.Verbosity(obj, value)
            obj.Verbosity = upper(value);
            obj.onSettingChanged_('Verbosity');
        end

        function set.SwapDirectionLabels(obj, value)
            obj.SwapDirectionLabels = logical(value);

            % A set method may not touch another property, so what counts as
            % a deliberate choice is recorded where the choice is made
            % (resolveSwapDirectionLabels_, toggleSwapLabels_), not here.
            obj.applyDirectionLabels_();
        end

        function set.Sections(obj, value)
            obj.Sections = obj.normalizeSections_(value);
            obj.onSectionsChanged_();
        end

        % --- Visibility ------------------------------------------------------

        function show(obj, names)
            % show(obj, names)
            % Show one or more parts of the panel, leaving the rest as they
            % are. Accepts section names and the group aliases.
            arguments
                obj
                names (1,:) string
            end
            obj.Sections = union(obj.Sections, obj.normalizeSections_(names), 'stable');
        end

        function hide(obj, names)
            % hide(obj, names)
            % Hide one or more parts of the panel. A hidden control keeps
            % its value and its bindings: hiding the speed field does not
            % stop a jog being sent at obj.SpeedRPM.
            arguments
                obj
                names (1,:) string
            end
            obj.Sections = setdiff(obj.Sections, obj.normalizeSections_(names), 'stable');
        end

        function tf = isSectionVisible(obj, name)
            % tf = isSectionVisible(obj, name)
            % True when the named part of the panel is currently shown. A
            % group alias is true only when every member of it is.
            arguments
                obj
                name (1,1) string
            end
            wanted = obj.normalizeSections_(name);
            tf = ~isempty(wanted) && all(ismember(wanted, obj.Sections));
        end

        % --- Connection -----------------------------------------------------

        function connect(obj)
            % connect(obj)
            % Open the link on the selected port. This is the ONLY thing in
            % the class that touches the serial port unbidden -- everything
            % else needs the link to be up already -- and it is reached from
            % the Connect button, the right-click menu, or a paradigm that
            % decides its rig should come up connected.
            if ~obj.permitDrive_('connect to the controller'), return; end

            if obj.IsConnected
                if strcmpi(char(obj.Motor.Port), obj.StagedPort_)
                    return
                end
                obj.disconnect();
            end

            m = obj.ensureMotor_();
            m.Verbosity = string(obj.Verbosity);

            if isempty(obj.StagedPort_)
                % No port named: probing is the only thing left to try, and
                % it is slow enough that the operator is told it is running
                % rather than left watching a frozen button.
                obj.detectPort();
                return
            end

            obj.setStatus_(sprintf('Connecting to %s...', obj.StagedPort_), obj.COLOR_WAIT);
            drawnow limitrate

            try
                m.connect(Port = string(obj.StagedPort_), AutoDetect = false);
                m.mode("USB");
                m.enable(true);
            catch ME
                % A controller that is off, unplugged, or held by another
                % MATLAB is an ordinary operator situation, so it reports in
                % the panel rather than throwing out of a button callback.
                vprintf(0, 1, ME)
                % The buttons are put back FIRST: updateLinkUI_ ends by
                % stating the link's state, which would otherwise overwrite
                % the one thing the operator needs to read here.
                obj.updateLinkUI_();
                obj.setStatus_(['Connect failed: ' obj.shortMsg_(ME.message)], obj.COLOR_ERROR);
                return
            end

            obj.readLimits_();
            obj.adoptSwapFromDevice_();   % connect() has just read GEAR
            obj.savePreferences_();
            obj.PollFailures_ = 0;
            obj.LastLogged_ = '';
            obj.note_('Motor: connected on %s', obj.StagedPort_);
            obj.updateLinkUI_();
            obj.startPolling();
            obj.poll_();
        end

        function disconnect(obj)
            % disconnect(obj)
            % Stop the motor and close the link. Every setting stays in the
            % panel and is used again on the next connect.
            obj.stopPolling();
            if isempty(obj.Motor) || ~isvalid(obj.Motor), return; end

            wasConnected = obj.IsConnected;
            obj.clearJogVisual_();
            obj.JogSign_ = 0;
            obj.MovePending_ = false;

            try
                if wasConnected
                    obj.Motor.stop();
                end
                obj.Motor.disconnect();
            catch ME
                vprintf(1, 1, ME)
            end

            if wasConnected
                obj.note_('Motor: disconnected');
            end
            obj.PositionDeg = NaN;
            obj.renderPosition_();
            obj.updateLinkUI_();
        end

        function port = detectPort(obj)
            % port = detectPort(obj)
            % Probe the available serial ports for a controller that greets
            % as one, select it, and connect. Returns '' when none answered.
            %
            % Slow by construction: every candidate port is opened and left
            % to boot (BootDelay, 2 s by default) before it is read, because
            % opening the port resets the Nano. The panel says what it is
            % doing for that reason.
            port = '';
            if ~obj.permitDrive_('probe the serial ports'), return; end

            m = obj.ensureMotor_();
            if obj.IsConnected
                obj.disconnect();
            end

            obj.setStatus_('Probing serial ports...', obj.COLOR_WAIT);
            obj.setEnabled_(false);
            drawnow limitrate

            try
                port = char(m.findControllerPort());
            catch ME
                vprintf(0, 1, ME)
                port = '';
            end
            obj.setEnabled_(true);

            if isempty(port)
                vprintf(0, 1, ['gui.components.NanoMotor: no DM320T controller answered on any ' ...
                    'available serial port'])
                obj.updateLinkUI_();   % before the message, which it would overwrite
                obj.setStatus_('No controller found', obj.COLOR_ERROR);
                return
            end

            vprintf(1, 'gui.components.NanoMotor: found a controller on %s', port)
            obj.selectPort_(port);
            obj.connect();
        end

        function refreshPorts(obj)
            % refreshPorts(obj)
            % Re-read the serial port list into the dropdown, keeping the
            % current selection when it is still there. A port opened by
            % this panel drops out of the "available" list, which is why the
            % staged one is added back rather than read off it.
            if ~obj.hasControl_('port'), return; end
            [items, value] = obj.portItems_();
            obj.H_.port.Items = items;
            obj.H_.port.Value = value;
        end

        % --- Motion ------------------------------------------------------------

        function jog(obj, direction)
            % jog(obj, direction)
            % Start continuous rotation: -1 or 'ccw', +1 or 'cw'. Calling it
            % for the direction already running stops the jog, which is what
            % clicking the lit button does.
            %
            % The direction is the MOTOR's, as the firmware's DIR is, so
            % SwapDirectionLabels does not change what this sends -- only
            % what the button that calls it is labelled.
            arguments
                obj
                direction
            end
            sgn = gui.components.NanoMotor.directionSign_(direction);
            if ~obj.requireLink_(), return; end

            if obj.JogSign_ == sgn
                obj.stopJog();
                return
            end

            obj.clearJogVisual_();
            obj.JogSign_ = sgn;

            % Zero would not turn the motor at all, and a button that does
            % nothing reads as a broken link rather than as a speed of zero.
            rpm = sgn * max(abs(obj.SpeedRPM), 1);

            obj.setJogVisual_(sgn, true);
            obj.setStatus_(sprintf('Jogging %s at %.4g RPM', ...
                obj.directionName_(sgn), abs(rpm)), obj.COLOR_MOVING);

            if ~obj.safeSend_(@() obj.Motor.setRPM(rpm))
                obj.JogSign_ = 0;
                obj.setJogVisual_(sgn, false);
                return
            end
            obj.note_('Motor: jog %s at %.4g RPM', ...
                obj.directionName_(sgn), abs(rpm));
        end

        function stopJog(obj)
            % stopJog(obj)
            % End a running jog by commanding zero speed. Does nothing when
            % no jog is running, so it is safe to call before anything else.
            if obj.JogSign_ == 0, return; end
            sgn = obj.JogSign_;
            obj.JogSign_ = 0;
            obj.setJogVisual_(sgn, false);

            if ~obj.IsConnected
                obj.updateLinkUI_();
                return
            end
            obj.safeSend_(@() obj.Motor.setRPM(0));
            obj.note_('Motor: jog stopped');
            obj.setStatus_(obj.connectedText_(), obj.COLOR_ON);
        end

        function stopMotion(obj)
            % stopMotion(obj)
            % STOP: end a jog and cancel any move in progress. This is the
            % button an operator reaches for, so it sends the stop even when
            % the panel believes nothing is running.
            if ~obj.requireLink_(), return; end
            obj.clearJogVisual_();
            obj.JogSign_ = 0;
            obj.MovePending_ = false;
            obj.safeSend_(@() obj.Motor.stop());
            obj.note_('Motor: STOP');
            obj.setStatus_(obj.connectedText_(), obj.COLOR_ON);
            obj.poll_();
        end

        function move(obj)
            % move(obj)
            % Send MOVEDEG for MoveAmount in MoveUnits, at SpeedRPM. A jog is
            % stopped first: the firmware's continuous speed and its relative
            % move are two different things to be doing at once.
            if ~obj.requireLink_(), return; end

            deg = obj.MoveAmount;
            if strcmp(obj.MoveUnits, 'rot')
                deg = deg * 360;
            end
            rpm = abs(obj.SpeedRPM);

            obj.stopJog();
            obj.safeSend_(@() obj.Motor.stop());

            obj.setStatus_(sprintf('Moving %.6g deg', deg), obj.COLOR_MOVING);
            if rpm > 0
                ok = obj.safeSend_(@() obj.Motor.moveDeg(deg, rpm));
            else
                % Zero means "the controller's own speed", which is a real
                % answer for a move even though it is not one for a jog.
                ok = obj.safeSend_(@() obj.Motor.moveDeg(deg));
            end

            obj.MovePending_ = ok;
            if ok
                obj.note_('Motor: move %.6g %s at %.4g RPM', obj.MoveAmount, obj.MoveUnits, rpm);
            end
            obj.poll_();
        end

        function zeroPosition(obj)
            % zeroPosition(obj)
            % Set the controller's open-loop position counter to zero, which
            % is how the commutator's current place becomes its reference.
            % The motor is stopped first: zeroing under a running jog would
            % leave the counter meaning nothing in particular.
            if ~obj.requireLink_(), return; end
            obj.stopJog();
            obj.safeSend_(@() obj.Motor.stop());
            if obj.safeSend_(@() obj.Motor.zero())
                obj.note_('Motor: position zeroed');
            end
            obj.poll_();
        end

        % --- Readout ------------------------------------------------------------

        function refresh(obj)
            % refresh(obj)
            % Read the position and motion state now, outside the timer.
            obj.poll_();
        end

        function startPolling(obj)
            % startPolling(obj)
            % Resume the position readout. It only ever runs while the link
            % is open and something is on screen to show, so a disconnected
            % panel costs the controller no serial traffic at all.
            if isempty(obj.Timer) || ~isvalid(obj.Timer), return; end
            if ~obj.IsConnected || obj.ReviewMode_, return; end
            if ~any(ismember(["Status","Position"], obj.Sections)), return; end
            if strcmp(obj.Timer.Running, 'off')
                start(obj.Timer);
            end
        end

        function stopPolling(obj)
            % stopPolling(obj) - Pause the position readout.
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer);
            end
        end
    end


    methods (Access = protected)

        function c = popOutHostContainer_(obj)
            % Container this component was built into (gui.PopOut).
            c = obj.Parent;
        end

        function h = createPopOut_(obj, container)
            % A second panel over the SAME controller, in its own window. It
            % never owns the link, so closing it leaves the port open; the
            % ButtonOnly form's pop-out is the panel that form does not have.
            h = gui.components.NanoMotor(obj.popOutSource_(), container, ...
                Port          = obj.StagedPort_, ...
                SpeedRPM      = obj.SpeedRPM, ...
                MoveAmount    = obj.MoveAmount, ...
                MoveUnits     = obj.MoveUnits, ...
                Verbosity     = obj.Verbosity, ...
                SwapDirectionLabels = obj.SwapDirectionLabels, ...
                Sections      = obj.Sections, ...
                UpdatePeriod  = obj.UpdatePeriod, ...
                FontSize      = obj.FontSize_, ...
                PreferenceTag = obj.popOutPreferenceTag_());

            % The window is built over the CONTROLLER, so the session it
            % belongs to is handed across separately -- without it a
            % pop-out's moves would go unrecorded, and a review would leave
            % its buttons live.
            if ~isempty(h) && isvalid(h)
                h.adoptSession_(obj.Runtime_, obj.ReviewMode_);
            end
        end
    end


    methods (Access = private)

        % --- Controller resolution ---------------------------------------------

        function resolveMotor_(obj, source)
            % Adopt the controller this panel drives: one handed in, else one
            % of our own. Nothing is connected here -- a driver object costs
            % no serial port until connect() is called on it, which is what
            % lets this component be built against a rig that is switched off.
            if isa(source, 'peripherals.NanoMotorControl') && isvalid(source)
                obj.Motor = source;
                obj.OwnsMotor_ = false;
                return
            end

            % A session: remembered so what the operator does here reaches
            % the data file, and so a review stands the panel down. Read by
            % property rather than by class, so a pop-out can be handed the
            % same source without the runtime having to exist.
            if ~isempty(source) && isobject(source) && isvalid(source)
                obj.Runtime_ = source;
                try
                    if isprop(source, 'ReviewMode')
                        obj.ReviewMode_ = logical(source.ReviewMode);
                    end
                catch ME
                    vprintf(3, 'gui.components.NanoMotor: could not read the review state (%s)', ME.message)
                end
            end

            obj.ensureMotor_();
        end

        function resolveSwapDirectionLabels_(obj, options)
            % Three sources, most specific first: what the caller stated,
            % what this machine last chose, and -- left to
            % adoptSwapFromDevice_ -- the controller's own OutputDirSign.
            obj.SwapExplicit_ = true;

            if isfield(options, 'SwapDirectionLabels')
                obj.SwapDirectionLabels = options.SwapDirectionLabels;
                return
            end

            if ispref(obj.SWAP_PREF_GROUP, obj.SWAP_PREF_NAME)
                obj.SwapDirectionLabels = ...
                    logical(getpref(obj.SWAP_PREF_GROUP, obj.SWAP_PREF_NAME));
            else
                % Nothing stated and nothing remembered: ask the controller.
                obj.SwapExplicit_ = false;
            end
        end

        function adoptSwapFromDevice_(obj)
            % connect() has just read the firmware's gear configuration, and
            % a reversing drive is the case the swap exists for. A starting
            % point rather than a choice, so it never raises SwapExplicit_
            % and an operator's toggle still outranks it.
            if obj.SwapExplicit_ || ~obj.IsConnected, return; end
            obj.SwapDirectionLabels = obj.Motor.OutputDirSign < 0;
        end

        function applyDirectionLabels_(obj)
            % The buttons are named for the MOTOR direction each commands;
            % only what they say moves.
            for sgn = [-1 1]
                if sgn < 0
                    name = 'ccw';
                else
                    name = 'cw';
                end
                if ~obj.hasControl_(name), continue; end
                label = obj.directionName_(sgn);
                obj.H_.(name).Text = label;
                obj.H_.(name).Tooltip = sprintf( ...
                    'Jog %s at the speed on the left; press again to stop', label);
            end

            % The status line names the direction too, so a swap during a jog
            % reaches it without waiting for the next poll.
            if obj.JogSign_ ~= 0
                obj.setStatus_(sprintf('Jogging %s at %.4g RPM', ...
                    obj.directionName_(obj.JogSign_), abs(obj.SpeedRPM)), obj.COLOR_MOVING);
            end
        end

        function name = directionName_(obj, sgn)
            % A negative motor sign reads CCW unless the labels are swapped
            % for a drive that reverses the output shaft.
            if xor(sgn < 0, obj.SwapDirectionLabels)
                name = 'CCW';
            else
                name = 'CW';
            end
        end

        function toggleSwapLabels_(obj)
            obj.SwapDirectionLabels = ~obj.SwapDirectionLabels;
            obj.SwapExplicit_ = true;
            try
                setpref(obj.SWAP_PREF_GROUP, obj.SWAP_PREF_NAME, obj.SwapDirectionLabels);
            catch ME
                vprintf(2, 'gui.components.NanoMotor: could not remember the label swap: %s', ME.message)
            end
        end

        function adoptSession_(obj, runtime, reviewMode)
            % Take on the session another instance of this class belongs to.
            % Reached only from createPopOut_, and private -- one panel
            % handing a session to another is the whole use for it.
            obj.Runtime_ = runtime;
            obj.ReviewMode_ = logical(reviewMode);
            if obj.ReviewMode_
                obj.stopPolling();
            end
            obj.updateLinkUI_();
        end

        function m = ensureMotor_(obj)
            % The driver, constructing a disconnected one on first need.
            if ~isempty(obj.Motor) && isvalid(obj.Motor)
                m = obj.Motor;
                return
            end
            m = peripherals.NanoMotorControl(Verbosity = string(obj.Verbosity));
            obj.Motor = m;
            obj.OwnsMotor_ = true;
            vprintf(2, 'gui.components.NanoMotor: no controller supplied; created a disconnected one')
        end

        function s = popOutSource_(obj)
            % What the pop-out is built over: the controller, so both
            % windows drive one link. The runtime goes with it only when
            % there is no controller yet -- a source can be one or the other.
            s = obj.Motor;
            if isempty(s) || ~isvalid(s)
                s = obj.Runtime_;
            end
        end

        function seedSetting_(obj, name, value, default)
            % Assign one setting at construction, falling back to the
            % built-in default when a remembered value no longer validates
            % (a hand-edited preference, a range that has since changed).
            try
                obj.(name) = value;
            catch ME
                vprintf(1, ['gui.components.NanoMotor: remembered %s is not usable (%s); ' ...
                    'falling back to the default'], name, ME.message)
                obj.(name) = default;
            end
        end

        function tf = permitDrive_(obj, what)
            % Guard for everything that would touch the hardware. A reviewed
            % session has no rig behind it, and its panel is a record.
            tf = ~obj.ReviewMode_;
            if ~tf
                vprintf(1, 'gui.components.NanoMotor: a reviewed session cannot %s', what)
            end
        end

        function tf = requireLink_(obj)
            % Guard for the actions that need an open link.
            tf = false;
            if ~obj.permitDrive_('drive the motor'), return; end
            tf = obj.IsConnected;
            if ~tf
                obj.setStatus_('Not connected', obj.COLOR_ERROR);
                vprintf(1, 'gui.components.NanoMotor: no controller connected')
            end
        end

        function ok = safeSend_(obj, fcn)
            % One transaction. The controller answers one reader at a time,
            % so a command is refused outright while another is in flight
            % rather than being sent into a reply somebody else is waiting
            % for -- which surfaces as NanoMotorControl:Timeout on BOTH.
            ok = false;
            if obj.Busy_
                vprintf(2, 'gui.components.NanoMotor: a command is already in flight; skipped')
                return
            end
            obj.Busy_ = true;
            c = onCleanup(@() obj.clearBusy_());  % released on return
            try
                fcn();
                ok = true;
            catch ME
                vprintf(0, 1, ME)
                obj.setStatus_(obj.shortMsg_(ME.message), obj.COLOR_ERROR);
            end
        end

        function clearBusy_(obj)
            if isvalid(obj)
                obj.Busy_ = false;
            end
        end

        function readLimits_(obj)
            % The speed ceiling the firmware enforces, so the field cannot
            % ask for a speed the controller will refuse. Absent (older
            % firmware, an unparseable reply) the built-in ceiling stands.
            try
                lim = double(obj.Motor.limitRPMQuery());
                if isfinite(lim) && lim > 0
                    obj.LimitRPM_ = lim;
                end
            catch ME
                vprintf(2, 'gui.components.NanoMotor: no RPM limit from the controller (%s)', ME.message)
            end

            if obj.SpeedRPM > obj.LimitRPM_
                obj.SpeedRPM = obj.LimitRPM_;
            end
            if obj.hasControl_('speed')
                obj.H_.speed.Limits = [0 obj.LimitRPM_];
            end
        end

        function note_(obj, fmt, varargin)
            % Record an operator action in the session notes, so a
            % commutator turned mid-session is in the data file rather than
            % only in somebody's memory. Never throws and does nothing
            % without a session (epsych.SessionNotes.log).
            if isempty(obj.Runtime_), return; end
            epsych.SessionNotes.log(obj.Runtime_, fmt, varargin{:});
        end

        % --- Polling ------------------------------------------------------------

        function createTimer_(obj)
            % fixedSpacing, not fixedRate: each tick is a serial round trip
            % of its own, and the period is the gap we want between them.
            tname = sprintf('NanoMotor_Timer_%d', gui.components.NanoMotor.nextInstanceId_());
            delete(timerfindall('Name', tname));
            obj.Timer = timer(Name = tname, ExecutionMode = 'fixedSpacing', ...
                Period = obj.UpdatePeriod, BusyMode = 'drop', ...
                TimerFcn = @(~,~) obj.timerTick_());
        end

        function timerTick_(obj)
            % An uncaught error in a TimerFcn stops the timer for good.
            if ~isvalid(obj), return; end
            try
                obj.poll_();
            catch ME
                vprintf(2, 'gui.components.NanoMotor: poll failed: %s', ME.message)
            end
        end

        function poll_(obj)
            % One readout pass: the position, plus the move state when a
            % move is believed to be running. MOVE? is not asked for
            % otherwise -- it would double the traffic on a link the panel
            % shares with whatever else drives the commutator.
            if ~isvalid(obj) || obj.ButtonOnly_, return; end

            if ~obj.IsConnected
                obj.PositionDeg = NaN;
                obj.renderPosition_();
                return
            end
            if obj.Busy_, return; end

            obj.Busy_ = true;
            c = onCleanup(@() obj.clearBusy_());  % released on return

            try
                obj.PositionDeg = obj.Motor.positionDeg();
                obj.renderPosition_();
                obj.reportMotion_();
                obj.PollFailures_ = 0;
            catch ME
                obj.onPollError_(ME);
            end
        end

        function reportMotion_(obj)
            % What to say under the position. A jog is what the panel itself
            % started, so it is known without asking; a move is the
            % controller's business until it reports itself finished.
            if obj.JogSign_ ~= 0
                obj.setStatus_(sprintf('Jogging %s at %.4g RPM', ...
                    obj.directionName_(obj.JogSign_), ...
                    abs(obj.SpeedRPM)), obj.COLOR_MOVING);
                return
            end

            if ~obj.MovePending_
                obj.setStatus_(obj.connectedText_(), obj.COLOR_ON);
                return
            end

            try
                M = obj.Motor.moveQuery();
            catch ME
                vprintf(3, 'gui.components.NanoMotor: MOVE? failed (%s)', ME.message)
                return
            end

            active = isfield(M, 'Active') && islogical(M.Active) && M.Active;
            if ~active
                obj.MovePending_ = false;
                obj.setStatus_(obj.connectedText_(), obj.COLOR_ON);
                return
            end

            txt = 'Moving';
            if isfield(M, 'REMDEG')
                txt = sprintf('Moving, %.3g deg to go', double(M.REMDEG));
            end
            obj.setStatus_(txt, obj.COLOR_MOVING);
        end

        function onPollError_(obj, ME)
            % A busy controller (SERQUIET on, motion in progress) is not a
            % failure: it is the firmware protecting its step timing, and it
            % answers again once the move ends. Anything else counts, and a
            % link that keeps failing is dropped rather than left costing a
            % serial timeout per period for as long as the window is open.
            if strcmp(ME.identifier, 'NanoMotorControl:DeviceBusy')
                obj.setStatus_('Moving (controller busy)', obj.COLOR_MOVING);
                return
            end

            obj.PollFailures_ = obj.PollFailures_ + 1;
            obj.logOnce_(ME.message);
            obj.setStatus_(obj.shortMsg_(ME.message), obj.COLOR_ERROR);

            if obj.PollFailures_ < obj.MAX_POLL_FAILURES, return; end
            obj.stopPolling();
            obj.setStatus_('Readout stopped (no reply)', obj.COLOR_ERROR);
            vprintf(0, 1, ['gui.components.NanoMotor: the controller stopped answering; the ' ...
                'position readout is paused. Reconnect to resume it.'])
        end

        function logOnce_(obj, msg)
            % The same failure every period is one event, not twenty.
            if strcmp(msg, obj.LastLogged_), return; end
            obj.LastLogged_ = msg;
            vprintf(1, 'gui.components.NanoMotor: %s', msg)
        end

        % --- UI ------------------------------------------------------------------

        function buildButton_(obj, parent, text)
            % The button form: one button, and the panel lives in the window
            % it opens. popOut is the ordinary gui.PopOut path, so the window
            % remembers where it was, can be pinned on top, raises rather
            % than duplicating, and closes with the GUI that owns the button.
            obj.H_.open = uibutton(parent, ...
                'Text',            text, ...
                'Icon',            gui.toolbarIcon("nanomotor"), ...
                'Tooltip',         'Commutator motor control (opens in its own window)', ...
                'FontSize',        obj.FontSize_, ...
                'ButtonPushedFcn', @(~,~) obj.popOut());

            obj.SelfDeleteListener_ = listener(obj.H_.open, 'ObjectBeingDestroyed', ...
                @(~,~) delete(obj));
        end

        function buildUI_(obj, container)
            % Five rows, no label column: the units live inside the fields
            % and the buttons say what they do, which is what makes the
            % panel fit where the old window did not. Every row is built
            % whatever Sections says and applySectionVisibility_ collapses
            % the ones that are off, so toggling a section costs no teardown.
            fs = obj.FontSize_;

            g = uigridlayout(container, [numel(obj.ROW_NAMES) 1]);
            g.RowHeight   = num2cell(obj.ROW_HEIGHTS);
            g.ColumnWidth = {'1x'};
            g.RowSpacing  = 4;
            g.Padding     = [6 6 6 6];
            g.Scrollable  = 'on';
            obj.H_.root = g;

            % --- Link: port, probe, connect --------------------------------
            lg = uigridlayout(g, [1 3]);
            lg.ColumnWidth   = {'1x', 56, 76};
            lg.RowHeight     = {'1x'};
            lg.ColumnSpacing = 4;
            lg.Padding       = [0 0 0 0];
            obj.Rows_.Link = lg;

            [items, value] = obj.portItems_();
            obj.H_.port = uidropdown(lg, Items = items, Value = value, FontSize = fs - 1, ...
                Tooltip = 'Serial port the controller is on (right-click to re-read the list)', ...
                ValueChangedFcn = @(src,~) obj.selectPort_(src.Value));
            obj.H_.detect = uibutton(lg, Text = 'Detect', FontSize = fs - 2, ...
                Tooltip = 'Probe every serial port for a controller (a few seconds per port)', ...
                ButtonPushedFcn = @(~,~) obj.detectPort());
            obj.H_.connect = uibutton(lg, Text = 'Connect', FontSize = fs - 1, ...
                Tooltip = 'Open the serial link; nothing is connected until this is pressed', ...
                ButtonPushedFcn = @(~,~) obj.onConnectPressed_());

            % --- Status: lamp and one line ---------------------------------
            sg = uigridlayout(g, [1 2]);
            sg.ColumnWidth   = {14, '1x'};
            sg.RowHeight     = {'1x'};
            sg.ColumnSpacing = 5;
            sg.Padding       = [0 0 0 0];
            obj.Rows_.Status = sg;
            obj.H_.lamp = uilamp(sg, Color = obj.COLOR_OFF, ...
                Tooltip = ['Grey disconnected, yellow connecting, green connected, ' ...
                           'blue moving, red error']);
            obj.H_.status = uilabel(sg, Text = '', FontSize = fs - 2, ...
                FontColor = [0.35 0.35 0.35]);

            % --- Position: the number, and its zero ------------------------
            pg = uigridlayout(g, [1 3]);
            pg.ColumnWidth   = {30, '1x', 46};
            pg.RowHeight     = {'1x'};
            pg.ColumnSpacing = 4;
            pg.Padding       = [0 0 0 0];
            obj.Rows_.Position = pg;
            obj.H_.posLabel = uilabel(pg, Text = 'Pos', FontSize = fs - 2, ...
                FontColor = [0.35 0.35 0.35]);
            obj.H_.position = uilabel(pg, Text = '--', FontSize = round(fs * 1.5), ...
                FontWeight = 'bold', HorizontalAlignment = 'right', ...
                Tooltip = 'Commanded output-shaft position (POSD?), in degrees');
            obj.H_.zero = uibutton(pg, Text = 'Zero', FontSize = fs - 2, ...
                Tooltip = 'Make this position the zero reference', ...
                ButtonPushedFcn = @(~,~) obj.zeroPosition());

            % --- Jog: speed, both directions, stop -------------------------
            jg = uigridlayout(g, [1 4]);
            jg.ColumnWidth   = {70, '1x', '1x', 54};
            jg.RowHeight     = {'1x'};
            jg.ColumnSpacing = 4;
            jg.Padding       = [0 0 0 0];
            obj.Rows_.Jog = jg;
            % Seeded through the field's own limits rather than assigned
            % straight: a remembered speed from a rig whose controller
            % reported a higher ceiling is a routine value, and uieditfield
            % refuses one outright -- which would abort the whole build and
            % take every row after it (see gui.components.Parameter_Control).
            obj.H_.speed = uieditfield(jg, 'numeric', ...
                Value = min(max(obj.SpeedRPM, 0), obj.LimitRPM_), ...
                Limits = [0 obj.LimitRPM_], LowerLimitInclusive = 'on', ...
                ValueDisplayFormat = '%.4g RPM', FontSize = fs - 1, ...
                Tooltip = 'Jog speed, and the speed a move is sent at (motor RPM)', ...
                ValueChangedFcn = @(src,~) obj.onEditChanged_('SpeedRPM', src.Value));
            % Tagged -- and named -- for the MOTOR direction each commands,
            % never for what it says: applyDirectionLabels_ writes the text
            % and a swap moves only that.
            obj.H_.ccw = uibutton(jg, Text = 'CCW', FontSize = fs, FontWeight = 'bold', ...
                Tag = 'NanoMotorJogNeg', ButtonPushedFcn = @(~,~) obj.jog(-1));
            obj.H_.cw = uibutton(jg, Text = 'CW', FontSize = fs, FontWeight = 'bold', ...
                Tag = 'NanoMotorJogPos', ButtonPushedFcn = @(~,~) obj.jog(+1));
            obj.H_.stop = uibutton(jg, Text = 'STOP', FontSize = fs - 1, FontWeight = 'bold', ...
                BackgroundColor = obj.COLOR_STOP, ...
                Tooltip = 'Stop the jog and cancel any move in progress', ...
                ButtonPushedFcn = @(~,~) obj.stopMotion());

            % --- Move: amount, units, go -----------------------------------
            mg = uigridlayout(g, [1 3]);
            mg.ColumnWidth   = {'1x', 54, 50};
            mg.RowHeight     = {'1x'};
            mg.ColumnSpacing = 4;
            mg.Padding       = [0 0 0 0];
            obj.Rows_.Move = mg;
            mlim = obj.moveLimits_();
            obj.H_.move = uieditfield(mg, 'numeric', ...
                Value = min(max(obj.MoveAmount, mlim(1)), mlim(2)), ...
                Limits = mlim, ValueDisplayFormat = '%.6g', FontSize = fs - 1, ...
                Tooltip = 'Move magnitude in the units beside it; negative goes the other way', ...
                ValueChangedFcn = @(src,~) obj.onEditChanged_('MoveAmount', src.Value));
            obj.H_.units = uidropdown(mg, Items = {'deg','rot'}, Value = obj.MoveUnits, ...
                FontSize = fs - 2, ...
                Tooltip = 'Output-shaft degrees, or whole revolutions (1 rot = 360 deg)', ...
                ValueChangedFcn = @(src,~) obj.onEditChanged_('MoveUnits', src.Value));
            obj.H_.go = uibutton(mg, Text = 'Move', FontSize = fs - 1, ...
                Tooltip = 'Send the move (MOVEDEG) at the speed on the left', ...
                ButtonPushedFcn = @(~,~) obj.move());

            obj.applyDirectionLabels_();
            obj.createContextMenu_();
            obj.applySectionVisibility_();

            obj.DestroyListener_ = listener(g, 'ObjectBeingDestroyed', @(~,~) delete(obj));
        end

        function lim = moveLimits_(obj)
            % A hundred turns either way, expressed in the current units.
            if strcmp(obj.MoveUnits, 'rot')
                lim = [-100 100];
            else
                lim = [-36000 36000];
            end
        end

        % --- Section visibility ---------------------------------------------------

        function names = normalizeSections_(obj, value)
            % Expand aliases, drop duplicates, and keep the canonical layout
            % order so Sections always reads back the way it is compared. An
            % unrecognized name is reported and skipped rather than thrown: a
            % typo in a build method must not stop the GUI from opening.
            value = reshape(string(value), 1, []);
            names = string.empty(1, 0);

            for v = value
                if strcmpi(v, "All")
                    names = [names, obj.SECTIONS];
                    continue
                end
                if strcmpi(v, "None")
                    continue
                end

                k = find(strcmpi(obj.ALIAS_NAMES, v), 1);
                if ~isempty(k)
                    names = [names, obj.ALIAS_MEMBERS{k}];
                    continue
                end

                k = find(strcmpi(obj.SECTIONS, v), 1);
                if isempty(k)
                    vprintf(1, ['gui.components.NanoMotor: "%s" is not a section of this panel; ' ...
                        'valid names are %s (or All/None)'], v, ...
                        strjoin([obj.SECTIONS, string(obj.ALIAS_NAMES)], ', '))
                    continue
                end
                names(end+1) = obj.SECTIONS(k);
            end

            names = obj.SECTIONS(ismember(obj.SECTIONS, names));
        end

        function onSectionsChanged_(obj)
            % Tail of the Sections setter: reflow, and remember the layout
            % when the operator was the one who changed it.
            obj.applySectionVisibility_();
            if obj.FromUI_
                obj.rememberSetting_('Sections', obj.Sections);
            end
        end

        function applySectionVisibility_(obj)
            % Collapse each row whose sections are all hidden, and blank the
            % individual controls inside the rows that hold several.
            if ~obj.hasControl_('root'), return; end

            heights = obj.ROW_HEIGHTS;
            for i = 1:numel(obj.ROW_NAMES)
                name = obj.ROW_NAMES{i};
                on = any(ismember(obj.ROW_SECTIONS{i}, obj.Sections));
                if ~on
                    heights(i) = 0;
                end
                if isfield(obj.Rows_, name) && ~isempty(obj.Rows_.(name)) && isvalid(obj.Rows_.(name))
                    obj.Rows_.(name).Visible = matlab.lang.OnOffSwitchState(on);
                end
            end
            obj.H_.root.RowHeight = num2cell(heights);

            % Link row: the port and its Connect button move together;
            % probing is its own section because it is the slow one.
            link   = ismember("Link", obj.Sections);
            detect = ismember("Detect", obj.Sections);
            obj.setItemVisible_('port',    link);
            obj.setItemVisible_('connect', link);
            obj.setItemVisible_('detect',  detect);
            if obj.hasControl_('port')
                widths = {'1x', 56, 76};
                if ~link,   widths([1 3]) = {0}; end
                if ~detect, widths{2} = 0; end
                obj.Rows_.Link.ColumnWidth = widths;
            end

            % Position row: the readout and its Zero button.
            pos  = ismember("Position", obj.Sections);
            zero = ismember("Zero", obj.Sections);
            obj.setItemVisible_('posLabel', pos);
            obj.setItemVisible_('position', pos);
            obj.setItemVisible_('zero',     zero);
            if obj.hasControl_('position')
                widths = {30, '1x', 46};
                if ~pos,  widths(1:2) = {0, '1x'}; end
                if ~zero, widths{3} = 0; end
                obj.Rows_.Position.ColumnWidth = widths;
            end

            % Jog row: speed, the two direction buttons, and STOP, each
            % giving its width back to the others when it is off.
            speed = ismember("Speed", obj.Sections);
            jogs  = ismember("Jog", obj.Sections);
            stop  = ismember("Stop", obj.Sections);
            obj.setItemVisible_('speed', speed);
            obj.setItemVisible_('ccw',   jogs);
            obj.setItemVisible_('cw',    jogs);
            obj.setItemVisible_('stop',  stop);
            if obj.hasControl_('speed')
                widths = {70, '1x', '1x', 54};
                if ~speed, widths{1} = 0; end
                if ~jogs,  widths(2:3) = {0, 0}; end
                if ~stop,  widths{4} = 0; end
                obj.Rows_.Jog.ColumnWidth = widths;
            end

            % Nothing on screen to read out means nothing worth asking the
            % controller for.
            if any(ismember(["Status","Position"], obj.Sections))
                obj.startPolling();
            else
                obj.stopPolling();
            end
        end

        function setItemVisible_(obj, name, tf)
            if ~obj.hasControl_(name), return; end
            obj.H_.(name).Visible = matlab.lang.OnOffSwitchState(tf);
        end

        function tf = hasControl_(obj, name)
            tf = isfield(obj.H_, name) && ~isempty(obj.H_.(name)) && isvalid(obj.H_.(name));
        end

        % --- Controls and their properties ------------------------------------------

        function onSettingChanged_(obj, name)
            % Shared tail of the property setters: move the control, then
            % remember the value when the operator was the one who set it.
            % Nothing is written to the controller from here -- a speed
            % takes effect at the next jog, and a move when Move is pressed.
            obj.updateControl_(name);
            if obj.Applying_, return; end

            if strcmp(name, 'Verbosity') && ~isempty(obj.Motor) && isvalid(obj.Motor)
                obj.Motor.Verbosity = string(obj.Verbosity);
            end

            % A jog already running follows the speed field, which is the
            % one setting an operator expects to act immediately.
            if strcmp(name, 'SpeedRPM') && obj.JogSign_ ~= 0 && obj.IsConnected
                obj.safeSend_(@() obj.Motor.setRPM(obj.JogSign_ * max(abs(obj.SpeedRPM), 1)));
            end

            if obj.FromUI_
                obj.rememberSetting_(name, obj.(name));
            end
        end

        function onMoveUnitsChanged_(obj, wasUnits)
            % Units are how the move is written down, not how far it goes, so
            % the amount is converted with them: 90 deg becomes 0.25 rot and
            % the commutator turns the same distance either way.
            obj.updateControl_('MoveUnits');
            if obj.Applying_ || strcmp(wasUnits, obj.MoveUnits), return; end

            obj.Applying_ = true;
            if strcmp(wasUnits, 'deg') && strcmp(obj.MoveUnits, 'rot')
                obj.MoveAmount = obj.MoveAmount / 360;
            elseif strcmp(wasUnits, 'rot') && strcmp(obj.MoveUnits, 'deg')
                obj.MoveAmount = obj.MoveAmount * 360;
            end
            obj.Applying_ = false;

            if obj.hasControl_('move')
                lim = obj.moveLimits_();
                obj.H_.move.Limits = lim;
                obj.MoveAmount = min(max(obj.MoveAmount, lim(1)), lim(2));
            end
            obj.updateControl_('MoveAmount');

            if obj.FromUI_
                % The amount goes with them: a bare number remembered in one
                % unit and restored in another would be a different move.
                obj.UserPrefs_.MoveUnits = obj.MoveUnits;
                obj.rememberSetting_('MoveAmount', obj.MoveAmount);
            end
        end

        function updateControl_(obj, name)
            % Move one control to match its property, without re-entering
            % the callback that may have moved the property in the first place.
            switch name
                case 'SpeedRPM'
                    if obj.hasControl_('speed')
                        obj.H_.speed.Value = min(obj.SpeedRPM, obj.LimitRPM_);
                    end
                case 'MoveAmount'
                    if obj.hasControl_('move'), obj.H_.move.Value = obj.MoveAmount; end
                case 'MoveUnits'
                    if obj.hasControl_('units'), obj.H_.units.Value = obj.MoveUnits; end
            end
        end

        function onEditChanged_(obj, name, value)
            % A control moved: assign through the property so the operator's
            % path and a paradigm's are the same one, flagged as the
            % operator's so it is remembered for the next session.
            obj.FromUI_ = true;
            try
                obj.(name) = value;
            catch ME
                vprintf(0, 1, ME)
                obj.updateControl_(name);
            end
            obj.FromUI_ = false;
        end

        function onConnectPressed_(obj)
            if obj.IsConnected
                obj.disconnect();
            else
                obj.connect();
            end
        end

        function selectPort_(obj, port)
            port = char(string(port));
            if strcmp(port, '(none)')
                port = '';
            end
            obj.StagedPort_ = port;
            obj.rememberSetting_('Port', port);
            obj.refreshPorts();
            obj.updateLinkUI_();
        end

        function [items, value] = portItems_(obj)
            % Every serial port the machine reports, plus the one in use (an
            % open port drops out of the available list) and the staged
            % selection, so a remembered port survives the controller being
            % switched off.
            try
                items = cellstr(serialportlist('all'));
            catch
                items = {};
            end
            if isempty(items)
                try
                    items = cellstr(serialportlist('available'));
                catch
                    items = {};
                end
            end
            items = reshape(items, 1, []);

            extra = {};
            if ~isempty(obj.StagedPort_), extra{end+1} = obj.StagedPort_; end
            try
                if ~isempty(obj.Motor) && isvalid(obj.Motor) && strlength(obj.Motor.Port) > 0
                    extra{end+1} = char(obj.Motor.Port);
                end
            catch
            end
            items = unique([items, extra], 'stable');

            if isempty(obj.StagedPort_)
                items = [{'(none)'}, items];
                value = '(none)';
            else
                value = obj.StagedPort_;
            end
        end

        function port = initialPort_(obj, options, saved)
            % Port preselected at construction: the caller's, else the one
            % the driver is already configured for (a controller handed in
            % knows its own port, and that outranks this panel's memory),
            % else the one the operator last picked here. Preselected only:
            % nothing is opened until Connect.
            port = '';
            if isfield(options, 'Port')
                port = char(options.Port);
            end
            if ~isempty(port), return; end
            try
                if ~isempty(obj.Motor) && isvalid(obj.Motor)
                    port = char(obj.Motor.Port);
                end
            catch
            end
            if isempty(port) && isfield(saved, 'Port')
                port = char(saved.Port);
            end
        end

        % --- Rendering ---------------------------------------------------------------

        function updateLinkUI_(obj)
            % The Connect button says what pressing it would do, and the
            % controls that need a link are dead without one -- which is how
            % a panel over an unplugged rig reads as "not connected yet"
            % rather than as broken.
            if obj.hasControl_('connect')
                if obj.IsConnected
                    obj.H_.connect.Text = 'Disconnect';
                else
                    obj.H_.connect.Text = 'Connect';
                end
            end

            obj.setEnabled_(true);
            obj.refreshPorts();

            if obj.ReviewMode_
                obj.setStatus_('Review (hardware offline)', obj.COLOR_OFF);
            elseif obj.IsConnected
                obj.setStatus_(obj.connectedText_(), obj.COLOR_ON);
            else
                obj.setStatus_('Not connected', obj.COLOR_OFF);
            end
        end

        function setEnabled_(obj, tf)
            % The motion controls follow the link; the port row follows only
            % whether something slow is running, so a failed connect can be
            % retried on another port.
            live = tf && obj.IsConnected && ~obj.ReviewMode_;
            for name = {'ccw','cw','stop','go','zero','speed','move','units'}
                if obj.hasControl_(name{1})
                    obj.H_.(name{1}).Enable = matlab.lang.OnOffSwitchState(live);
                end
            end
            for name = {'port','connect','detect'}
                if obj.hasControl_(name{1})
                    obj.H_.(name{1}).Enable = matlab.lang.OnOffSwitchState(tf && ~obj.ReviewMode_);
                end
            end
        end

        function renderPosition_(obj)
            if ~obj.hasControl_('position'), return; end
            if isfinite(obj.PositionDeg)
                txt = [sprintf('%.2f', obj.PositionDeg) char(176)];
            else
                txt = '--';
            end
            if ~strcmp(obj.H_.position.Text, txt)
                obj.H_.position.Text = txt;
            end
        end

        function setStatus_(obj, text, color)
            obj.Status = char(text);
            if obj.hasControl_('status') && ~strcmp(obj.H_.status.Text, obj.Status)
                obj.H_.status.Text = obj.Status;
            end
            if obj.hasControl_('lamp') && ~isequal(obj.H_.lamp.Color, color)
                obj.H_.lamp.Color = color;
            end
        end

        function txt = connectedText_(obj)
            if obj.IsConnected && strlength(obj.Motor.Port) > 0
                txt = sprintf('Connected on %s', obj.Motor.Port);
            elseif obj.IsConnected
                txt = 'Connected';
            else
                txt = 'Not connected';
            end
        end

        function setJogVisual_(obj, sgn, tf)
            % The lit button is the only thing saying which way the motor is
            % turning, since a jog has no other outward sign until the
            % position moves.
            if sgn < 0
                name = 'ccw';
            else
                name = 'cw';
            end
            if ~obj.hasControl_(name), return; end
            if tf
                obj.H_.(name).BackgroundColor = obj.COLOR_JOG_ON;
            else
                obj.H_.(name).BackgroundColor = [0.96 0.96 0.96];
            end
        end

        function clearJogVisual_(obj)
            obj.setJogVisual_(-1, false);
            obj.setJogVisual_(+1, false);
        end

        % --- Context menu -------------------------------------------------------------

        function createContextMenu_(obj)
            % Right-click menu. Everything the panel can do is reachable
            % from here, which is what makes hiding a row safe: the ports
            % list, the connection, and the verbosity have no controls of
            % their own at all once the Link row is off.
            f = ancestor(obj.Parent, 'figure');
            if isempty(f) || ~isvalid(f), return; end

            try
                cm = uicontextmenu(f);
                obj.ContextMenu = cm;
                obj.ShowMenuH_ = uimenu(cm, Text = 'Show');
                obj.PortMenuH_ = uimenu(cm, Text = 'Port');
                obj.VerbMenuH_ = uimenu(cm, Text = 'Driver Messages');
                uimenu(cm, Text = 'Refresh Port List', Separator = 'on', ...
                    MenuSelectedFcn = @(~,~) obj.refreshPorts());
                uimenu(cm, Text = 'Detect Controller...', ...
                    MenuSelectedFcn = @(~,~) obj.detectPort());
                uimenu(cm, Text = 'Zero Position', ...
                    MenuSelectedFcn = @(~,~) obj.zeroPosition());
                obj.SwapMenuH_ = uimenu(cm, Text = 'Swap CW / CCW Labels', ...
                    MenuSelectedFcn = @(~,~) obj.toggleSwapLabels_());
                obj.addPopOutMenu_(cm);

                cm.ContextMenuOpeningFcn = @(~,~) obj.refreshMenus_();
            catch ME
                vprintf(3, 'gui.components.NanoMotor: context menu unavailable: %s', ME.message)
                obj.ContextMenu = [];
                return
            end

            targets = [{obj.H_.root}, struct2cell(obj.Rows_)', struct2cell(obj.H_)'];
            for k = 1:numel(targets)
                h = targets{k};
                if isempty(h) || ~isgraphics(h) || ~isvalid(h), continue; end
                try
                    h.ContextMenu = cm;
                catch ME
                    vprintf(3, 'gui.components.NanoMotor: cannot attach context menu: %s', ME.message)
                end
            end
        end

        function refreshMenus_(obj)
            obj.refreshShowMenu_();
            obj.refreshPortMenu_();
            obj.refreshVerbosityMenu_();
            if ~isempty(obj.SwapMenuH_) && isvalid(obj.SwapMenuH_)
                obj.SwapMenuH_.Checked = ...
                    matlab.lang.OnOffSwitchState(obj.SwapDirectionLabels);
            end
        end

        function refreshShowMenu_(obj)
            m = obj.ShowMenuH_;
            if isempty(m) || ~isvalid(m), return; end
            delete(m.Children);

            for name = obj.SECTIONS
                item = uimenu(m, Text = char(name), ...
                    MenuSelectedFcn = @(~,~) obj.toggleSection_(name));
                item.Checked = ismember(name, obj.Sections);
            end

            uimenu(m, Text = 'Show All', Separator = 'on', ...
                Enable = matlab.lang.OnOffSwitchState(numel(obj.Sections) < numel(obj.SECTIONS)), ...
                MenuSelectedFcn = @(~,~) obj.setSectionsFromUI_(obj.SECTIONS));
            uimenu(m, Text = 'Reset to Default', ...
                MenuSelectedFcn = @(~,~) obj.resetSections_());
        end

        function refreshPortMenu_(obj)
            m = obj.PortMenuH_;
            if isempty(m) || ~isvalid(m), return; end
            delete(m.Children);

            items = obj.portItems_();
            for i = 1:numel(items)
                item = uimenu(m, Text = items{i}, ...
                    MenuSelectedFcn = @(~,~) obj.selectPort_(items{i}));
                item.Checked = strcmp(items{i}, obj.StagedPort_);
            end

            if obj.IsConnected
                uimenu(m, Text = 'Disconnect', Separator = 'on', ...
                    MenuSelectedFcn = @(~,~) obj.disconnect());
            else
                uimenu(m, Text = 'Connect', Separator = 'on', ...
                    Enable = matlab.lang.OnOffSwitchState(~obj.ReviewMode_), ...
                    MenuSelectedFcn = @(~,~) obj.connect());
            end
        end

        function refreshVerbosityMenu_(obj)
            m = obj.VerbMenuH_;
            if isempty(m) || ~isvalid(m), return; end
            delete(m.Children);

            levels = {'SILENT', 'Nothing'; 'INFO', 'What it is doing'; ...
                      'DETAILED', 'Full serial transcript'};
            for i = 1:size(levels, 1)
                item = uimenu(m, Text = levels{i,2}, ...
                    MenuSelectedFcn = @(~,~) obj.setVerbosityFromUI_(levels{i,1}));
                item.Checked = strcmp(obj.Verbosity, levels{i,1});
            end
        end

        function setVerbosityFromUI_(obj, level)
            obj.FromUI_ = true;
            try
                obj.Verbosity = level;
            catch ME
                vprintf(0, 1, ME)
            end
            obj.FromUI_ = false;
        end

        function toggleSection_(obj, name)
            if ismember(name, obj.Sections)
                sel = setdiff(obj.Sections, name, 'stable');
            else
                sel = [obj.Sections, name];
            end
            obj.setSectionsFromUI_(sel);
        end

        function setSectionsFromUI_(obj, sel)
            obj.FromUI_ = true;
            obj.Sections = sel;
            obj.FromUI_ = false;
        end

        function resetSections_(obj)
            % Back to the layout the hosting GUI asked for, and forget the
            % operator's -- otherwise the saved one would win again next time.
            obj.Sections = obj.DefaultSections_;
            if isfield(obj.UserPrefs_, 'Sections')
                obj.UserPrefs_ = rmfield(obj.UserPrefs_, 'Sections');
            end
            obj.savePreferences_();
        end

        % --- Remembered configuration ---------------------------------------------------

        function s = loadPreferences_(obj)
            % What the operator configured in this panel last time. Only ever
            % holds what they changed HERE -- a value a paradigm assigned is
            % the paradigm's to reassert, not something to resurrect a
            % session later.
            s = struct();
            try
                pname = obj.preferenceName_();
                if ~ispref(obj.PREF_GROUP, pname), return; end
                s = getpref(obj.PREF_GROUP, pname);
                if ~isstruct(s), s = struct(); return; end
            catch ME
                vprintf(2, 'gui.components.NanoMotor: failed to load preferences: %s', ME.message)
                s = struct();
            end
        end

        function rememberSetting_(obj, name, value)
            obj.UserPrefs_.(name) = value;
            obj.savePreferences_();
        end

        function savePreferences_(obj)
            try
                setpref(obj.PREF_GROUP, obj.preferenceName_(), obj.UserPrefs_);
            catch ME
                vprintf(2, 'gui.components.NanoMotor: failed to save preferences: %s', ME.message)
            end
        end

        function n = preferenceName_(obj)
            % Preference key scoped to the hosting GUI: explicit tag, else
            % the ancestor figure Tag, else its Name, else 'default'.
            n = obj.PreferenceTag_;
            if isempty(n)
                try
                    f = ancestor(obj.Parent, 'figure');
                    if ~isempty(f) && isvalid(f)
                        if ~isempty(f.Tag)
                            n = f.Tag;
                        elseif ~isempty(f.Name)
                            n = f.Name;
                        end
                    end
                catch
                end
            end
            if isempty(n), n = 'default'; end
            n = matlab.lang.makeValidName(n);
        end
    end


    methods (Static, Access = private)

        function s = shortMsg_(msg)
            % One line of an error message, short enough for the status row.
            s = char(string(msg));
            s = strrep(s, newline, ' ');
            if numel(s) > 70
                s = [s(1:70) '...'];
            end
        end

        function v = pick_(options, saved, name, default)
            % Resolve one setting: what the caller asked for, else what the
            % operator left behind, else the built-in default. An option
            % declared with no default in the arguments block is simply
            % absent when it was not supplied, which is what makes the first
            % of those three distinguishable from the others.
            if isfield(options, name)
                v = options.(name);
            elseif isstruct(saved) && isfield(saved, name) && ~isempty(saved.(name))
                v = saved.(name);
            else
                v = default;
            end
        end

        function sgn = directionSign_(direction)
            % -1/+1, 'ccw'/'cw', or 'CCW'/'CW' -- the button, the menu and a
            % script all name a direction differently.
            if isnumeric(direction) || islogical(direction)
                sgn = sign(double(direction));
                if sgn == 0, sgn = 1; end
                return
            end
            d = upper(strtrim(char(string(direction))));
            switch d
                case {'CCW', '-'}
                    sgn = -1;
                case {'CW', '+'}
                    sgn = 1;
                otherwise
                    error('gui:components:NanoMotor:BadDirection', ...
                        'Direction must be CW, CCW, +1 or -1; got "%s".', d);
            end
        end

        function n = nextInstanceId_()
            persistent counter
            if isempty(counter), counter = 0; end
            counter = counter + 1;
            n = counter;
        end
    end
end
