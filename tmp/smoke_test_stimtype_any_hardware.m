function smoke_test_stimtype_any_hardware()
% smoke_test_stimtype_any_hardware()
% Exercise 'StimType' parameters on hardware-backed interfaces: the removed
% hw.Software-only restriction, the shared hw.Interface extraction helpers,
% the pass-through to set_parameter, and serialization round-trips on a
% non-Software parent.
%
% Every backend is constructed offline (Connect=false where the constructor
% offers it), so no hardware is required.
%
%   matlab -batch "run('tmp/smoke_test_stimtype_any_hardware.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

failures = {};

DEVICE_FS = 97656.25;   % a plausible TDT rate, distinct from any stimgen default

% ===== A. StimType is accepted on every interface =======================
try
    ifaces = localOfflineInterfaces_();
    for k = 1:numel(ifaces)
        iface = ifaces{k};
        p = hw.Parameter(iface, Name='Stim', Type='StimType');
        assert(strcmp(p.Type, 'StimType'), '%s: Type did not stick', class(iface));

        % Assigning Type after construction is the path set.Type's format
        % rule serves; the constructor writes options.Format afterwards, so
        % it is not the place to check it.
        q = hw.Parameter(iface, Name='Stim2');
        q.Type = 'StimType';
        assert(strcmp(q.Format, '%s'), '%s: StimType should format as %%s', class(iface));
    end
    fprintf('PASS: A. StimType accepted on %d interface types\n', numel(ifaces));
catch ME
    failures{end+1} = sprintf('A. type acceptance: %s', ME.message);
    fprintf('FAIL: A. %s\n', ME.message);
end

% ===== B. isStimulusValue recognizes the wire forms =====================
try
    t = stimgen.Tone(Fs=48000, Duration=0.05);
    assert(hw.Interface.isStimulusValue(t), 'bare stimulus not recognized');
    assert(hw.Interface.isStimulusValue({[t t]}), 'cell-wrapped array not recognized');
    assert(~hw.Interface.isStimulusValue(5), 'numeric misreported as stimulus');
    assert(~hw.Interface.isStimulusValue('Tone'), 'char misreported as stimulus');
    assert(~hw.Interface.isStimulusValue({1 2}), 'multi-cell misreported as stimulus');
    assert(~hw.Interface.isStimulusValue([]), 'empty misreported as stimulus');
    fprintf('PASS: B. isStimulusValue classifies wire forms\n');
catch ME
    failures{end+1} = sprintf('B. isStimulusValue: %s', ME.message);
    fprintf('FAIL: B. %s\n', ME.message);
end

% ===== C. stimulusPayload extracts and reconciles Fs ====================
try
    t = stimgen.Tone(Fs=48000, Duration=0.05, Frequency=4000);
    payload = hw.Interface.stimulusPayload(t);
    assert(isscalar(payload), 'expected one payload element');
    assert(payload.Fs == 48000, 'Fs should be untouched without a device rate');
    assert(~isempty(payload.Signal), ...
        'Signal is empty: stimulusPayload must generate it');
    assert(payload.N == numel(payload.Signal), ...
        'N (%d) should match the signal length (%d)', payload.N, numel(payload.Signal));
    assert(strcmp(payload.Class, 'stimgen.Tone'), 'Class field wrong: %s', payload.Class);

    % A device rate at or below hw.Module's 1 Hz "unset" default must not
    % regenerate the waveform.
    payload = hw.Interface.stimulusPayload(t, 1);
    assert(payload.Fs == 48000, 'unset module Fs (1 Hz) must not regenerate');

    % A real device rate regenerates at that rate.
    payload = hw.Interface.stimulusPayload(t, DEVICE_FS);
    assert(payload.Fs == DEVICE_FS, 'Fs not reconciled to the device rate');
    assert(t.Fs == DEVICE_FS, 'reconciliation should stick on the stimulus');
    assert(payload.N == round(DEVICE_FS * 0.05), ...
        'sample count %d does not match the device rate', payload.N);
    assert(numel(payload.Signal) == payload.N, 'signal not regenerated at device rate');

    % Arrays yield one element per stimulus.
    pair = hw.Interface.stimulusPayload([stimgen.Tone(), stimgen.Noise()]);
    assert(numel(pair) == 2, 'expected two payload elements, got %d', numel(pair));

    assert(isempty(hw.Interface.stimulusPayload(stimgen.Tone.empty(1,0))), ...
        'empty stimulus should give an empty payload');

    fprintf('PASS: C. stimulusPayload extracts and reconciles Fs\n');
catch ME
    failures{end+1} = sprintf('C. stimulusPayload: %s', ME.message);
    fprintf('FAIL: C. %s\n', ME.message);
end

% ===== D. set.Value reaches set_parameter on every backend ==============
% Offline backends are no-ops on the wire, so this asserts that the write
% path completes rather than throwing on an object it cannot coerce.
try
    ifaces = localOfflineInterfaces_();
    for k = 1:numel(ifaces)
        iface = ifaces{k};
        m = localEnsureModule_(iface);
        p = m.add_parameter('Stim', stimgen.Tone(Duration=0.02));
        p.Value = stimgen.Tone(Duration=0.02, Frequency=8000);
        assert(isa(p.Value, 'stimgen.Tone'), ...
            '%s: stimulus did not survive the write', class(iface));
        p.Value = [];   % an unset StimType must not throw either
    end
    fprintf('PASS: D. set.Value dispatches to %d backends without error\n', numel(ifaces));
catch ME
    failures{end+1} = sprintf('D. set_parameter dispatch: %s', ME.message);
    fprintf('FAIL: D. %s\n', ME.message);
end

% ===== E. Values / index Expression still work off Software =============
try
    [~, m] = localOfflineRPcox_(DEVICE_FS);
    p = m.add_parameter('Stim', stimgen.Tone(Duration=0.02));
    p.Values = {stimgen.Tone(Frequency=1000), stimgen.Tone(Frequency=2000), ...
        stimgen.Noise()};
    p.Expression = "2";
    p.Value = 1;   % discarded; the expression picks the item
    assert(p.Value.Frequency == 2000, 'index expression selected the wrong item');

    p.Expression = "4";
    localExpectError_(@() setValue_(p, 1), 'hw:Parameter:IndexExpressionOutOfRange', ...
        'out-of-range index');

    fprintf('PASS: E. index Expression works on a hardware parent\n');
catch ME
    failures{end+1} = sprintf('E. index expression: %s', ME.message);
    fprintf('FAIL: E. %s\n', ME.message);
end

% ===== F. Non-stimulus values still rejected ============================
try
    iface = hw.TDT_RPcox();
    p = hw.Parameter(iface, Name='Stim', Type='StimType');
    localExpectError_(@() setValue_(p, 42), 'hw:Parameter:InvalidStimTypeValue', ...
        'bare number without an Expression');
    fprintf('PASS: F. StimType still rejects non-stimulus values\n');
catch ME
    failures{end+1} = sprintf('F. value validation: %s', ME.message);
    fprintf('FAIL: F. %s\n', ME.message);
end

% ===== G. Serialization round-trips on a hardware parent ================
try
    [~, m] = localOfflineRPcox_(DEVICE_FS);
    p = m.add_parameter('Stim', stimgen.Tone(Duration=0.03, Frequency=3000));
    p.Value = stimgen.Tone(Duration=0.03, Frequency=3000);
    S = p.toStruct();

    [~, targetModule] = localOfflineRPcox_(DEVICE_FS);
    q = hw.Parameter(targetModule.parent, Name='Placeholder');
    q.Module = targetModule;
    q.fromStruct(S);

    assert(strcmp(q.Type, 'StimType'), 'Type did not round-trip: %s', q.Type);
    assert(isa(q.Value, 'stimgen.Tone'), ...
        'Value did not round-trip as a stimulus (got %s)', class(q.Value));
    assert(q.Value.Frequency == 3000, 'stimulus properties did not round-trip');
    assert(isa(q.Values{1}, 'stimgen.Tone'), 'design-time Values did not round-trip');

    fprintf('PASS: G. StimType serialization round-trips on a hardware parent\n');
catch ME
    failures{end+1} = sprintf('G. serialization: %s', ME.message);
    fprintf('FAIL: G. %s\n', ME.message);
end

% ===== H. A stimulus is written to its RPvds tag ========================
% TDTRP is unavailable offline, so this asserts the extraction the backend
% performs rather than the ActiveX write: the waveform handed to the tag is
% the one generated at the module's own rate.
try
    [~, m] = localOfflineRPcox_(DEVICE_FS);
    stim = stimgen.Tone(Fs=48000, Duration=0.04, Frequency=2000);
    p = m.add_parameter('Stim', stim);
    p.Value = stim;

    payload = hw.Interface.stimulusPayload(p.Value, m.Fs);
    assert(payload.Fs == m.Fs, 'payload not aligned to the module rate');
    assert(numel(payload.Signal) == round(m.Fs * 0.04), ...
        'waveform length %d does not match the module rate', numel(payload.Signal));
    assert(isrow(payload.Signal), 'RPvds expects a row vector of samples');
    assert(all(isfinite(payload.Signal)), 'waveform contains non-finite samples');

    fprintf('PASS: H. stimulus resolves to a device-rate waveform (%d samples @ %g Hz)\n', ...
        numel(payload.Signal), payload.Fs);
catch ME
    failures{end+1} = sprintf('H. waveform extraction: %s', ME.message);
    fprintf('FAIL: H. %s\n', ME.message);
end

% ===== I. A connected backend reads the stimulus host-side ==============
% hw.VlcRecorder connects without launching anything, so it is the one
% backend that can be IsConnected in a headless test. Its get_parameter
% knows nothing about a 'Stim' tag, which is the point: a device read must
% not be what a 'StimType' parameter returns.
try
    iface = hw.VlcRecorder();
    iface.connect();   % rebuilds Module, so add parameters afterwards
    assert(iface.IsConnected, 'VlcRecorder should connect offline');

    m = iface.Module(1);
    stim = stimgen.Tone(Duration=0.02, Frequency=6000);
    p = m.add_parameter('Stim', stim);
    p.Value = stim;

    assert(isa(p.Value, 'stimgen.Tone'), ...
        'connected backend returned %s instead of the stimulus', class(p.Value));
    assert(p.Value.Frequency == 6000, 'stimulus read back with wrong properties');

    % A non-StimType parameter on the same connected interface must still
    % delegate its read to the backend.
    q = m.add_parameter('FrameRate', 30);
    q.Value = 30;
    assert(isequal(q.Value, 30), 'numeric read should still come from the backend');

    fprintf('PASS: I. connected backend reads the stimulus host-side\n');
catch ME
    failures{end+1} = sprintf('I. connected read: %s', ME.message);
    fprintf('FAIL: I. %s\n', ME.message);
end

% ===== Summary ==========================================================
fprintf('\n');
if isempty(failures)
    fprintf('ALL PASS\n');
else
    fprintf('%d FAILURE(S):\n', numel(failures));
    fprintf('  %s\n', failures{:});
end

end


% ------------------------------------------------------------------------
function ifaces = localOfflineInterfaces_()
% One instance of each backend, constructed without touching hardware.
ifaces = { ...
    hw.Software(), ...
    hw.TDT_RPcox(), ...
    hw.TDT_Synapse(Connect=false), ...
    hw.Teensy(Connect=false), ...
    hw.Intan_RHX(Connect=false), ...
    hw.VlcRecorder()};
end


% ------------------------------------------------------------------------
function m = localEnsureModule_(iface)
% Return the interface's first module, installing one when the backend
% builds its modules at connect time.
if ~isempty(iface.Module)
    m = iface.Module(1);
    return
end

m = hw.Module(iface, 'M1', 'M1', uint8(1));
if ismethod(iface, 'setModules')
    iface.setModules(m);
elseif ismethod(iface, 'set_module')
    iface.set_module(m);
end
end


% ------------------------------------------------------------------------
function [iface, m] = localOfflineRPcox_(deviceFs)
% An offline TDT_RPcox carrying one module at a known device rate, which
% connect() would otherwise read from the hardware.
iface = hw.TDT_RPcox();
m = hw.Module(iface, 'RZ6', 'RZ6', uint8(1));
m.Fs = deviceFs;
iface.setModules(m);
end


% ------------------------------------------------------------------------
function setValue_(p, v)
p.Value = v;
end


% ------------------------------------------------------------------------
function localExpectError_(fcn, expectedID, label)
try
    fcn();
    error('smoke:NoError', '%s should have raised %s', label, expectedID);
catch ME
    if strcmp(ME.identifier, 'smoke:NoError')
        rethrow(ME);
    end
    assert(strcmp(ME.identifier, expectedID), ...
        '%s raised %s, expected %s', label, ME.identifier, expectedID);
end
end
