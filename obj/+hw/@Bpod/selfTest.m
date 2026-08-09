function results = selfTest(obj, options)
% results = selfTest(obj)
% results = selfTest(obj, Invasive=true)
% Pre-flight diagnostics for epsych.SelfTest. Never throws.
%
% The non-invasive pass issues ZERO transport calls: it reports on the
% interface's configuration only. That is not merely polite. epsych.SelfTest can
% be run from RunExpt's Help menu while a session is live, and after 'R' the
% Bpod is a push stream with no CRC, sequence number, or resync marker — a
% single stray probe byte would either be parsed as an opcode by the firmware or
% would answer with a bare unframed byte that the host parser reads as the start
% of an event message. Both silently corrupt the trial.
%
% For the same reason nothing here reads obj.mode: its getter drives the byte
% pump. Property reads used below (IsConnected, FirmwareBuild, Module) touch no
% transport.
%
% Parameters:
%   obj              - hw.Bpod instance.
%   options.Invasive - When false (default) make no hardware calls at all. When
%                      true the handshake may be exercised, restoring the
%                      connection state it found.
%
% Returns:
%   results - 1xN struct array built by hw.Interface.selfTestResult.
%
% See also: hw.Interface.selfTest, hw.Interface.selfTestResult, epsych.SelfTest,
%           documentation/hw/hw_Bpod.md

arguments
    obj
    options.Invasive (1,1) logical = false
end

results = hw.Interface.selfTestResult();

% Configuration checks are pure property reads, but a self-test that throws
% would take down the whole diagnostics window, so even these are guarded.
try
    results = local_configChecks(obj, results);
catch ME
    results(end + 1) = hw.Interface.selfTestResult('Bpod Configuration', 'fail', ...
        'Configuration checks raised an error.', ...
        Detail = ME.message, ...
        Remedy = 'Re-create the interface from ProtocolDesigner and retry.');
end

if ~options.Invasive
    results(end + 1) = hw.Interface.selfTestResult('Bpod Handshake', 'skip', ...
        'Firmware handshake requires an invasive test.');
    return
end

results = local_handshakeCheck(obj, results);

end


% ------------------------------------------------------------------------
function results = local_configChecks(obj, results)
% results = local_configChecks(obj, results)
% Append the checks that need no hardware. obj is a handle; results is a value
% array, so it is passed and returned.

% --- Port ---------------------------------------------------------------
% The available-port list is deliberately NOT enumerated here. serialportlist
% can block for seconds while Windows walks the driver stack, this runs on the
% pre-flight path, and a port that exists proves nothing about the board being
% a Bpod. The invasive pass settles that question properly.
if obj.IsConnected
    results(end + 1) = hw.Interface.selfTestResult('Bpod Port', 'pass', ...
        sprintf('Connected on %s.', obj.Port));
elseif ~isempty(obj.Port)
    results(end + 1) = hw.Interface.selfTestResult('Bpod Port', 'pass', ...
        sprintf('Port %s is configured.', obj.Port), ...
        Detail = 'Whether a Bpod actually answers there is only checked by the invasive test.');
elseif obj.AutoDetect
    results(end + 1) = hw.Interface.selfTestResult('Bpod Port', 'info', ...
        'No port configured; Auto-detect will probe available ports at connect.');
else
    results(end + 1) = hw.Interface.selfTestResult('Bpod Port', 'fail', ...
        'No serial port is configured and Auto-detect is off.', ...
        Remedy = 'Set the Serial Port option in ProtocolDesigner, or enable Auto-detect.');
end

% --- Box ID -------------------------------------------------------------
% Only the constructor validates BoxID; the property itself accepts any double,
% so a value assigned after construction can still be nonsense. A bad box
% number does not fail loudly at runtime, it just names parameters nobody reads.
boxID = obj.BoxID;
if isfinite(boxID) && boxID > 0 && boxID == floor(boxID)
    results(end + 1) = hw.Interface.selfTestResult('Bpod Box ID', 'pass', ...
        sprintf('Serving box %d.', boxID), ...
        Detail = sprintf('Per-box parameters are named x_NewTrial_%d, x_TrialComplete_%d, ...', ...
            boxID, boxID));
else
    results(end + 1) = hw.Interface.selfTestResult('Bpod Box ID', 'fail', ...
        sprintf('Box ID %g is not a positive integer.', boxID), ...
        Remedy = 'Set Box ID to a positive whole number in ProtocolDesigner.');
end

% --- State matrix builder ----------------------------------------------
if isempty(obj.StateMatrixFcn)
    results(end + 1) = hw.Interface.selfTestResult('Bpod State Matrix Builder', 'info', ...
        'No builder configured; the interface runs in immediate I/O mode.', ...
        Detail = 'MATLAB times the trial and drives outputs directly, at timer-tick resolution.');
else
    % exist(...,'file') resolves a function file on the MATLAB path, which is
    % what StateMatrixFcn must be: it is invoked by name, so a full path to a
    % file in an unadded folder would resolve here and still fail at feval.
    found = false;
    try
        found = exist(obj.StateMatrixFcn, 'file') ~= 0;
    catch ME
        vprintf(2, 'Bpod: resolving state matrix builder "%s" failed: %s', ...
            obj.StateMatrixFcn, ME.message);
    end

    if found
        results(end + 1) = hw.Interface.selfTestResult('Bpod State Matrix Builder', 'pass', ...
            sprintf('Builder "%s" resolves on the MATLAB path.', obj.StateMatrixFcn));
    else
        results(end + 1) = hw.Interface.selfTestResult('Bpod State Matrix Builder', 'fail', ...
            sprintf('Builder "%s" was not found on the MATLAB path.', obj.StateMatrixFcn), ...
            Detail = 'Expected a function file with the signature sma = f(iface, P).', ...
            Remedy = 'Add the builder''s folder to the MATLAB path, or correct the State Matrix Builder option.');
    end
end

% --- Module and parameter table ----------------------------------------
% Counted straight off the modules rather than through all_parameters so an
% interface with no modules at all cannot throw on the way to a fail result.
nModules = numel(obj.Module);
nParams = 0;
for i = 1:nModules
    nParams = nParams + numel(obj.Module(i).Parameters);
end

if nModules == 0
    results(end + 1) = hw.Interface.selfTestResult('Bpod Parameter Table', 'fail', ...
        'The interface has no module, so it exposes no parameters.', ...
        Remedy = 'Connect the interface once, or use Read HW Params in ProtocolDesigner, to build the table.');
elseif nParams == 0
    results(end + 1) = hw.Interface.selfTestResult('Bpod Parameter Table', 'fail', ...
        sprintf('Module "%s" holds no parameters.', obj.Module(1).Name), ...
        Remedy = 'Use Read HW Params in ProtocolDesigner to repopulate the Bpod parameter table.');
else
    results(end + 1) = hw.Interface.selfTestResult('Bpod Parameter Table', 'pass', ...
        sprintf('%d parameter(s) across %d module(s).', nParams, nModules));
end

% --- One box per device -------------------------------------------------
% Informational rather than a failure: the interface cannot see the session's
% subject count from here. prepareRecording turns this into a hard error when a
% multi-subject session actually starts.
results(end + 1) = hw.Interface.selfTestResult('Bpod Box Limit', 'info', ...
    'One Bpod serves exactly one subject box.', ...
    Detail = ['The device has a single state machine and a single run opcode. A session ' ...
        'with more than one subject would have the second subject''s trial overwrite the ' ...
        'first''s in flight, so hw.Bpod refuses to start one.']);

end


% ------------------------------------------------------------------------
function results = local_handshakeCheck(obj, results)
% results = local_handshakeCheck(obj, results)
% Invasive check: prove the firmware handshake and report its build number.
%
% connect() is the handshake — it writes '6', requires the reply byte, then
% reads the build with 'F'. Reaching IsConnected therefore IS the proof, and
% re-issuing '6' against an already-open link would only risk desynchronizing a
% stream that may already be carrying a trial.

wasConnected = obj.IsConnected;

try
    if ~wasConnected
        obj.connect();
    end

    if ~obj.IsConnected
        results(end + 1) = hw.Interface.selfTestResult('Bpod Handshake', 'fail', ...
            'Could not open a connection to the state machine.', ...
            Remedy = 'Check the USB cable and port, close any serial terminal holding it, and re-flash Bpod_MainModule_0_6 if needed.');
    elseif obj.FirmwareBuild < 6
        % Builds below 6 report event timestamps on a different scale, so the
        % trial record would be silently mis-scaled rather than obviously wrong.
        results(end + 1) = hw.Interface.selfTestResult('Bpod Handshake', 'warn', ...
            sprintf('Handshake succeeded, but firmware build %g is below 6.', obj.FirmwareBuild), ...
            Detail = 'Event timestamps use a different scale factor before build 6, so recorded times would be wrong.', ...
            Remedy = 'Flash Firmware/Bpod_MainModule_0_6 onto the main module.');
    else
        results(end + 1) = hw.Interface.selfTestResult('Bpod Handshake', 'pass', ...
            sprintf('Handshake succeeded on %s (firmware build %g).', obj.Port, obj.FirmwareBuild));
    end
catch ME
    results(end + 1) = hw.Interface.selfTestResult('Bpod Handshake', 'fail', ...
        'The handshake raised an error.', ...
        Detail = ME.message, ...
        Remedy = 'Close any serial terminal holding the port, confirm the board is powered, then retry.');
end

% Restore the connection state we found, whatever happened above.
try
    if ~wasConnected && obj.IsConnected
        obj.disconnect();
    end
catch ME
    vprintf(0, 1, ME);
end

end
