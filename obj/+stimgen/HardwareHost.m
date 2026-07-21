classdef (Abstract) HardwareHost < handle
    % stimgen.HardwareHost
    %
    % Abstract contract that lets stimgen GUIs drive experiment hardware
    % without naming any host-application type.
    %
    % stimgen deliberately knows nothing about how protocols are stored or
    % how hardware is addressed. A host application (e.g. EPsych) supplies a
    % concrete subclass that wraps its own runtime and protocol objects; the
    % stimgen GUIs talk only to this interface. Passing no host leaves the
    % GUIs in offline mode, where speaker preview still works but hardware
    % playback is disabled.
    %
    % This mirrors the seam already used by stimgen.calibration.Engine,
    % which depends only on the abstract stimgen.calibration.HwAdapter.
    %
    % Methods:
    %   loadProtocol    - Load a protocol object or file; throws on failure
    %   hasProtocol     - True when a protocol is loaded
    %   protocolName    - Short display name for the loaded protocol
    %   connect         - Connect all hardware interfaces
    %   release         - Drop interfaces and clear runtime state
    %   setMode         - Set device mode ("Preview" or "Idle")
    %   findParameter   - Resolve a named parameter handle, or [] if absent
    %   connectionState - "None" | "NotConnected" | "Partial" | "Ready"
    %
    % Example:
    %   % Host application supplies the concrete implementation:
    %   player = stimgen.StimPlayer(stimbridge.RuntimeHost('my.eprot'));
    %
    %   % Offline: speaker preview only, no host required:
    %   player = stimgen.StimPlayer();
    %
    % See also: stimgen.StimPlayer, stimgen.calibration.CalibrationGui,
    %           stimgen.calibration.HwAdapter

    methods (Abstract)
        % loadProtocol(obj, protocolInput)
        % Load a protocol from a host-defined protocol object or a filepath.
        % Throws an MException if the protocol cannot be loaded; stimgen
        % catches and reports it through the GUI.
        loadProtocol(obj, protocolInput)

        % tf = hasProtocol(obj)
        % Return true when a protocol is currently loaded.
        tf = hasProtocol(obj)

        % name = protocolName(obj)
        % Return a short (1,1) string naming the loaded protocol, for
        % display in status text. Return "" when no protocol is loaded.
        name = protocolName(obj)

        % connect(obj)
        % Connect every hardware interface defined by the loaded protocol.
        % Throws if an interface fails to connect.
        connect(obj)

        % release(obj)
        % Release hardware interfaces and clear runtime state. Must be safe
        % to call when nothing is connected.
        release(obj)

        % setMode(obj, modeName)
        % Set the device mode for all interfaces.
        %
        % Parameters:
        %   modeName - "Preview" or "Idle"
        setMode(obj, modeName)

        % p = findParameter(obj, name)
        % Resolve a named hardware parameter.
        %
        % Returns:
        %   p - Handle exposing a gettable/settable .Value property, or []
        %       when no such parameter exists. Must not error when absent.
        p = findParameter(obj, name)

        % state = connectionState(obj)
        % Report hardware connection state as a (1,1) string:
        %   "None"         - no runtime/interfaces present
        %   "NotConnected" - interfaces present but none connected
        %   "Partial"      - some interfaces connected
        %   "Ready"        - all interfaces connected
        state = connectionState(obj)

        % adapter = calibrationAdapter(obj)
        % Build a calibration adapter for the connected hardware. Selecting
        % which interface can drive calibration is host-specific, so the
        % host owns that decision.
        %
        % Returns:
        %   adapter - stimgen.calibration.HwAdapter subclass instance
        %
        % Throws if no connected interface can be adapted.
        adapter = calibrationAdapter(obj)
    end
end
