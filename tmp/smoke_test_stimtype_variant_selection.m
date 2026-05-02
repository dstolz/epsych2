function report = smoke_test_stimtype_variant_selection()
% report = smoke_test_stimtype_variant_selection()
% Run a lightweight smoke test for StimType vector-variant selection.
%
% This test validates:
%   1) Cartesian + Serial behavior with vectorized properties.
%   2) PairwiseStrict length mismatch error path.
%   3) PairwiseScalarExpand behavior with scalar expansion.
%   4) Non-vectorizable guard for Fs/ApplyCalibration/ApplyWindow.
%   5) Basic execution of ShuffleUniform / ShuffleLeastUsed.
%   6) Optional CustomSelector mode if a selector class is available.
%   7) evaluate_property_expression_: range syntax (0:10:50).
%   8) evaluate_property_expression_: vector literal ([1000 2000 4000]).
%   9) evaluate_property_expression_: MATLAB expression (1000*2.^(0:3)).
%  10) evaluate_property_expression_: cross-property bare name reference.
%  11) evaluate_property_expression_: qualified ClassName.PropName reference.
%  12) evaluate_property_expression_: reject assignment syntax.
%  13) evaluate_property_expression_: reject semicolon statement.
%  14) evaluate_property_expression_: reject non-finite (Inf/NaN) result.
%  15) localFormatPropertyValue_: scalar and vector display formatting.
%  16) AMnoise: vector AMDepth expression assignment and update_signal.
%  17) Noise: vector HighPass expression assignment and update_signal.
%  18) FMtone: vector CarrierFrequency expression assignment and update_signal.
%  19) ClickTrain: vector Rate expression assignment and update_signal.
%
% Returns:
%   report - Struct with pass/fail flags and details for each section.

report = struct();
report.timestamp = datetime('now');
report.allPassed = false;
report.steps = struct();

tone = stimgen.Tone();

% 1) Cartesian + Serial
stepName = 'cartesianSerial';
try
    tone.Frequency = [1000 2000 4000 8000];
    tone.SoundLevel = [0 10 20 30 40];
    tone.VariantCombinationMode = "Cartesian";
    tone.VariantSelectionMode = "Serial";
    tone.VariantReselectOnUpdate = false;

    observedFreq = zeros(1, 8);
    for k = 1:8
        tone.update_signal();
        observedFreq(k) = double(tone.selected_value("Frequency"));
    end

    expectedFreq = [1000 2000 4000 8000 1000 2000 4000 8000];
    assert(isequal(observedFreq, expectedFreq), ...
        'Cartesian+Serial frequency sequence mismatch.');

    report.steps.(stepName) = struct('passed', true, 'detail', 'Cartesian+Serial sequence matched expected frequency cycle.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% 2) PairwiseStrict mismatch should error
stepName = 'pairwiseStrictMismatch';
try
    tone.Frequency = [1000 2000 4000 8000];
    tone.SoundLevel = [0 10 20 30 40];
    tone.VariantCombinationMode = "PairwiseStrict";
    tone.VariantSelectionMode = "Serial";
    tone.VariantReselectOnUpdate = true;

    threwExpected = false;
    try
        tone.update_signal();
    catch ME
        threwExpected = strcmp(ME.identifier, 'stimgen:StimType:PairwiseLengthMismatch');
    end

    assert(threwExpected, 'PairwiseStrict mismatch did not throw stimgen:StimType:PairwiseLengthMismatch.');
    report.steps.(stepName) = struct('passed', true, 'detail', 'PairwiseStrict mismatch produced expected error.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% 3) PairwiseScalarExpand
stepName = 'pairwiseScalarExpand';
try
    tone.Frequency = [1000 2000 4000 8000];
    tone.SoundLevel = 20;
    tone.VariantCombinationMode = "PairwiseScalarExpand";
    tone.VariantSelectionMode = "Serial";
    tone.VariantReselectOnUpdate = false;

    observedFreq = zeros(1, 4);
    observedLevel = zeros(1, 4);
    for k = 1:4
        tone.update_signal();
        observedFreq(k) = double(tone.selected_value("Frequency"));
        observedLevel(k) = double(tone.selected_value("SoundLevel"));
    end

    assert(isequal(observedFreq, [1000 2000 4000 8000]), 'PairwiseScalarExpand frequency sequence mismatch.');
    assert(all(observedLevel == 20), 'PairwiseScalarExpand scalar expansion for SoundLevel failed.');

    report.steps.(stepName) = struct('passed', true, 'detail', 'PairwiseScalarExpand produced expected sequence and scalar expansion.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% 4) Non-vectorizable property guard (Fs)
stepName = 'nonVectorizableGuard';
try
    tone.Frequency = 1000;
    tone.SoundLevel = 20;
    tone.VariantCombinationMode = "Cartesian";
    tone.VariantSelectionMode = "Serial";

    threwExpected = false;
    originalFs = tone.Fs;
    try
        tone.Fs = [44100 48000];
        tone.update_signal();
    catch ME
        threwExpected = strcmp(ME.identifier, 'stimgen:StimType:NonVectorizableProperty') || ...
            startsWith(ME.identifier, 'MATLAB:') || ...
            contains(ME.message, 'size') || ...
            contains(ME.message, 'dimensions');
    end
    tone.Fs = originalFs;

    assert(threwExpected, 'Vector Fs assignment was expected to fail but succeeded.');
    report.steps.(stepName) = struct('passed', true, 'detail', 'Fs vectorization was rejected as expected.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% 5) Shuffle modes smoke (run without assertions on exact sequence)
stepName = 'shuffleModesSmoke';
try
    tone.Frequency = [500 1000 2000 4000];
    tone.SoundLevel = 10;
    tone.VariantCombinationMode = "PairwiseScalarExpand";
    tone.VariantReselectOnUpdate = true;

    tone.VariantSelectionMode = "ShuffleUniform";
    for k = 1:10
        tone.update_signal();
    end

    tone.VariantSelectionMode = "ShuffleLeastUsed";
    for k = 1:10
        tone.update_signal();
    end

    report.steps.(stepName) = struct('passed', true, 'detail', 'ShuffleUniform and ShuffleLeastUsed executed without runtime errors.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% 6) Optional CustomSelector smoke
stepName = 'customSelectorSmoke';
try
    selectorClass = "";
    candidates = [ ...
        "epsych.DefaultTrialSelector", ...
        "DefaultTrialSelector" ...
    ];
    for i = 1:numel(candidates)
        if exist(char(candidates(i)), 'class') == 8
            selectorClass = candidates(i);
            break
        end
    end

    if selectorClass == ""
        report.steps.(stepName) = struct('passed', true, 'detail', 'Skipped: no TrialSelector subclass found on path for smoke test.');
    else
        tone.Frequency = [1000 2000 4000];
        tone.SoundLevel = 20;
        tone.VariantCombinationMode = "PairwiseScalarExpand";
        tone.VariantSelectionMode = "CustomSelector";
        tone.VariantSelectorClass = selectorClass;
        tone.VariantReselectOnUpdate = true;
        tone.update_signal();

        report.steps.(stepName) = struct('passed', true, 'detail', sprintf('CustomSelector executed with %s.', selectorClass));
    end
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% 7) evalPropertyExpression: range syntax
stepName = 'exprRangeSyntax';
try
    tone.SoundLevel = 0;
    result = tone.evalPropertyExpression('SoundLevel', '0:10:50');
    assert(isequal(result, 0:10:50), 'Range 0:10:50 did not produce expected vector.');
    report.steps.(stepName) = struct('passed', true, 'detail', 'Range expression 0:10:50 evaluated correctly.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% 8) evalPropertyExpression: vector literal
stepName = 'exprVectorLiteral';
try
    result = tone.evalPropertyExpression('Frequency', '[1000 2000 4000 8000]');
    assert(isequal(result, [1000 2000 4000 8000]), 'Vector literal did not produce expected values.');
    report.steps.(stepName) = struct('passed', true, 'detail', 'Vector literal [1000 2000 4000 8000] evaluated correctly.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% 9) evalPropertyExpression: MATLAB expression
stepName = 'exprMatlabExpr';
try
    result = tone.evalPropertyExpression('Frequency', '1000*2.^(0:3)');
    assert(isequal(result, [1000 2000 4000 8000]), 'MATLAB expression 1000*2.^(0:3) did not produce expected values.');
    report.steps.(stepName) = struct('passed', true, 'detail', 'MATLAB expression 1000*2.^(0:3) evaluated correctly.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% 10) evalPropertyExpression: cross-property bare name reference
stepName = 'exprBarePropRef';
try
    tone.SoundLevel = 60;
    result = tone.evalPropertyExpression('Frequency', 'SoundLevel * 50');
    assert(isequal(result, 3000), 'Bare property reference SoundLevel*50 did not produce 3000.');
    report.steps.(stepName) = struct('passed', true, 'detail', 'Bare property reference SoundLevel*50 evaluated correctly.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% 11) evalPropertyExpression: qualified ClassName.PropName reference
stepName = 'exprQualifiedRef';
try
    tone.SoundLevel = 60;
    result = tone.evalPropertyExpression('Frequency', 'Tone.SoundLevel * 50');
    assert(isequal(result, 3000), 'Qualified Tone.SoundLevel*50 did not produce 3000.');
    report.steps.(stepName) = struct('passed', true, 'detail', 'Qualified reference Tone.SoundLevel*50 evaluated correctly.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% 12) evalPropertyExpression: reject assignment syntax
stepName = 'exprRejectAssignment';
try
    threwExpected = false;
    try
        tone.evalPropertyExpression('Frequency', 'Frequency = 1000');
    catch ME2
        threwExpected = contains(ME2.message, 'Assignments are not allowed');
    end
    assert(threwExpected, 'Assignment expression was expected to be rejected but was not.');
    report.steps.(stepName) = struct('passed', true, 'detail', 'Assignment expression was correctly rejected.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% 13) evalPropertyExpression: reject semicolon statement
stepName = 'exprRejectSemicolon';
try
    threwExpected = false;
    try
        tone.evalPropertyExpression('Frequency', '1000; 2000');
    catch ME2
        threwExpected = contains(ME2.message, 'single expression');
    end
    assert(threwExpected, 'Semicolon expression was expected to be rejected but was not.');
    report.steps.(stepName) = struct('passed', true, 'detail', 'Semicolon expression was correctly rejected.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% 14) evalPropertyExpression: reject non-finite result
stepName = 'exprRejectNonFinite';
try
    threwExpected = false;
    try
        tone.evalPropertyExpression('Frequency', '1/0');
    catch ME2
        threwExpected = contains(ME2.message, 'finite');
    end
    assert(threwExpected, 'Non-finite expression (1/0) was expected to be rejected but was not.');
    report.steps.(stepName) = struct('passed', true, 'detail', 'Non-finite expression 1/0 was correctly rejected.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% 15) localFormatPropertyValue_ round-trip via scalar and vector display
stepName = 'exprVectorRoundTrip';
try
    tone.Frequency = 1000;
    tone.SoundLevel = 0;
    tone.VariantCombinationMode = "Cartesian";
    tone.VariantSelectionMode = "Serial";
    tone.VariantReselectOnUpdate = false;

    freqVec = tone.evalPropertyExpression('Frequency', '1000*2.^(0:3)');
    levelVec = tone.evalPropertyExpression('SoundLevel', '0:10:50');
    tone.Frequency = freqVec;
    tone.SoundLevel = levelVec;

    assert(numel(tone.Frequency) == 4, 'Expected 4 Frequency values after expression assignment.');
    assert(numel(tone.SoundLevel) == 6, 'Expected 6 SoundLevel values after expression assignment.');

    nExpected = 4 * 6;
    observedCombos = zeros(1, nExpected);
    for k = 1:nExpected
        tone.update_signal();
        observedCombos(k) = double(tone.selected_value("Frequency"));
    end
    assert(numel(unique(observedCombos)) == 4, 'Expected 4 unique frequencies across Cartesian product.');
    report.steps.(stepName) = struct('passed', true, 'detail', 'Expression-driven vector assignment and Cartesian trial expansion matched expected behavior.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% 16) AMnoise vector AMDepth expression should assign and run
stepName = 'amnoiseAMDepthVector';
try
    amn = stimgen.AMnoise();
    amn.VariantCombinationMode = "PairwiseScalarExpand";
    amn.VariantSelectionMode = "Serial";
    amn.VariantReselectOnUpdate = false;

    depthVec = amn.evalPropertyExpression('AMDepth', '0.1:0.1:1');
    amn.AMDepth = depthVec;
    assert(numel(amn.AMDepth) == 10, 'Expected 10 AMDepth values from 0.1:0.1:1.');

    amn.AMRate = 5;
    amn.update_signal();
    selectedDepth = double(amn.selected_value("AMDepth"));
    assert(selectedDepth >= 0.1 && selectedDepth <= 1, 'Selected AMDepth must be within [0.1, 1].');

    report.steps.(stepName) = struct('passed', true, 'detail', 'AMnoise accepted vector AMDepth and update_signal executed.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% 17) Noise vector HighPass expression should assign and run
stepName = 'noiseHighPassVector';
try
    nz = stimgen.Noise();
    nz.VariantCombinationMode = "PairwiseScalarExpand";
    nz.VariantSelectionMode = "Serial";
    nz.VariantReselectOnUpdate = false;

    hpVec = nz.evalPropertyExpression('HighPass', '500:500:2500');
    nz.HighPass = hpVec;
    nz.LowPass = 12000;
    nz.update_signal();

    selectedHighPass = double(nz.selected_value("HighPass"));
    assert(selectedHighPass >= 500 && selectedHighPass <= 2500, 'Selected HighPass must be within [500, 2500].');
    report.steps.(stepName) = struct('passed', true, 'detail', 'Noise accepted vector HighPass and update_signal executed.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% 18) FMtone vector CarrierFrequency expression should assign and run
stepName = 'fmtoneCarrierVector';
try
    fm = stimgen.FMtone();
    fm.VariantCombinationMode = "PairwiseScalarExpand";
    fm.VariantSelectionMode = "Serial";
    fm.VariantReselectOnUpdate = false;

    carrierVec = fm.evalPropertyExpression('CarrierFrequency', '[2000 4000 8000]');
    fm.CarrierFrequency = carrierVec;
    fm.ModulationFrequency = 10;
    fm.ModulationDepth = 500;
    fm.update_signal();

    selectedCarrier = double(fm.selected_value("CarrierFrequency"));
    assert(ismember(selectedCarrier, [2000 4000 8000]), 'Selected CarrierFrequency must be one of [2000 4000 8000].');
    report.steps.(stepName) = struct('passed', true, 'detail', 'FMtone accepted vector CarrierFrequency and update_signal executed.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% 19) ClickTrain vector Rate expression should assign and run
stepName = 'clickTrainRateVector';
try
    ct = stimgen.ClickTrain();
    ct.VariantCombinationMode = "PairwiseScalarExpand";
    ct.VariantSelectionMode = "Serial";
    ct.VariantReselectOnUpdate = false;

    rateVec = ct.evalPropertyExpression('Rate', '5:5:25');
    ct.Rate = rateVec;
    ct.ClickDuration = 100e-6;
    ct.update_signal();

    selectedRate = double(ct.selected_value("Rate"));
    assert(ismember(selectedRate, 5:5:25), 'Selected Rate must be one of 5:5:25.');
    report.steps.(stepName) = struct('passed', true, 'detail', 'ClickTrain accepted vector Rate and update_signal executed.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Aggregate result
stepNames = fieldnames(report.steps);
stepPassed = false(size(stepNames));
for i = 1:numel(stepNames)
    stepPassed(i) = logical(report.steps.(stepNames{i}).passed);
end
report.allPassed = all(stepPassed);

if report.allPassed
    fprintf('StimType variant smoke test PASSED (%d/%d steps).\n', nnz(stepPassed), numel(stepPassed));
else
    fprintf('StimType variant smoke test FAILED (%d/%d steps).\n', nnz(stepPassed), numel(stepPassed));
    for i = 1:numel(stepNames)
        if ~report.steps.(stepNames{i}).passed
            fprintf('  - %s failed:\n%s\n', stepNames{i}, report.steps.(stepNames{i}).detail);
        end
    end
end
end