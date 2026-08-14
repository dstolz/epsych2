classdef SyringePump < gui.PopOut
    % obj = gui.SyringePump(source, container, Name=Value)
    % Operator panel for a New Era NE-1000 syringe pump (hw.NE1000).
    %
    % Shows how much the pump has dispensed, refreshed on its own timer
    % (~4 Hz by default), and gives the operator the four settings a reward
    % pump actually needs at the rig: which serial port the pump is on,
    % the syringe inside diameter, the pumping rate, and whether the pusher
    % pushes (Infuse, the default) or pulls (Withdraw). Start / Stop / Zero
    % buttons drive the pump by hand.
    %
    % Every setting is also a settable property, so a paradigm can drive the
    % panel programmatically: obj.Rate = 1.2 both writes the pump and moves
    % the control, exactly as a keystroke would.
    %
    %   Rate is expressed in the component's RateUnits (mL/min by default),
    %   and the interface is switched to those units on attach so the value
    %   goes on the wire unrounded -- the pump's command grammar allows only
    %   4 digits, so 0.7 mL/min expressed in uL/hr would overflow it.
    %   The change is logged; give RateUnits='MH' (etc.) to keep a protocol's
    %   own units instead.
    %
    %   Volume is displayed in VolumeUnits ("mL" by default), converted from
    %   whatever units the pump reports (it picks uL below a 14 mm syringe
    %   diameter and mL at or above, so its resolution at 21.59 mm is 1 uL).
    %
    %   Both are operator-facing: the right-click Units menu offers uL or mL
    %   per minute or per hour for the rate, and uL, mL, or the pump's own
    %   units for the readout. Changing the rate units converts Rate with
    %   them, so the pump never changes speed underneath the operator.
    %
    % The panel works with or without a pump attached. Given an
    % epsych.Runtime it drives that session's hw.NE1000; given nothing (or a
    % runtime with no pump) it constructs an offline interface of its own,
    % so the operator can pick a port and connect from the panel itself.
    % Settings made while disconnected are held and pushed on connect.
    %
    % Which controls appear is programmatic: Sections lists the parts that
    % are shown, and assigning it (or calling show/hide) reflows the panel at
    % any time. A rig whose protocol owns the rate and whose syringe never
    % changes can be left with nothing but the readout:
    %
    %   p.Sections = ["Volume" "Status"];   % readout only
    %   p.hide(["Diameter" "Port" "Detect"])
    %   p.show("Direction")
    %
    % Section names are Volume, Status, Port, Detect, Diameter, Rate,
    % Direction, TTL, Start, Stop, Zero, plus the group aliases Connection
    % (=Port+Detect), Settings (=Diameter+Rate+Direction+TTL), Triggers
    % (=Start+Stop+Zero), All, and None. With neither Volume nor Status shown
    % there is nothing to read out, so the poll timer stops and the panel
    % costs the pump no serial traffic at all.
    %
    % The TTL section is the one control that changes what starts the pump
    % rather than how it runs: with it enabled, the pump's own trigger input
    % (DB-9 pin 2) starts and stops it, so a rig can gate reward from a
    % digital line with no host round trip. WHICH trigger mode that is
    % (level, foot switch, start-only, ...) is programmatic only -- it
    % follows how the rig is wired, so it is a construction option and the
    % TriggerMode property, never a control:
    %
    %   obj.addSyringePump(panel, TriggerMode='ST', TTLTrigger=true);
    %
    % Properties:
    %   Diameter        - Syringe inside diameter, mm (default 21.59)
    %   Rate            - Pumping rate in RateUnits (default 0.7 mL/min)
    %   RateUnits       - 'UM'|'MM'|'UH'|'MH' (default 'MM', i.e. mL/min)
    %   VolumeUnits     - Readout units: 'uL', 'mL' (default), or 'auto'
    %   Direction       - 'Infuse' (push) or 'Withdraw' (pull)
    %   TTLTrigger      - Whether the pump's TTL trigger input may start it
    %   TriggerMode     - Which trigger mode that is (programmatic only)
    %   Sections        - Parts of the panel currently shown
    %   Interface       - The hw.NE1000 being driven
    %   IsConnected     - True while the pump link is up (Dependent)
    %   Port            - Port currently selected in the panel (Dependent)
    %   VolumeInfused   - Infused volume in VolumeUnits, as of the last poll
    %   VolumeWithdrawn - Withdrawn volume in VolumeUnits, as of the last poll
    %   Status          - Pump status text as of the last poll
    %   ContextMenu     - The right-click menu; host GUIs may append items
    %
    % Methods:
    %   show / hide           - Show or hide parts of the panel by name
    %   isSectionVisible      - True when a named part is shown
    %   connect / disconnect  - Open or close the pump link on the selected port
    %   detectPort            - Probe the serial ports for a pump
    %   refreshPorts          - Re-read the serial port list into the dropdown
    %   startPump / stopPump  - RUN / STP
    %   zeroVolume            - Clear both dispensed-volume accumulators
    %   refresh               - Re-read every setting and reading from the pump
    %   startPolling / stopPolling - Resume / pause the volume readout timer
    %
    % Examples:
    %   % Inside a gui.BoxGUI build method
    %   obj.addSyringePump(panelReward);
    %   obj.addSyringePump(panelReward, Rate=1.5, Diameter=14.43);
    %
    %   % Only the readout and the manual buttons; the protocol owns the rest
    %   obj.addSyringePump(panelReward, Sections=["Volume" "Status" "Triggers"]);
    %
    %   % Standalone, no protocol: pick a port in the panel and connect
    %   f = uifigure('Name','Pump');
    %   p = gui.SyringePump([], f);
    %
    % See also: documentation/gui/gui_SyringePump.md, hw.NE1000,
    % gui.BoxGUI.addSyringePump, gui.Parameter_Monitor, gui.PopOut

    properties
        % Syringe inside diameter in mm. Scales every rate and volume the
        % pump computes; the pump rejects a change while it is pumping.
        Diameter (1,1) double {mustBeInRange(Diameter, 0.1, 50)} = 21.59

        % Pumping rate in RateUnits (mL/min by default).
        Rate (1,1) double {mustBeNonnegative} = 0.7

        % Units the rate is written in: 'UM' uL/min, 'MM' mL/min (default),
        % 'UH' uL/hr, 'MH' mL/hr. Assigning it converts Rate with it -- the
        % pump keeps running at the same speed, it is only written down
        % differently -- switches the interface to match, and relabels the
        % control. The operator does the same from the right-click Units menu.
        RateUnits (1,2) char {mustBeMember(RateUnits, {'UM','MM','UH','MH'})} = 'MM'

        % Units the dispensed-volume readout is displayed in: 'mL' (default),
        % 'uL', or 'auto' to follow whatever the pump reports (uL below a
        % 14 mm syringe diameter, mL at or above). Display only: it changes
        % no value the pump is given.
        VolumeUnits (1,:) char {mustBeMember(VolumeUnits, {'uL','mL','auto'})} = 'mL'

        % 'Infuse' pushes the syringe (reward delivery), 'Withdraw' pulls it
        % (refilling). The pump rejects a change while pumping to a target.
        Direction (1,:) char {mustBeMember(Direction, {'Infuse','Withdraw'})} = 'Infuse'

        % Whether the pump's TTL trigger input (DB-9 pin 2) may start and stop
        % it, which is how a rig delivers hardware-timed reward with no host
        % round trip. The pump keeps this setting through a power cycle, so
        % the panel asserts it rather than assuming it.
        TTLTrigger (1,1) logical = false

        % Which TTL trigger mode is used when TTLTrigger is on; see
        % hw.NE1000.TRIGGER_MODES. Programmatic only -- no control, no menu
        % entry, and not remembered between sessions: the mode follows how
        % pin 2 is wired, which is the paradigm's business and not the
        % operator's. Left alone it is whatever the interface is set to.
        % (the list is hw.NE1000.TRIGGER_MODES, spelled out because property
        % validation functions may only reference literals)
        TriggerMode (1,2) char {mustBeMember(TriggerMode, ...
            {'FT','FH','F2','LE','ST','T2','SP','P2','RL','RH','SL','SH'})} = 'LE'

        % Parts of the panel that are shown, as a string array of section
        % names (see SECTIONS). Assign it -- or call show/hide -- at any time;
        % the panel reflows, keeping every control's state. Group aliases are
        % expanded on assignment, so this always reads back as the individual
        % names it resolved to.
        Sections (1,:) string = gui.SyringePump.SECTIONS
    end

    properties (SetAccess = private)
        Parent                          % Hosting container supplied at construction
        Interface = []                  % hw.NE1000 this panel drives
        UpdatePeriod (1,1) double = 0.25 % volume readout period, seconds

        VolumeInfused (1,1) double = NaN   % last poll, in the displayed units
        VolumeWithdrawn (1,1) double = NaN % last poll, in the displayed units
        Status (1,:) char = ''             % last poll, e.g. 'Infusing', 'Alarm:S'

        Timer = []                      % readout timer
        ContextMenu = []                % right-click menu
    end

    properties (Dependent)
        IsConnected % True while the pump link is up
        Port        % Serial port currently selected in the panel
    end

    properties (Access = private)
        OwnsInterface_ (1,1) logical = false % delete the interface on teardown
        Applying_ (1,1) logical = false      % suppress hardware writes from set methods
        Source_ = []                         % construction source, reused by the pop-out
        StagedPort_ (1,:) char = ''          % port chosen in the dropdown
        PreferenceTag_ (1,:) char = ''
        FontSize_ (1,1) double = 12
        H_ (1,1) struct = struct()           % graphics handles
        Rows_ (1,1) struct = struct()        % one container handle per ROW_NAMES entry
        DefaultSections_ (1,:) string = string.empty(1,0) % what "Reset to Default" restores
        FromUI_ (1,1) logical = false        % the change came from the panel, so remember it
        UserPrefs_ (1,1) struct = struct()   % the operator's remembered configuration
        ShowMenuH_ = []                      % "Show" submenu
        ValueMenuH_ = []                     % "Set Value" submenu
        UnitsMenuH_ = []                     % "Units" submenu
        DestroyListener_ = event.listener.empty
        LastReadout_ (1,:) char = ''         % change detection for the big label
    end

    properties (Constant)
        % Individually hideable parts of the panel, in layout order.
        SECTIONS = ["Volume", "Status", "Port", "Detect", "Diameter", ...
                    "Rate", "Direction", "TTL", "Start", "Stop", "Zero"]
    end

    properties (Constant, Access = private)
        PREF_GROUP = 'epsych2_gui_SyringePump'

        % Group names accepted wherever a section name is, and what each
        % expands to. 'All' and 'None' are handled in normalizeSections_.
        ALIAS_NAMES = {'Connection', 'Settings', 'Triggers'}
        ALIAS_MEMBERS = {["Port","Detect"], ["Diameter","Rate","Direction","TTL"], ...
                         ["Start","Stop","Zero"]}

        % The panel's rows, in order, with their heights in pixels and the
        % sections that keep each one on screen. A row whose sections are all
        % hidden collapses to zero height rather than being destroyed, so
        % showing it again costs nothing and no control loses its state.
        ROW_NAMES   = {'Volume', 'Status', 'Port', 'Diameter', 'Rate', 'Direction', 'TTL', 'Triggers'}
        ROW_HEIGHTS = [58, 20, 26, 26, 26, 34, 26, 30]
        ROW_SECTIONS = {"Volume", "Status", ["Port","Detect"], "Diameter", ...
                        "Rate", "Direction", "TTL", ["Start","Stop","Zero"]}

        % Rate unit codes and their operator-facing labels, index-aligned.
        RATE_CODES  = {'UM', 'MM', 'UH', 'MH'}
        RATE_LABELS = {'uL/min', 'mL/min', 'uL/hr', 'mL/hr'}

        % Volume readout units and their menu labels, index-aligned. 'auto'
        % is not a unit but a policy: display whatever the pump reported.
        VOLUME_CODES  = {'uL', 'mL', 'auto'}
        VOLUME_LABELS = {'uL', 'mL', 'Follow the pump'}

        % Status prompts that mean the motor is turning, and the colors the
        % status line takes when running / alarmed / idle.
        RUNNING_STATES = {'Infusing', 'Withdrawing', 'Purging'}
        COLOR_RUN   = [0.10 0.50 0.15]
        COLOR_ALARM = [0.75 0.10 0.10]
        COLOR_IDLE  = [0.35 0.35 0.35]
        COLOR_REJECT = [1.00 0.85 0.85]
    end


    methods

        function obj = SyringePump(source, container, options)
            % obj = gui.SyringePump(source, container, ...)
            %  source    - hw.NE1000 to drive, an epsych.Runtime (whose
            %              Interfaces are searched for one), or [] to have
            %              the panel construct an offline interface of its own.
            %  container - Figure, panel, tab, or layout hosting the panel.
            %  Diameter      - Syringe inside diameter, mm. Default 21.59.
            %  Rate          - Pumping rate in RateUnits. Default 0.7.
            %  Direction     - 'Infuse' (default) or 'Withdraw'.
            %  TTLTrigger    - Let the pump's TTL trigger input start and stop
            %                  it. Default false.
            %  TriggerMode   - Trigger mode used when TTLTrigger is on; see
            %                  hw.NE1000.TRIGGER_MODES. Programmatic only.
            %                  Default: whatever the interface is set to.
            %  RateUnits     - 'MM' (default, mL/min), 'UM', 'UH', or 'MH'.
            %                  The interface is switched to these units on
            %                  attach; the operator may change them here.
            %  VolumeUnits   - Readout units: 'mL' (default), 'uL', or 'auto'
            %                  to follow whatever the pump reports.
            %  UpdatePeriod  - Readout period in seconds. Default 0.25 (4 Hz).
            %  Port          - Serial port to preselect. Default: the
            %                  interface's port, else the last one used here.
            %  ApplyOnStart  - Push Diameter/Rate/Direction to a connected
            %                  pump at construction (default true). False
            %                  reads the pump's current values instead.
            %  Sections      - Parts of the panel to show; see SECTIONS and
            %                  the group aliases. Default "All". This is the
            %                  DEFAULT layout: a selection the operator made
            %                  from the right-click menu in an earlier
            %                  session takes precedence, and "Reset to
            %                  Default" in that menu comes back to this.
            %  FontSize      - Base font size for the controls. Default 12.
            %  PreferenceTag - Key for the remembered configuration (defaults
            %                  to the hosting figure Tag/Name).
            %
            % Diameter, Rate, Direction, RateUnits, VolumeUnits, Sections,
            % and Port have no built-in default in the arguments block on
            % purpose: the absence of an option is what distinguishes "the
            % caller did not say" from "the caller asked for the default
            % value", which is what lets the operator's remembered
            % configuration fill the gap.
            arguments
                source = []
                container (1,1) = uifigure(Name = 'Syringe Pump')
                options.Diameter (1,1) double {mustBeInRange(options.Diameter, 0.1, 50)}
                options.Rate (1,1) double {mustBeNonnegative}
                options.Direction (1,:) char {mustBeMember(options.Direction, {'Infuse','Withdraw'})}
                options.TTLTrigger (1,1) logical
                options.TriggerMode (1,2) char
                options.RateUnits (1,2) char {mustBeMember(options.RateUnits, {'UM','MM','UH','MH'})}
                options.VolumeUnits (1,:) char {mustBeMember(options.VolumeUnits, {'uL','mL','auto'})}
                options.UpdatePeriod (1,1) double {mustBePositive} = 0.25
                options.Port (1,:) char
                options.ApplyOnStart (1,1) logical = true
                options.Sections (1,:) string
                options.FontSize (1,1) double {mustBePositive} = 12
                options.PreferenceTag (1,:) char = ''
            end

            obj.Parent          = container;
            obj.Source_         = source;
            obj.UpdatePeriod    = options.UpdatePeriod;
            obj.PreferenceTag_  = options.PreferenceTag;
            obj.FontSize_       = options.FontSize;

            % The panel is a fixed stack of short rows, so the pop-out wants
            % a window barely bigger than the panel, not the mixin default.
            obj.PopOutSize  = [340 300];
            obj.PopOutLabel = 'Syringe Pump';

            % What the operator configured here last time. Everything below
            % resolves as: what the caller asked for, else what the operator
            % left behind, else the built-in default.
            saved = obj.loadPreferences_();
            obj.UserPrefs_ = saved;

            % Units first: every value below is a number in them. Assigning
            % them here must not convert anything -- there is nothing yet to
            % convert -- so it goes through the same guard the settings use.
            obj.Applying_ = true;
            obj.seedSetting_('RateUnits', ...
                char(gui.SyringePump.pick_(options, saved, 'RateUnits', 'MM', true)), 'MM');
            obj.seedSetting_('VolumeUnits', ...
                char(gui.SyringePump.pick_(options, saved, 'VolumeUnits', 'mL', true)), 'mL');
            obj.Applying_ = false;

            % Layout: the caller's Sections is the default the menu resets
            % to, and a saved selection overrides it (as gui.NextTrial's
            % saved field selection overrides its Fields option).
            obj.DefaultSections_ = obj.normalizeSections_( ...
                gui.SyringePump.pick_(options, saved, 'Sections', "All", false));
            obj.Sections = gui.SyringePump.pick_(options, saved, 'Sections', ...
                obj.DefaultSections_, true);

            % Seed the settings without touching hardware: the interface is
            % not resolved yet, and applyToHardware_ below decides whether
            % these values or the pump's own are authoritative.
            obj.Applying_ = true;
            obj.seedSetting_('Diameter', gui.SyringePump.pick_(options, saved, 'Diameter', 21.59, true), 21.59);
            obj.seedSetting_('Rate',     obj.initialRate_(options, saved), 0.7);
            obj.seedSetting_('Direction', ...
                char(gui.SyringePump.pick_(options, saved, 'Direction', 'Infuse', true)), 'Infuse');
            obj.seedSetting_('TTLTrigger', ...
                logical(gui.SyringePump.pick_(options, saved, 'TTLTrigger', false, true)), false);
            obj.Applying_ = false;

            obj.resolveInterface_(source);

            % The trigger mode is the one setting the operator has no say in,
            % so it is never taken from the remembered configuration: what the
            % caller asked for, else whatever the interface is already
            % configured for -- which is how a protocol's choice of mode
            % survives a panel opening over its pump.
            obj.Applying_ = true;
            obj.seedSetting_('TriggerMode', ...
                char(gui.SyringePump.pick_(options, saved, 'TriggerMode', ...
                    obj.Interface.TriggerMode, false)), 'LE');
            obj.Applying_ = false;
            if isfield(options, 'TriggerMode')
                obj.pushTriggerMode_();
            end
            obj.StagedPort_ = obj.initialPort_(options, saved);

            obj.buildUI_(container);

            if obj.IsConnected
                obj.applyRateUnits_();
                if options.ApplyOnStart
                    obj.applyToHardware_();
                else
                    obj.readFromHardware_();
                end
            end

            obj.updateLinkUI_();
            obj.createTimer_();
        end

        function delete(obj)
            % Stop the readout timer, drop the menu, and release the
            % interface -- but only when this panel created it; one borrowed
            % from a running session outlives the window.
            try
                if ~isempty(obj.Timer) && isvalid(obj.Timer)
                    stop(obj.Timer);
                    delete(obj.Timer);
                end
            catch
            end
            try
                delete(obj.DestroyListener_);
            catch
            end
            try
                if ~isempty(obj.ContextMenu) && isvalid(obj.ContextMenu)
                    delete(obj.ContextMenu);
                end
            catch
            end
            try
                if obj.OwnsInterface_ && ~isempty(obj.Interface) && isvalid(obj.Interface)
                    delete(obj.Interface);
                end
            catch ME
                vprintf(2, 'gui.SyringePump: releasing the interface failed: %s', ME.message)
            end
        end

        % --- Dependent properties -------------------------------------------

        function tf = get.IsConnected(obj)
            tf = ~isempty(obj.Interface) && isvalid(obj.Interface) && obj.Interface.IsConnected;
        end

        function p = get.Port(obj)
            p = obj.StagedPort_;
        end

        % --- Settings -------------------------------------------------------

        function set.Diameter(obj, value)
            obj.Diameter = value;
            obj.onSettingChanged_('Diameter');
        end

        function set.Rate(obj, value)
            obj.Rate = value;
            obj.onSettingChanged_('Rate');
        end

        function set.Direction(obj, value)
            obj.Direction = value;
            obj.onSettingChanged_('Direction');
        end

        function set.RateUnits(obj, value)
            was = obj.RateUnits;
            obj.RateUnits = upper(value);
            obj.onRateUnitsChanged_(was);
        end

        function set.VolumeUnits(obj, value)
            obj.VolumeUnits = value;
            obj.onVolumeUnitsChanged_();
        end

        function set.TTLTrigger(obj, value)
            obj.TTLTrigger = value;
            obj.onSettingChanged_('TTLTrigger');
        end

        function set.TriggerMode(obj, value)
            obj.TriggerMode = upper(value);
            obj.onSettingChanged_('TriggerMode');
        end

        % --- Visibility ------------------------------------------------------

        function set.Sections(obj, value)
            obj.Sections = obj.normalizeSections_(value);
            obj.onSectionsChanged_();
        end

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
            % Hide one or more parts of the panel. Hidden controls keep their
            % state and their hardware bindings -- hiding the rate field does
            % not stop the panel writing obj.Rate to the pump.
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
            % Open the pump link on the selected port, replacing an existing
            % link when the selection changed. Held settings are pushed once
            % the pump answers.
            if isempty(obj.StagedPort_)
                obj.setStatus_('No port selected', obj.COLOR_ALARM);
                vprintf(0, 1, 'gui.SyringePump: choose a serial port before connecting')
                return
            end

            iface = obj.ensureInterface_();
            if obj.IsConnected
                if strcmpi(iface.Port, obj.StagedPort_)
                    return
                end
                iface.disconnect();
            end

            iface.Port = obj.StagedPort_;
            iface.AutoDetect = false;   % an explicit choice outranks probing

            obj.setStatus_(sprintf('Connecting to %s...', obj.StagedPort_), obj.COLOR_IDLE);
            drawnow limitrate

            try
                iface.connect();
            catch ME
                % A missing pump is an ordinary operator situation (wrong
                % port, cable out), so it reports in the panel rather than
                % throwing out of a button callback.
                vprintf(0, 1, ME)
                obj.setStatus_('Connect failed', obj.COLOR_ALARM);
                obj.updateLinkUI_();
                return
            end

            obj.applyRateUnits_();
            obj.applyToHardware_();
            obj.savePreferences_();
            obj.updateLinkUI_();
            obj.poll_();
        end

        function disconnect(obj)
            % disconnect(obj)
            % Stop the pump and close the link. Settings stay in the panel
            % and are pushed again on the next connect.
            if isempty(obj.Interface) || ~isvalid(obj.Interface), return; end
            try
                obj.Interface.disconnect();
            catch ME
                vprintf(0, 1, ME)
            end
            obj.updateLinkUI_();
        end

        function port = detectPort(obj)
            % port = detectPort(obj)
            % Probe the available serial ports for a pump that answers VER,
            % and select it. Returns '' when none answered.
            iface = obj.ensureInterface_();
            wasConnected = obj.IsConnected;
            if wasConnected
                iface.disconnect();
            end

            obj.setStatus_('Probing serial ports...', obj.COLOR_IDLE);
            drawnow limitrate

            port = hw.NE1000.findPumpPort(BaudRate = iface.BaudRate, ...
                Address = iface.Address, Timeout = iface.Timeout);

            if isempty(port)
                obj.setStatus_('No pump found', obj.COLOR_ALARM);
                vprintf(0, 1, 'gui.SyringePump: no NE-1000 answered on any available serial port')
                if wasConnected
                    obj.connect();
                end
                return
            end

            vprintf(1, 'gui.SyringePump: found a pump on %s', port)
            obj.selectPort_(port);
            obj.connect();
        end

        function refreshPorts(obj)
            % refreshPorts(obj)
            % Re-read the serial port list into the dropdown, keeping the
            % current selection when it is still present.
            if ~obj.hasControl_('port'), return; end
            [items, value] = obj.portItems_();
            obj.H_.port.Items = items;
            obj.H_.port.Value = value;
        end

        % --- Pump control ---------------------------------------------------

        function startPump(obj)
            % startPump(obj)
            % Run the pump (RUN). With the pump's Volume target set it
            % dispenses that volume and stops itself; with Volume 0 it runs
            % until stopPump.
            if ~obj.requireLink_(), return; end
            obj.Interface.trigger('Start');
            obj.poll_();
        end

        function stopPump(obj)
            % stopPump(obj)
            % Stop the pump (STP).
            if ~obj.requireLink_(), return; end
            obj.Interface.trigger('Stop');
            obj.poll_();
        end

        function zeroVolume(obj)
            % zeroVolume(obj)
            % Clear both dispensed-volume accumulators. The pump only
            % accepts this while stopped, so the pump is stopped first.
            if ~obj.requireLink_(), return; end
            obj.Interface.trigger('Stop');
            obj.Interface.trigger('ClearVolume');
            obj.poll_();
        end

        % --- Readout --------------------------------------------------------

        function refresh(obj)
            % refresh(obj)
            % Re-read every setting and reading from the pump into the panel.
            % The timer only polls the volumes and status; this also pulls
            % back diameter, rate, and direction (three more round trips),
            % which is what to call after something else has written them.
            obj.readFromHardware_();
            obj.poll_();
        end

        function startPolling(obj)
            % startPolling(obj) - Resume the volume readout timer.
            if ~isempty(obj.Timer) && isvalid(obj.Timer) && obj.Timer.Running == "off"
                start(obj.Timer);
            end
        end

        function stopPolling(obj)
            % stopPolling(obj) - Pause the volume readout timer.
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer);
            end
        end
    end


    methods (Access = protected)

        function c = popOutHostContainer_(obj)
            % Container this panel was built into (gui.PopOut).
            c = obj.Parent;
        end

        function h = createPopOut_(obj, container)
            % A second panel over the SAME pump, in its own window. It never
            % owns the interface, so closing it leaves the link alone; both
            % panels poll, so the pump answers two DIS queries per period.
            h = gui.SyringePump(obj.Interface, container, ...
                Diameter       = obj.Diameter, ...
                Rate           = obj.Rate, ...
                Direction      = obj.Direction, ...
                TTLTrigger     = obj.TTLTrigger, ...
                TriggerMode    = obj.TriggerMode, ...
                RateUnits      = obj.RateUnits, ...
                VolumeUnits    = obj.VolumeUnits, ...
                UpdatePeriod   = obj.UpdatePeriod, ...
                Port           = obj.StagedPort_, ...
                ApplyOnStart   = false, ...
                Sections       = obj.Sections, ...
                FontSize       = obj.FontSize_, ...
                PreferenceTag  = obj.popOutPreferenceTag_());
        end
    end


    methods (Access = private)

        % --- Interface resolution -------------------------------------------

        function resolveInterface_(obj, source)
            % Adopt the pump this panel drives: one handed in, the one a
            % runtime is using, or -- failing both -- an offline interface of
            % our own, so the panel still opens against a runtime with no
            % hardware (epsych.SelfTest check I6) and the operator can pick a
            % port from it.
            if isa(source, 'hw.NE1000') && isvalid(source)
                obj.Interface = source;
                obj.OwnsInterface_ = false;
                return
            end

            if ~isempty(source) && isobject(source) && isprop(source, 'Interfaces')
                try
                    I = source.Interfaces;
                    hit = arrayfun(@(x) isa(x, 'hw.NE1000'), I);
                    if any(hit)
                        found = I(hit);
                        obj.Interface = found(1);
                        obj.OwnsInterface_ = false;
                        return
                    end
                catch ME
                    vprintf(2, 'gui.SyringePump: could not search the runtime interfaces: %s', ME.message)
                end
            end

            if ~isempty(source) && ~isa(source, 'hw.NE1000') && ~isobject(source)
                vprintf(2, 'gui.SyringePump: unrecognized source; using a standalone interface')
            end

            obj.ensureInterface_();
        end

        function iface = ensureInterface_(obj)
            % The interface, constructing an offline one on first need.
            if ~isempty(obj.Interface) && isvalid(obj.Interface)
                iface = obj.Interface;
                return
            end
            iface = hw.NE1000('', Connect = false, RateUnits = obj.RateUnits);
            obj.Interface = iface;
            obj.OwnsInterface_ = true;
            vprintf(2, 'gui.SyringePump: no pump interface supplied; created a standalone one')
        end

        function seedSetting_(obj, name, value, default)
            % Assign one setting at construction, falling back to the
            % built-in default when the remembered value no longer validates
            % (a syringe diameter saved before the property's range changed,
            % a hand-edited preference).
            try
                obj.(name) = value;
            catch ME
                vprintf(1, ['gui.SyringePump: remembered %s is not usable (%s); ' ...
                    'falling back to the default'], name, ME.message)
                obj.(name) = default;
            end
        end

        function tf = requireLink_(obj)
            % Guard for the actions that need a live pump.
            tf = obj.IsConnected;
            if ~tf
                obj.setStatus_('Not connected', obj.COLOR_ALARM);
                vprintf(1, 'gui.SyringePump: no pump connected')
            end
        end

        % --- Hardware writes -------------------------------------------------

        function applyRateUnits_(obj)
            % Put the interface in the units this panel displays. Writing
            % 0.7 uL/min as 0.042 mL/hr would lose most of its precision to
            % the pump's 4-digit command grammar, so the panel changes the
            % units rather than converting -- and says so, since a protocol's
            % Rate column changes meaning with them.
            iface = obj.Interface;
            if isempty(iface) || ~isvalid(iface) || strcmp(iface.RateUnits, obj.RateUnits)
                return
            end

            vprintf(1, ['gui.SyringePump: switching %s rate units from %s to %s ' ...
                '(the panel displays %s); a protocol column that writes Rate ' ...
                'is now in those units too'], class(iface), iface.RateUnits, ...
                obj.RateUnits, obj.rateLabel_());
            iface.RateUnits = obj.RateUnits;

            % Keep the parameter's label honest for the trial table and any
            % monitor showing it; the units it was built with are now stale.
            try
                P = iface.find_parameter('Rate', silenceParameterNotFound = true);
                if ~isempty(P)
                    P(1).Unit = obj.rateLabel_();
                end
            catch ME
                vprintf(3, 'gui.SyringePump: could not relabel the Rate parameter: %s', ME.message)
            end
        end

        function applyToHardware_(obj)
            % Push the panel's settings to a connected pump, skipping any the
            % pump already agrees with. Skipping matters most for Diameter: a
            % diameter write resets the pump's dispensed-volume accumulators,
            % so a redundant one would silently zero the readout.
            if ~obj.IsConnected, return; end

            cur = obj.Interface.get_parameter('Diameter', includeInvisible = true);
            if isempty(cur) || abs(cur - obj.Diameter) > 5e-3
                obj.pushSetting_('Diameter', obj.Diameter, 'diameter');
            end

            cur = obj.Interface.get_parameter('Rate');
            if isempty(cur) || abs(cur - obj.Rate) > 1e-9
                obj.pushSetting_('Rate', obj.Rate, 'rate');
            end

            cur = obj.Interface.get_parameter('Direction', includeInvisible = true);
            if isempty(cur) || ~strcmpi(char(cur), obj.Direction)
                obj.pushSetting_('Direction', obj.Direction, 'direction');
            end

            % Read first: the read is what syncs the interface to the mode the
            % pump is actually in, so pushing the panel's mode afterwards is
            % what makes it win. Reversed, a pump already triggerable in
            % another mode would keep it, since the enable then needs no write.
            cur = obj.Interface.get_parameter('TTLTrigger', includeInvisible = true);
            obj.pushTriggerMode_();
            if isempty(cur) || logical(cur) ~= obj.TTLTrigger
                obj.pushSetting_('TTLTrigger', obj.TTLTrigger, 'ttl');
            end
        end

        function ok = pushSetting_(obj, wire, value, control)
            % Write one setting and flag the control when the pump refuses
            % it -- an out-of-range rate for the loaded syringe, or a change
            % attempted mid-dispense, both of which are rejections rather
            % than errors and would otherwise only reach the log.
            ok = true;
            if ~obj.IsConnected, return; end
            try
                ok = obj.Interface.set_parameter(wire, value);
            catch ME
                vprintf(0, 1, ME)
                ok = false;
            end
            obj.flagControl_(control, ~ok);
            if ~ok
                obj.setStatus_(sprintf('Pump rejected %s', lower(wire)), obj.COLOR_ALARM);
            end
        end

        function onSettingChanged_(obj, name)
            % Shared tail of the three property setters: move the control,
            % then write the pump unless we are the ones reading it.
            obj.updateControl_(name);
            if obj.Applying_, return; end
            if obj.FromUI_
                obj.rememberSetting_(name, obj.(name));
            end
            switch name
                case 'Diameter'
                    obj.pushSetting_('Diameter', obj.Diameter, 'diameter');
                case 'Rate'
                    obj.pushSetting_('Rate', obj.Rate, 'rate');
                case 'Direction'
                    obj.pushSetting_('Direction', obj.Direction, 'direction');
                    obj.updateReadoutLabels_();
                case 'TTLTrigger'
                    obj.pushSetting_('TTLTrigger', obj.TTLTrigger, 'ttl');
                case 'TriggerMode'
                    % Not a parameter: the mode belongs to the interface, and
                    % the pump only hears about it while the trigger is on.
                    obj.pushTriggerMode_();
            end
        end

        function onRateUnitsChanged_(obj, wasUnits)
            % Tail of the RateUnits setter. Units are how the rate is written
            % down, not how fast the pump runs, so the rate is converted with
            % them: an operator switching from uL/min to mL/min watches 500
            % become 0.5 and the syringe keeps moving at the same speed. The
            % interface follows, since the panel and the pump must agree on
            % what the number the trial table re-asserts means.
            if obj.Applying_ || strcmp(wasUnits, obj.RateUnits), return; end

            % The pump accepts a change of units only while it is stopped
            % (manual 10.4.1). Mid-run, hw.NE1000's RAT-with-units write is
            % rejected and falls back to the bare value -- which the pump
            % would take in its OLD units, changing how fast it is actually
            % running. So the change is refused outright rather than half
            % applied behind the operator.
            if obj.IsConnected && ismember(obj.Status, obj.RUNNING_STATES)
                vprintf(0, 1, ['gui.SyringePump: the pump is %s; stop it before ' ...
                    'changing the rate units'], lower(obj.Status))
                obj.setStatus_('Stop the pump to change units', obj.COLOR_ALARM);
                obj.Applying_ = true;
                obj.RateUnits = wasUnits;
                obj.Applying_ = false;
                return
            end

            obj.Applying_ = true;
            obj.Rate = gui.SyringePump.convertRate_(obj.Rate, wasUnits, obj.RateUnits);
            obj.Applying_ = false;

            obj.applyRateUnits_();      % the interface, and the Rate label
            obj.updateRateCaption_();
            obj.warnRateResolution_();
            obj.pushSetting_('Rate', obj.Rate, 'rate');

            if obj.FromUI_
                % The rate goes with them: a bare number remembered in one
                % unit and restored in another would change the pump's speed
                % a session later.
                obj.UserPrefs_.RateUnits = obj.RateUnits;
                obj.rememberSetting_('Rate', obj.Rate);
            end
        end

        function onVolumeUnitsChanged_(obj)
            % Tail of the VolumeUnits setter. Nothing is written to the pump:
            % the readout is scaled from whatever units the pump reports in,
            % so a fresh poll is all it takes.
            if obj.Applying_, return; end
            obj.poll_();
            obj.updateReadoutLabels_();
            if obj.FromUI_
                obj.rememberSetting_('VolumeUnits', obj.VolumeUnits);
            end
        end

        function warnRateResolution_(obj)
            % The pump's command grammar carries 4 digits and one decimal
            % point (hw.NE1000.formatFloat_), so the same rate is not
            % expressible in every unit: 0.7 uL/min asked for in mL/min goes
            % on the wire as 0.001 (a 43 % error), and 500 uL/min asked for
            % in uL/hr does not fit at all. Which units to use is the
            % operator's call, but not a silent one.
            if obj.Rate <= 0, return; end
            if obj.Rate >= 10000
                vprintf(0, 1, ['gui.SyringePump: %.6g %s is more than the pump can be ' ...
                    'told (its commands carry 4 digits); choose a coarser unit'], ...
                    obj.Rate, obj.rateLabel_())
            elseif obj.Rate < 0.01
                vprintf(0, 1, ['gui.SyringePump: %.4g %s is finer than the pump can be ' ...
                    'told (its commands carry 4 digits, so it resolves 0.001 %s); ' ...
                    'choose a finer unit to keep the rate exact'], ...
                    obj.Rate, obj.rateLabel_(), obj.rateLabel_())
            end
        end

        function pushTriggerMode_(obj)
            % Hand the mode to the interface, which writes it to a connected
            % pump. A mode the pump does not have is a programming error and
            % throws there; it reaches the panel through a property assignment
            % rather than a control, so it is logged rather than flagged.
            if isempty(obj.Interface) || ~isvalid(obj.Interface), return; end
            try
                obj.Interface.TriggerMode = obj.TriggerMode;
            catch ME
                vprintf(0, 1, ME)
            end
        end

        function readFromHardware_(obj)
            % Pull the pump's current settings into the panel without
            % writing anything back.
            if ~obj.IsConnected, return; end

            obj.Applying_ = true;
            try
                d = obj.Interface.get_parameter('Diameter', includeInvisible = true);
                if ~isempty(d) && isfinite(d) && d >= 0.1 && d <= 50
                    obj.Diameter = d;
                end

                r = obj.Interface.get_parameter('Rate');
                if ~isempty(r) && isfinite(r) && r >= 0
                    obj.Rate = r;
                end

                dir = obj.Interface.get_parameter('Direction', includeInvisible = true);
                if ~isempty(dir) && ismember(char(dir), {'Infuse','Withdraw'})
                    obj.Direction = char(dir);
                end

                % Reading the trigger also syncs the interface's TriggerMode
                % to what the pump reports, so the mode comes from there.
                ttl = obj.Interface.get_parameter('TTLTrigger', includeInvisible = true);
                if ~isempty(ttl) && (islogical(ttl) || isnumeric(ttl))
                    obj.TTLTrigger = logical(ttl);
                end
                obj.TriggerMode = obj.Interface.TriggerMode;
            catch ME
                vprintf(2, 'gui.SyringePump: reading the pump settings failed: %s', ME.message)
            end
            obj.Applying_ = false;

            obj.updateReadoutLabels_();
        end

        % --- Polling ---------------------------------------------------------

        function createTimer_(obj)
            tname = sprintf('SyringePump_Timer_%d', gui.SyringePump.nextInstanceId_());
            delete(timerfindall('Name', tname));
            obj.Timer = timer(Name = tname, ExecutionMode = 'fixedRate', ...
                Period = obj.UpdatePeriod, BusyMode = 'drop', ...
                TimerFcn = @(~,~) obj.timerTick_());

            % A panel showing neither the volume nor the status has nothing
            % to poll for, so it never starts asking the pump.
            if any(ismember(["Volume","Status"], obj.Sections))
                obj.poll_();
                start(obj.Timer);
            end
        end

        function timerTick_(obj)
            % An uncaught error in a TimerFcn stops the timer, and a syringe
            % pump on a long RS-232 run drops the odd reply.
            if ~isvalid(obj), return; end
            try
                obj.poll_();
            catch ME
                vprintf(2, 'gui.SyringePump: poll failed: %s', ME.message)
            end
        end

        function poll_(obj)
            % One readout pass: both accumulators (served by a single DIS
            % round trip through the interface's cache) plus the status
            % prompt. Nothing is drawn when the value has not changed.
            if ~isvalid(obj) || ~obj.hasControl_('value'), return; end

            if ~obj.IsConnected
                obj.VolumeInfused = NaN;
                obj.VolumeWithdrawn = NaN;
                obj.renderVolume_();
                obj.setStatus_('Disconnected', obj.COLOR_IDLE);
                return
            end

            vi = obj.Interface.get_parameter('VolumeInfused');
            vw = obj.Interface.get_parameter('VolumeWithdrawn');
            k  = obj.volumeScale_();
            obj.VolumeInfused   = obj.scalarOrNaN_(vi) * k;
            obj.VolumeWithdrawn = obj.scalarOrNaN_(vw) * k;
            obj.renderVolume_();

            s = obj.Interface.get_parameter('Status', includeInvisible = true);
            if isempty(s)
                s = 'No reply';
            end
            obj.Status = char(s);

            if startsWith(obj.Status, 'Alarm')
                color = obj.COLOR_ALARM;
            elseif ismember(obj.Status, obj.RUNNING_STATES)
                color = obj.COLOR_RUN;
            else
                color = obj.COLOR_IDLE;
            end
            obj.setStatus_(obj.Status, color);
        end

        function k = volumeScale_(obj)
            % Factor from the pump's reported volume units to the displayed
            % ones. The pump reports uL below a 14 mm diameter and mL at or
            % above; DispensedUnits is what it actually said last time, and
            % the diameter rule stands in before the first reply.
            reported = 'ML';
            try
                if ~isempty(obj.Interface.DispensedUnits)
                    reported = upper(obj.Interface.DispensedUnits);
                elseif obj.Diameter < 14
                    reported = 'UL';
                end
            catch
            end

            shown = obj.displayVolumeUnits_(reported);
            if strcmp(reported, 'ML') && strcmp(shown, 'uL')
                k = 1000;
            elseif strcmp(reported, 'UL') && strcmp(shown, 'mL')
                k = 1e-3;
            else
                k = 1;
            end
        end

        function u = displayVolumeUnits_(obj, reported)
            % Units the readout is labeled with.
            if strcmpi(obj.VolumeUnits, 'auto')
                if strcmpi(reported, 'UL')
                    u = 'uL';
                else
                    u = 'mL';
                end
            else
                u = obj.VolumeUnits;
            end
        end

        % --- UI ---------------------------------------------------------------

        function buildUI_(obj, container)
            % Every row is built whatever Sections says; applySectionVisibility_
            % collapses the ones that are off. Building the whole panel once
            % keeps toggling a section free of teardown, and keeps a hidden
            % control's value live for the code that still writes it.
            fs = obj.FontSize_;

            g = uigridlayout(container, [numel(obj.ROW_NAMES) 1]);
            g.RowHeight   = num2cell(obj.ROW_HEIGHTS);
            g.ColumnWidth = {'1x'};
            g.RowSpacing  = 4;
            g.Padding     = [6 6 6 6];
            g.Scrollable  = 'on';
            obj.H_.root = g;

            % --- Volume readout ------------------------------------------
            rg = uigridlayout(g, [2 1]);
            obj.Rows_.Volume = rg;
            rg.RowHeight   = {'1x', 16};
            rg.ColumnWidth = {'1x'};
            rg.RowSpacing  = 0;
            rg.Padding     = [0 0 0 0];
            obj.H_.value = uilabel(rg, Text = '--', FontSize = round(fs * 2.4), ...
                FontWeight = 'bold', HorizontalAlignment = 'center');
            obj.H_.caption = uilabel(rg, Text = '', FontSize = fs - 1, ...
                FontColor = obj.COLOR_IDLE, HorizontalAlignment = 'center');

            obj.H_.status = uilabel(g, Text = '', FontSize = fs - 1, ...
                FontColor = obj.COLOR_IDLE, HorizontalAlignment = 'center');
            obj.Rows_.Status = obj.H_.status;

            % --- Port ------------------------------------------------------
            pg = uigridlayout(g, [1 4]);
            pg.ColumnWidth = {'1x', 34, 60, 90};
            pg.RowHeight   = {'1x'};
            pg.ColumnSpacing = 4;
            pg.Padding     = [0 0 0 0];
            obj.Rows_.Port = pg;

            [items, value] = obj.portItems_();
            obj.H_.port = uidropdown(pg, Items = items, Value = value, ...
                FontSize = fs, Tooltip = 'Serial port the pump is attached to', ...
                ValueChangedFcn = @(src,~) obj.onPortPicked_(src.Value));
            obj.H_.ports = uibutton(pg, Text = 'Ports', FontSize = fs - 2, ...
                Tooltip = 'Re-read the list of serial ports', ...
                ButtonPushedFcn = @(~,~) obj.refreshPorts());
            obj.H_.detect = uibutton(pg, Text = 'Detect', FontSize = fs - 1, ...
                Tooltip = 'Probe every serial port for a pump', ...
                ButtonPushedFcn = @(~,~) obj.detectPort());
            obj.H_.connect = uibutton(pg, Text = 'Connect', FontSize = fs, ...
                ButtonPushedFcn = @(~,~) obj.onConnectPressed_());

            % --- Diameter / rate ------------------------------------------
            [obj.H_.diameter, obj.Rows_.Diameter] = obj.addNumericRow_(g, ...
                'Diameter (mm)', obj.Diameter, ...
                '%.2f', [0.1 50], @(v) obj.onEditChanged_('Diameter', v), ...
                'Inside diameter of the loaded syringe; the pump scales every rate and volume by it');
            % The rate label is kept: it carries the units, which the operator
            % can change from the menu at any time.
            [obj.H_.rate, obj.Rows_.Rate, obj.H_.rateCaption] = obj.addNumericRow_(g, ...
                sprintf('Rate (%s)', obj.rateLabel_()), ...
                obj.Rate, '%.4g', [0 Inf], @(v) obj.onEditChanged_('Rate', v), ...
                'Pumping rate; the usable range depends on the syringe diameter');

            % --- Direction --------------------------------------------------
            dg = uigridlayout(g, [1 2]);
            dg.ColumnWidth = {110, '1x'};
            dg.RowHeight   = {'1x'};
            dg.Padding     = [0 0 0 0];
            obj.Rows_.Direction = dg;
            uilabel(dg, Text = 'Direction', FontSize = fs);
            obj.H_.direction = uiswitch(dg, 'slider', Items = {'Infuse','Withdraw'}, ...
                Value = obj.Direction, FontSize = fs - 1, ...
                Tooltip = 'Infuse pushes the syringe; Withdraw pulls it back', ...
                ValueChangedFcn = @(src,~) obj.onEditChanged_('Direction', src.Value));

            % --- TTL trigger --------------------------------------------------
            tg = uigridlayout(g, [1 2]);
            tg.ColumnWidth = {110, '1x'};
            tg.RowHeight   = {'1x'};
            tg.Padding     = [0 0 0 0];
            obj.Rows_.TTL = tg;
            uilabel(tg, Text = 'TTL Trigger', FontSize = fs);
            obj.H_.ttl = uicheckbox(tg, Text = 'Enabled', Value = obj.TTLTrigger, ...
                FontSize = fs - 1, ...
                ValueChangedFcn = @(src,~) obj.onEditChanged_('TTLTrigger', src.Value));

            % --- Triggers ---------------------------------------------------
            bg = uigridlayout(g, [1 3]);
            bg.ColumnWidth = {'1x','1x','1x'};
            bg.RowHeight   = {'1x'};
            bg.ColumnSpacing = 4;
            bg.Padding     = [0 0 0 0];
            obj.Rows_.Triggers = bg;
            obj.H_.start = uibutton(bg, Text = 'Start', FontSize = fs, FontWeight = 'bold', ...
                Tooltip = 'Run the pump (stops itself once the pump''s volume target is met)', ...
                ButtonPushedFcn = @(~,~) obj.startPump());
            obj.H_.stop = uibutton(bg, Text = 'Stop', FontSize = fs, FontWeight = 'bold', ...
                ButtonPushedFcn = @(~,~) obj.stopPump());
            obj.H_.zero = uibutton(bg, Text = 'Zero', FontSize = fs, ...
                Tooltip = 'Clear the dispensed-volume accumulators', ...
                ButtonPushedFcn = @(~,~) obj.zeroVolume());

            obj.updateControl_('TTLTrigger');   % also builds its tooltip
            obj.updateReadoutLabels_();
            obj.createContextMenu_();
            obj.applySectionVisibility_();

            obj.DestroyListener_ = listener(g, 'ObjectBeingDestroyed', @(~,~) delete(obj));
        end

        function [h, row, lbl] = addNumericRow_(obj, parent, label, value, format, limits, fcn, tip)
            % One labeled numeric edit field; also returns the row container
            % so the section machinery can collapse it, and the label so a
            % caller whose units can change can relabel it.
            row = uigridlayout(parent, [1 2]);
            row.ColumnWidth = {110, '1x'};
            row.RowHeight   = {'1x'};
            row.Padding     = [0 0 0 0];
            lbl = uilabel(row, Text = label, FontSize = obj.FontSize_);
            h = uieditfield(row, 'numeric', Value = value, ...
                Limits = limits, LowerLimitInclusive = 'on', ...
                ValueDisplayFormat = format, FontSize = obj.FontSize_, ...
                Tooltip = tip, ValueChangedFcn = @(src,~) fcn(src.Value));
        end

        % --- Section visibility ------------------------------------------------

        function names = normalizeSections_(obj, value)
            % Expand aliases, drop duplicates, and keep the canonical layout
            % order so Sections always reads back the same way it is compared.
            % An unrecognized name is reported and skipped rather than thrown:
            % a typo in a build method must not stop the GUI from opening.
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
                    vprintf(1, ['gui.SyringePump: "%s" is not a section of this panel; ' ...
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
            % individual controls inside the two rows that hold several.
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

            % Port row: the dropdown, its refresh, and the connect button move
            % together as "Port"; probing is its own section.
            port   = ismember("Port", obj.Sections);
            detect = ismember("Detect", obj.Sections);
            obj.setItemVisible_('port',    port);
            obj.setItemVisible_('ports',   port);
            obj.setItemVisible_('connect', port);
            obj.setItemVisible_('detect',  detect);
            if obj.hasControl_('port')
                widths = {'1x', 34, 60, 90};
                if ~port
                    widths([1 2 4]) = {0};
                end
                if ~detect
                    widths{3} = 0;
                end
                obj.Rows_.Port.ColumnWidth = widths;
            end

            % Trigger row: one column per button, so a hidden one gives its
            % width to the others rather than leaving a gap.
            trig = ismember(["Start","Stop","Zero"], obj.Sections);
            obj.setItemVisible_('start', trig(1));
            obj.setItemVisible_('stop',  trig(2));
            obj.setItemVisible_('zero',  trig(3));
            if obj.hasControl_('start')
                widths = {'1x', '1x', '1x'};
                widths(~trig) = {0};
                obj.Rows_.Triggers.ColumnWidth = widths;
            end

            % Nothing to read out means nothing worth asking the pump for.
            if any(ismember(["Volume","Status"], obj.Sections))
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

        function updateControl_(obj, name)
            % Move one control to match its property, without re-entering
            % the callback that may have moved the property in the first place.
            switch name
                case 'Diameter'
                    if obj.hasControl_('diameter'), obj.H_.diameter.Value = obj.Diameter; end
                case 'Rate'
                    if obj.hasControl_('rate'), obj.H_.rate.Value = obj.Rate; end
                case 'Direction'
                    if obj.hasControl_('direction'), obj.H_.direction.Value = obj.Direction; end
                case {'TTLTrigger', 'TriggerMode'}
                    % The mode has no control of its own, so the checkbox's
                    % tooltip is where an operator finds out what the pump
                    % will do with pin 2.
                    if obj.hasControl_('ttl')
                        obj.H_.ttl.Value = obj.TTLTrigger;
                        obj.H_.ttl.Tooltip = sprintf( ...
                            'Let the pump''s TTL trigger input (pin 2) start and stop it -- %s', ...
                            obj.triggerModeLabel_());
                    end
            end
        end

        function s = triggerModeLabel_(obj)
            % What the interface's mode code means, for the tooltip and menu.
            i = find(strcmp(hw.NE1000.TRIGGER_MODES, obj.TriggerMode), 1);
            if isempty(i)
                s = obj.TriggerMode;
            else
                s = sprintf('%s (%s)', hw.NE1000.TRIGGER_LABELS{i}, obj.TriggerMode);
            end
        end

        function updateRateCaption_(obj)
            % The rate row's label carries the units, so it is rewritten
            % whenever they change.
            if ~obj.hasControl_('rateCaption'), return; end
            obj.H_.rateCaption.Text = sprintf('Rate (%s)', obj.rateLabel_());
        end

        function updateReadoutLabels_(obj)
            % The big number tracks the direction the pump is set to run,
            % which is the accumulator an operator is watching.
            if ~obj.hasControl_('caption'), return; end
            if strcmp(obj.Direction, 'Withdraw')
                word = 'Withdrawn';
            else
                word = 'Infused';
            end
            units = obj.displayVolumeUnits_(obj.reportedUnits_());
            obj.H_.caption.Text = sprintf('%s (%s)', word, units);
            obj.LastReadout_ = '';  % force the next render
            obj.renderVolume_();
        end

        function u = reportedUnits_(obj)
            u = 'ML';
            try
                if ~isempty(obj.Interface.DispensedUnits)
                    u = upper(obj.Interface.DispensedUnits);
                elseif obj.Diameter < 14
                    u = 'UL';
                end
            catch
            end
        end

        function renderVolume_(obj)
            if ~obj.hasControl_('value'), return; end
            if strcmp(obj.Direction, 'Withdraw')
                v = obj.VolumeWithdrawn;
            else
                v = obj.VolumeInfused;
            end
            s = gui.SyringePump.formatVolume_(v);
            if strcmp(s, obj.LastReadout_), return; end
            obj.H_.value.Text = s;
            obj.LastReadout_ = s;
        end

        function setStatus_(obj, text, color)
            if ~obj.hasControl_('status'), return; end
            if ~strcmp(obj.H_.status.Text, text)
                obj.H_.status.Text = text;
            end
            if ~isequal(obj.H_.status.FontColor, color)
                obj.H_.status.FontColor = color;
            end
        end

        function flagControl_(obj, control, rejected)
            % Tint a control whose last write the pump refused.
            if ~obj.hasControl_(control), return; end
            try
                if rejected
                    obj.H_.(control).BackgroundColor = obj.COLOR_REJECT;
                else
                    obj.H_.(control).BackgroundColor = 'white';
                end
            catch
                % A uiswitch has no BackgroundColor; the status line carries it.
            end
        end

        function updateLinkUI_(obj)
            % Connect button text follows what pressing it would do, and the
            % settings are disabled with no pump to send them to.
            if obj.hasControl_('connect')
                if ~obj.IsConnected
                    obj.H_.connect.Text = 'Connect';
                elseif strcmpi(obj.Interface.Port, obj.StagedPort_)
                    obj.H_.connect.Text = 'Disconnect';
                else
                    obj.H_.connect.Text = 'Reconnect';
                end
            end
            obj.refreshPorts();
            obj.updateReadoutLabels_();
        end

        function onConnectPressed_(obj)
            if obj.IsConnected && strcmpi(obj.Interface.Port, obj.StagedPort_)
                obj.disconnect();
            else
                obj.connect();
            end
        end

        function onPortPicked_(obj, value)
            obj.selectPort_(value);
        end

        function selectPort_(obj, port)
            port = char(port);
            if strcmp(port, '(none)')
                port = '';
            end
            obj.StagedPort_ = port;
            obj.rememberSetting_('Port', port);
            obj.refreshPorts();
            obj.updateLinkUI_();
        end

        function onEditChanged_(obj, name, value)
            % A control moved: assign through the property so programmatic
            % and manual changes take exactly the same path, flagged as the
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

        function [items, value] = portItems_(obj)
            % Every serial port the machine reports, plus the one already in
            % use (an open port is missing from the 'available' list) and the
            % staged selection, so a saved port survives the pump being off.
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
                if ~isempty(obj.Interface) && isvalid(obj.Interface) && ~isempty(obj.Interface.Port)
                    extra{end+1} = obj.Interface.Port;
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

        function r = initialRate_(obj, options, saved)
            % Rate to open with, expressed in this panel's units. A caller
            % states its rate in them already; a remembered one is a bare
            % number, so it is converted from the units that panel was
            % displaying -- what it saved alongside, else the ones this
            % caller states, else uL/min, which is what the panel displayed
            % before the units could be changed. Without this, an operator
            % who set 500 uL/min last session would get 500 mL/min today.
            r = gui.SyringePump.pick_(options, saved, 'Rate', 0.7, true);
            if isfield(options, 'Rate') || ~isfield(saved, 'Rate'), return; end

            was = 'UM';
            if isfield(saved, 'RateUnits')
                was = char(saved.RateUnits);
            elseif isfield(options, 'RateUnits')
                was = char(options.RateUnits);
            end
            r = gui.SyringePump.convertRate_(r, was, obj.RateUnits);
        end

        function port = initialPort_(obj, options, saved)
            % Port preselected at construction: the caller's, else the one
            % the interface is already configured for (a protocol saved it
            % with the pump, and it outranks this panel's memory), else the
            % one the operator last picked here.
            port = '';
            if isfield(options, 'Port')
                port = char(options.Port);
            end
            if ~isempty(port), return; end
            try
                if ~isempty(obj.Interface) && isvalid(obj.Interface)
                    port = char(obj.Interface.Port);
                end
            catch
            end
            if isempty(port) && isfield(saved, 'Port')
                port = char(saved.Port);
            end
        end

        % --- Context menu ------------------------------------------------------

        function createContextMenu_(obj)
            % Right-click menu. The two submenus are rebuilt every time the
            % menu opens: check marks track Sections, and the value entries
            % show what they would change, so every setting stays reachable
            % from here even when its row is hidden -- which is the point of
            % being able to hide it.
            f = ancestor(obj.Parent, 'figure');
            if isempty(f) || ~isvalid(f), return; end

            try
                cm = uicontextmenu(f);
                obj.ContextMenu = cm;
                obj.ShowMenuH_  = uimenu(cm, Text = 'Show');
                obj.ValueMenuH_ = uimenu(cm, Text = 'Set Value');
                obj.UnitsMenuH_ = uimenu(cm, Text = 'Units');
                uimenu(cm, Text = 'Refresh From Pump', Separator = 'on', ...
                    MenuSelectedFcn = @(~,~) obj.refresh());
                uimenu(cm, Text = 'Refresh Port List', ...
                    MenuSelectedFcn = @(~,~) obj.refreshPorts());
                uimenu(cm, Text = 'Zero Dispensed Volume', ...
                    MenuSelectedFcn = @(~,~) obj.zeroVolume());
                obj.addPopOutMenu_(cm);

                try
                    cm.ContextMenuOpeningFcn = @(~,~) obj.refreshMenus_();
                catch
                    cm.Callback = @(~,~) obj.refreshMenus_();
                end
            catch ME
                vprintf(3, 'gui.SyringePump: context menu unavailable: %s', ME.message)
                obj.ContextMenu = [];
                return
            end

            % Attached to everything clickable: with most sections hidden,
            % the readout or the bare panel may be all there is to aim at.
            targets = [{obj.H_.root}, struct2cell(obj.Rows_)', struct2cell(obj.H_)'];
            for k = 1:numel(targets)
                h = targets{k};
                if isempty(h) || ~isgraphics(h) || ~isvalid(h), continue; end
                try
                    h.ContextMenu = cm;
                catch ME
                    vprintf(3, 'gui.SyringePump: cannot attach context menu: %s', ME.message)
                end
            end
        end

        function refreshMenus_(obj)
            obj.refreshShowMenu_();
            obj.refreshValueMenu_();
            obj.refreshUnitsMenu_();
        end

        function refreshShowMenu_(obj)
            % One checkable entry per section, plus Show All and a reset to
            % whatever layout the hosting GUI asked for.
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

        function refreshValueMenu_(obj)
            % Every setting, labeled with its current value, so a hidden row
            % is still adjustable without unhiding it.
            m = obj.ValueMenuH_;
            if isempty(m) || ~isvalid(m), return; end
            delete(m.Children);

            uimenu(m, Text = sprintf('Diameter (%.2f mm)...', obj.Diameter), ...
                MenuSelectedFcn = @(~,~) obj.promptValue_('Diameter'));
            uimenu(m, Text = sprintf('Rate (%.4g %s)...', obj.Rate, obj.rateLabel_()), ...
                MenuSelectedFcn = @(~,~) obj.promptValue_('Rate'));

            dm = uimenu(m, Text = sprintf('Direction (%s)', obj.Direction));
            for d = {'Infuse', 'Withdraw'}
                item = uimenu(dm, Text = d{1}, ...
                    MenuSelectedFcn = @(~,~) obj.onEditChanged_('Direction', d{1}));
                item.Checked = strcmp(obj.Direction, d{1});
            end

            % The mode is not offered here -- only whether the trigger is
            % listened to at all, which is the operator's call.
            tm = uimenu(m, Text = sprintf('TTL Trigger (%s, %s)', ...
                gui.SyringePump.ttlLabel_(obj.TTLTrigger), obj.TriggerMode));
            for tf = [true false]
                item = uimenu(tm, Text = gui.SyringePump.ttlLabel_(tf), ...
                    MenuSelectedFcn = @(~,~) obj.onEditChanged_('TTLTrigger', tf));
                item.Checked = obj.TTLTrigger == tf;
            end

            label = obj.StagedPort_;
            if isempty(label), label = 'none'; end
            pm = uimenu(m, Text = sprintf('Port (%s)', label), Separator = 'on');
            items = obj.portItems_();
            for i = 1:numel(items)
                item = uimenu(pm, Text = items{i}, ...
                    MenuSelectedFcn = @(~,~) obj.selectPort_(items{i}));
                item.Checked = strcmp(items{i}, obj.StagedPort_);
            end
            uimenu(pm, Text = 'Detect...', Separator = 'on', ...
                MenuSelectedFcn = @(~,~) obj.detectPort());

            if obj.IsConnected
                uimenu(m, Text = 'Disconnect', MenuSelectedFcn = @(~,~) obj.disconnect());
            else
                uimenu(m, Text = 'Connect', ...
                    Enable = matlab.lang.OnOffSwitchState(~isempty(obj.StagedPort_)), ...
                    MenuSelectedFcn = @(~,~) obj.connect());
            end
        end

        function refreshUnitsMenu_(obj)
            % Which units the rate is written in and the volume is read in.
            % Both are one operator decision each -- microliters or
            % milliliters, per minute or per hour -- so they are offered as
            % the four combinations rather than as two coupled choices.
            m = obj.UnitsMenuH_;
            if isempty(m) || ~isvalid(m), return; end
            delete(m.Children);

            rm = uimenu(m, Text = sprintf('Rate (%s)', obj.rateLabel_()));
            for i = 1:numel(obj.RATE_CODES)
                code = obj.RATE_CODES{i};
                item = uimenu(rm, Text = obj.RATE_LABELS{i}, ...
                    MenuSelectedFcn = @(~,~) obj.setUnitsFromUI_('RateUnits', code));
                item.Checked = strcmp(obj.RateUnits, code);
            end

            vm = uimenu(m, Text = sprintf('Volume (%s)', obj.volumeUnitsLabel_()));
            for i = 1:numel(obj.VOLUME_CODES)
                code = obj.VOLUME_CODES{i};
                item = uimenu(vm, Text = obj.VOLUME_LABELS{i}, ...
                    MenuSelectedFcn = @(~,~) obj.setUnitsFromUI_('VolumeUnits', code));
                item.Checked = strcmp(obj.VolumeUnits, code);
            end
        end

        function s = volumeUnitsLabel_(obj)
            % What the readout is labeled with, saying so when that is the
            % pump's choice rather than the operator's.
            s = obj.VolumeUnits;
            if strcmpi(s, 'auto')
                s = sprintf('pump: %s', obj.displayVolumeUnits_(obj.reportedUnits_()));
            end
        end

        function setUnitsFromUI_(obj, name, value)
            % A units choice made in the menu, which is the kind that
            % persists. Assigning through the property keeps the operator's
            % path and a paradigm's identical, as onEditChanged_ does for
            % the values.
            obj.FromUI_ = true;
            try
                obj.(name) = value;
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
            % An operator's layout choice, which is the kind that persists.
            obj.FromUI_ = true;
            obj.Sections = sel;
            obj.FromUI_ = false;
        end

        function resetSections_(obj)
            % Back to the layout the hosting GUI asked for, and forget the
            % operator's -- otherwise the saved one would win again next time.
            obj.Sections = obj.DefaultSections_;
            obj.forgetPreferences_();
        end

        function promptValue_(obj, name)
            % Prompt for one numeric setting. inputdlg opens its own dialog,
            % so it works from a uifigure; a cancelled or unparseable entry
            % is ignored.
            switch name
                case 'Diameter'
                    prompt = 'Syringe inside diameter (mm), 0.1-50:';
                    dflt = sprintf('%.2f', obj.Diameter);
                otherwise
                    prompt = sprintf('Pumping rate (%s):', obj.rateLabel_());
                    dflt = sprintf('%.4g', obj.Rate);
            end

            try
                a = inputdlg({prompt}, sprintf('Set %s', name), [1 40], {dflt});
            catch ME
                vprintf(0, 1, 'gui.SyringePump: cannot prompt for %s: %s', name, ME.message)
                return
            end
            if isempty(a), return; end

            v = str2double(strtrim(a{1}));
            if ~isfinite(v)
                vprintf(0, 1, 'gui.SyringePump: "%s" is not a number', strtrim(a{1}))
                return
            end
            obj.onEditChanged_(name, v);
        end

        % --- Remembered configuration --------------------------------------------

        function s = loadPreferences_(obj)
            % What the operator configured in this panel last time: which
            % sections were shown, the port, and any value they set here.
            % Only ever holds what the operator changed through the panel --
            % a value a paradigm assigned is the paradigm's to reassert, not
            % something to resurrect a session later.
            s = struct();
            try
                pname = obj.preferenceName_();
                if ~ispref(obj.PREF_GROUP, pname), return; end
                s = getpref(obj.PREF_GROUP, pname);
                if ~isstruct(s), s = struct(); return; end
                vprintf(3, 'gui.SyringePump: loaded saved configuration "%s"', pname)
            catch ME
                vprintf(2, 'gui.SyringePump: failed to load preferences: %s', ME.message)
                s = struct();
            end
        end

        function rememberSetting_(obj, name, value)
            % Record one operator-made change and persist the lot.
            obj.UserPrefs_.(name) = value;
            obj.savePreferences_();
        end

        function savePreferences_(obj)
            try
                setpref(obj.PREF_GROUP, obj.preferenceName_(), obj.UserPrefs_);
            catch ME
                vprintf(2, 'gui.SyringePump: failed to save preferences: %s', ME.message)
            end
        end

        function forgetPreferences_(obj)
            % Drop the remembered layout, so the next session opens with the
            % layout its build method asked for.
            if isfield(obj.UserPrefs_, 'Sections')
                obj.UserPrefs_ = rmfield(obj.UserPrefs_, 'Sections');
            end
            obj.savePreferences_();
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

        function s = rateLabel_(obj)
            i = find(strcmp(obj.RATE_CODES, obj.RateUnits), 1);
            if isempty(i)
                s = obj.RateUnits;
            else
                s = obj.RATE_LABELS{i};
            end
        end

        function v = scalarOrNaN_(~, value)
            v = NaN;
            if isnumeric(value) && isscalar(value) && isfinite(value)
                v = double(value);
            end
        end
    end


    methods (Static, Access = private)

        function v = pick_(options, saved, name, default, useSaved)
            % Resolve one setting: what the caller asked for, else what the
            % operator left behind, else the built-in default. An option
            % declared with no default in the arguments block is simply
            % absent when it was not supplied, which is what makes the first
            % of those three distinguishable from the others.
            if isfield(options, name)
                v = options.(name);
            elseif useSaved && isfield(saved, name) && ~isempty(saved.(name))
                v = saved.(name);
            else
                v = default;
            end
        end

        function v = convertRate_(v, from, to)
            % The same physical rate, written in different units.
            if strcmpi(from, to), return; end
            v = double(v) * gui.SyringePump.rateFactor_(from) ...
                          / gui.SyringePump.rateFactor_(to);
        end

        function k = rateFactor_(code)
            % uL/min in one unit of a rate code. The code is <volume><time>:
            % U or M microliters or milliliters, M or H per minute or hour.
            code = upper(char(code));
            k = 1;
            if code(1) == 'M', k = k * 1000; end
            if code(2) == 'H', k = k / 60; end
        end

        function s = ttlLabel_(tf)
            % Operator-facing name for the two trigger states.
            if tf
                s = 'Enabled';
            else
                s = 'Disabled';
            end
        end

        function n = nextInstanceId_()
            persistent counter
            if isempty(counter), counter = 0; end
            counter = counter + 1;
            n = counter;
        end

        function s = formatVolume_(v)
            % Readout text, with enough decimals to see a single reward
            % arrive but not so many that the number jitters in width. The
            % pump reports three decimals, and in mL that is exactly what a
            % 1 uL step needs, so small values keep all three.
            if ~isfinite(v)
                s = '--';
            elseif abs(v) >= 1000
                s = sprintf('%.0f', v);
            elseif abs(v) >= 10
                s = sprintf('%.1f', v);
            elseif abs(v) >= 1
                s = sprintf('%.2f', v);
            else
                s = sprintf('%.3f', v);
            end
        end
    end
end
