function smoke_test_coefficient_buffer_param()
% smoke_test_coefficient_buffer_param()
% Headless smoke test for Coefficient Buffer parameter support in
% epsych.ProtocolDesigner:
%   1. Syntax-checks the files touched by the coefficient-buffer editor work.
%   2. Verifies a vector-valued Coefficient Buffer level displays as a
%      summary in the parameter table rather than concatenated digits.
%   3. Verifies compile() carries the coefficient vector through as a single
%      trial level.
%   4. Verifies the .esgc extraction source: an Engine round-trip preserves
%      CalibrationData.filter and its Coefficients.
%
% Run with: matlab -batch "run('tmp/smoke_test_coefficient_buffer_param.m')"

repoRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(repoRoot);
epsych_startup();

fprintf('--- Coefficient Buffer smoke test ---\n');

% 1. Syntax check touched files -------------------------------------------
touchedFiles = { ...
    fullfile(repoRoot, 'obj', '+epsych', '@ProtocolDesigner', 'private', 'editParameterCoefficientBufferValue.m'), ...
    fullfile(repoRoot, 'obj', '+epsych', '@ProtocolDesigner', 'onParamEdited.m'), ...
    fullfile(repoRoot, 'obj', '+epsych', '@ProtocolDesigner', 'private', 'getParameterValueDisplay.m'), ...
    fullfile(repoRoot, 'obj', '+epsych', '@ProtocolDesigner', 'private', 'getParameterValueFull.m')};

for k = 1:numel(touchedFiles)
    f = touchedFiles{k};
    assert(isfile(f), 'Missing file: %s', f);
    t = mtree(f, '-file');
    assert(~strcmp(t.root.kind, 'ERR'), 'Syntax error in %s', f);
end
fprintf('PASS: syntax check (%d files)\n', numel(touchedFiles));

% 2. Table display of a buffer-valued level -------------------------------
nTaps = 257;
coefs = sin(linspace(0, pi, nTaps));

protocol = epsych.Protocol(Name = 'CoefficientBufferSmokeTest');
module = protocol.Interfaces(1).Module;
module.add_parameter('FIRCoefs', {coefs}, ...
    Type = 'Coefficient Buffer', isArray = true, ...
    Description = "Equalization FIR coefficient buffer");
module.add_parameter('gain', [10 20], Type = 'Float', Unit = 'dB');

designer = epsych.ProtocolDesigner(protocol);
cleanupDesigner = onCleanup(@() delete(designer.Figure));

tableData = designer.TableParams.Data;
rowIdx = find(strcmp(tableData(:, 2), 'FIRCoefs'), 1);
assert(~isempty(rowIdx), 'FIRCoefs row not found in parameter table');
valueCell = tableData{rowIdx, 5};
assert(contains(valueCell, sprintf('[%d values]', nTaps)), ...
    'Expected "[%d values]" summary, got: %s', nTaps, valueCell);
fprintf('PASS: parameter table shows "%s" for the buffer level\n', valueCell);

% 3. Compile carries the vector through as one trial level ----------------
protocol.compile();
paramNames = {protocol.COMPILED.parameters.Name};
colIdx = find(strcmp(paramNames, 'FIRCoefs'), 1);
assert(~isempty(colIdx), 'FIRCoefs not found in compiled parameters');
compiledLevel = protocol.COMPILED.trials{1, colIdx};
assert(isnumeric(compiledLevel) && numel(compiledLevel) == nTaps, ...
    'Compiled trial level should be the %d-tap vector, got %s of %d elements', ...
    nTaps, class(compiledLevel), numel(compiledLevel));
assert(size(protocol.COMPILED.trials, 1) == 2, ...
    'Expected 2 trials (gain levels), got %d', size(protocol.COMPILED.trials, 1));
fprintf('PASS: compile carries %d-tap buffer as a single level across %d trials\n', ...
    numel(compiledLevel), size(protocol.COMPILED.trials, 1));

% 4. .esgc round-trip preserves the equalization filter -------------------
filt = designfilt('lowpassfir', 'FilterOrder', 10, 'CutoffFrequency', 0.4);
calData = struct();
calData.filter = filt;
calData.filterGrpDelay = 5;
calData.filterSource = "tone";
calData.filterDesign = struct('sampleRate', 48828.125, 'designedOn', datetime('now'));
calData.tone = struct('frequency', [1000; 2000], 'voltage', [1; 2]);

s = struct();
s.version = 1;
s.CalibrationData = calData;
s.MicSensitivity = 2.24;
s.NormativeValue = 94;
s.ReferenceLevel = 94;
s.ReferenceFrequency = 1000;
s.ExcitationVoltage = 1;
s.CalibrationTimestamp = datetime('now');

esgcFile = fullfile(tempdir, 'smoke_test_coef_buffer.esgc');
save(esgcFile, '-struct', 's');
cleanupEsgc = onCleanup(@() delete(esgcFile));

engine = stimgen.calibration.Engine.load(esgcFile);
loadedFilter = engine.CalibrationData.filter;
assert(isa(loadedFilter, 'digitalFilter'), ...
    'Expected digitalFilter after .esgc round-trip, got %s', class(loadedFilter));
loadedCoefs = loadedFilter.Coefficients;
assert(numel(loadedCoefs) == 11, ...
    'Expected 11 taps after round-trip, got %d', numel(loadedCoefs));
assert(isequal(loadedCoefs, filt.Coefficients), 'Coefficients changed in round-trip');
fprintf('PASS: .esgc round-trip preserves %d-tap equalization filter\n', numel(loadedCoefs));

fprintf('--- All coefficient buffer smoke tests passed ---\n');
end
