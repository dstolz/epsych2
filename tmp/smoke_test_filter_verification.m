function smoke_test_filter_verification
% Headless smoke test for Engine.test_filter and the CalibrationGui
% Test Filter button, against the FakeSpeakerAdapter simulated rig.
% The button always runs the sweep flatness test (Engine.test_filter),
% regardless of whether the filter was designed from tones or the swept sine.
%
%   matlab -batch "run('tmp/smoke_test_filter_verification.m')"

repoRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repoRoot, 'obj', 'stimgen'));
addpath(fileparts(mfilename('fullpath')));

global GVerbosity %#ok<GVMIS>
GVerbosity = 1;

%% 1. Lint the touched files
sg = fullfile(repoRoot, 'obj', 'stimgen', '+stimgen');
files = { ...
    fullfile(sg, '+calibration', '@Engine', 'test_filter.m'), ...
    fullfile(sg, '+calibration', '@Engine', 'Engine.m'), ...
    fullfile(sg, '+calibration', '@LiveMonitor', 'LiveMonitor.m'), ...
    fullfile(sg, '@StimCalibration', 'StimCalibration.m'), ...
    fullfile(sg, '+calibration', 'CalibrationGui.m')};
for k = 1:numel(files)
    msgs = checkcode(files{k}, '-severity');
    err = msgs([msgs.severity] >= 2);
    if ~isempty(err)
        for m = err(:)'
            fprintf(2, '%s:%d %s\n', files{k}, m.line, m.message);
        end
        error('smoke:lint', 'checkcode errors in %s', files{k});
    end
end
fprintf('PASS lint\n');

%% 2. Engine.test_filter end-to-end against a simulated speaker
adapter = FakeSpeakerAdapter(44100);
eng = stimgen.calibration.Engine(adapter);
eng.set_configuration(MicSensitivity=0.01, ExcitationVoltage=1);

% Guard: no filter yet -> must raise the friendly error
try
    eng.test_filter();
    error('smoke:noFilterGuard', 'test_filter did not refuse without a filter');
catch ME
    assert(strcmp(ME.identifier, 'stimgen:calibration:Engine:noFilter'), ...
        'unexpected error: %s / %s', ME.identifier, ME.message);
end
fprintf('PASS no-filter guard\n');

% Calibrate broadband, design, then test
eng.calibrate_swept_sine(0.5, [], 1);
eng.design_filter("swept_sine", ShowResponse=false, SmoothingOctaves=1/6);
r = eng.test_filter(Duration=0.5, RepeatCount=1);

fprintf('band %g-%g Hz | ripple %.2f -> %.2f dB | std %.3f -> %.3f dB | passed=%d\n', ...
    r.band(1), r.band(2), r.unfiltered.ripple_db, r.filtered.ripple_db, ...
    r.unfiltered.flatness_std_db, r.filtered.flatness_std_db, r.passed);

assert(r.filtered.ripple_db < r.unfiltered.ripple_db, ...
    'filter did not flatten the simulated response');
assert(isfield(eng.CalibrationData, 'filterTest'), 'filterTest not stored');
assert(r.passed == (r.filtered.ripple_db <= r.ripple_tolerance_db));
fprintf('PASS engine test_filter\n');

%% 3. StimCalibration proxies test_filter without owning a GUI
sc = stimgen.StimCalibration(adapter);
sc.Engine.restore(struct( ...
    'CalibrationData',      eng.CalibrationData, ...
    'MicSensitivity',       eng.MicSensitivity, ...
    'NormativeValue',       eng.NormativeValue, ...
    'ReferenceLevel',       eng.ReferenceLevel, ...
    'ReferenceFrequency',   eng.ReferenceFrequency, ...
    'ExcitationVoltage',    eng.ExcitationVoltage, ...
    'CalibrationTimestamp', eng.CalibrationTimestamp));

r2 = sc.test_filter(Duration=0.5, RepeatCount=1);
assert(isstruct(r2) && isfield(r2, 'passed'), 'proxy did not return a result');
assert(isfield(sc.Engine.CalibrationData, 'filterTest'), 'proxy run did not store filterTest');
assert(~ismethod(sc, 'gui'), 'StimCalibration still exposes a gui method');
delete(sc);
fprintf('PASS StimCalibration proxy\n');

%% 4. Tone-designed filter also gets the sweep flatness test
engTone = stimgen.calibration.Engine(FakeSpeakerAdapter(44100));
engTone.set_configuration(MicSensitivity=0.01, ExcitationVoltage=1);
engTone.calibrate_tones([1000 2000 4000 8000], 1);
engTone.design_filter("tone", ShowResponse=false);
assert(engTone.CalibrationData.filterSource == "tone");
rTone = engTone.test_filter(Duration=0.5, RepeatCount=1);
assert(isfield(engTone.CalibrationData, 'filterTest'), 'filterTest not stored for a tone-designed filter');
assert(isfield(rTone, 'passed'), 'filter test returned no verdict for a tone-designed filter');
fprintf('PASS tone-designed filter via test_filter\n');

%% 5. CalibrationGui: enable rules and button-driven run
% Offline: no adapter, no filter -> Test Filter must be disabled.
cg1 = stimgen.calibration.CalibrationGui();
b = find_test_filter_btn(cg1);
assert(strcmp(b.Enable, 'off'), 'Test Filter enabled with no filter/adapter');
delete_gui_figure(b);

% Swept-sine-designed filter with adapter -> enabled; clicking runs the
% sweep flatness test.
cg2 = stimgen.calibration.CalibrationGui(eng);
b = find_test_filter_btn(cg2);
assert(strcmp(b.Enable, 'on'), 'Test Filter not enabled despite filter+adapter');
assert(eng.CalibrationData.filterSource == "swept_sine");
prevTested = eng.CalibrationData.filterTest.testedOn;
b.ButtonPushedFcn(b, []);
assert(eng.CalibrationData.filterTest.testedOn > prevTested, ...
    'CalibrationGui button did not run a new filter test');
delete_gui_figure(b);
fprintf('PASS CalibrationGui button (swept-sine filter)\n');

% Tone-designed filter with adapter -> clicking must NOT open the tone-test
% dialog; it runs the sweep flatness test directly, same as the swept-sine case.
cg3 = stimgen.calibration.CalibrationGui(engTone);
b = find_test_filter_btn(cg3);
assert(strcmp(b.Enable, 'on'), 'Test Filter not enabled for a tone-designed filter');
prevTested = engTone.CalibrationData.filterTest.testedOn;
b.ButtonPushedFcn(b, []);
assert(engTone.CalibrationData.filterTest.testedOn > prevTested, ...
    'CalibrationGui button did not run a new filter test for a tone-designed filter');
delete_gui_figure(b);
fprintf('PASS CalibrationGui button (tone-designed filter)\n');

fprintf('ALL PASS\n');
end

function b = find_test_filter_btn(cg)
assert(isvalid(cg));
b = findall(groot, 'Type', 'uibutton', 'Text', 'Test Filter');
assert(isscalar(b), 'expected exactly one Test Filter button, found %d', numel(b));
end

function delete_gui_figure(h)
delete(ancestor(h, 'figure'));
end
