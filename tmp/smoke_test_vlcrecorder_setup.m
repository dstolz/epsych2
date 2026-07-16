function report = smoke_test_vlcrecorder_setup()
% report = smoke_test_vlcrecorder_setup()
% Lightweight smoke test for gui.VlcRecorderSetup.
%
% Verifies:
%   1) Crop coordinate math round-trips (ROI <-> crop values), including
%      clamping behavior at the minimum ROI size.
%   2) Constructor/Apply/delete work with EnablePreview=false (no webcam
%      opened), and no timer/figure is left behind after delete.
%   3) (Gated) With a real webcam available, live preview + ROI commit
%      works end-to-end. Skipped when no webcam support/hardware is present,
%      or when the camera can't be opened (e.g. already in use elsewhere).

report = struct();
report.timestamp = datetime('now');
report.steps = struct();

% Step 1: crop coordinate round-trip
stepName = 'cropMathRoundTrip';
try
    imgSize = [640 480];

    cases = { ...
        [0 0 0 0], ...       % no crop
        [10 20 30 40], ...   % asymmetric
        [0 0 320 320], ...   % left+right == W, forces width clamping
        [300 300 0 0]};      % top+bottom > H, forces height clamping

    for i = 1:numel(cases)
        cIn = cases{i};
        [pos, cCorrected] = gui.VlcRecorderSetup.cropsToRoi(cIn, imgSize, 16);
        cRoundTrip = gui.VlcRecorderSetup.roiToCrops(pos, imgSize);
        assert(isequal(cRoundTrip, cCorrected), ...
            'SmokeTest:CropRoundTripMismatch', ...
            'Case %d: round-trip %s does not match corrected crops %s.', ...
            i, mat2str(cRoundTrip), mat2str(cCorrected));

        w = imgSize(1) - cCorrected(3) - cCorrected(4);
        h = imgSize(2) - cCorrected(1) - cCorrected(2);
        assert(w >= 16 - 1e-9 && h >= 16 - 1e-9, ...
            'SmokeTest:CropTooSmall', 'Case %d: corrected ROI [%g x %g] below minimum.', i, w, h);
    end

    % Full-frame ROI must map back to zero crop on every edge.
    fullFramePos = [0.5 0.5 imgSize(1) imgSize(2)];
    fullFrameCrops = gui.VlcRecorderSetup.roiToCrops(fullFramePos, imgSize);
    assert(isequal(fullFrameCrops, [0 0 0 0]), ...
        'SmokeTest:FullFrameCropMismatch', 'Full-frame ROI produced nonzero crop: %s.', mat2str(fullFrameCrops));

    report.steps.(stepName) = struct('passed', true, 'detail', 'Crop <-> ROI round-trip and clamping behaved as expected.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 2: construct / Apply / delete without opening a webcam
stepName = 'constructNoPreview';
try
    rec = hw.VlcRecorder();
    g = gui.VlcRecorderSetup(rec, EnablePreview=false, PersistPrefs=false);
    c = onCleanup(@() localDelete_(g, rec));

    fig = g.Parent;

    topField = findall(fig, 'Tag', 'VlcRecorderSetup_CropTopField');
    leftField = findall(fig, 'Tag', 'VlcRecorderSetup_CropLeftField');
    frSpinner = findall(fig, 'Tag', 'VlcRecorderSetup_FrameRateSpinner');
    resDD = findall(fig, 'Tag', 'VlcRecorderSetup_ResolutionDropDown');
    applyBtn = findall(fig, 'Tag', 'VlcRecorderSetup_ApplyButton');

    assert(~isempty(topField) && ~isempty(leftField) && ~isempty(frSpinner) ...
        && ~isempty(resDD) && ~isempty(applyBtn), ...
        'SmokeTest:MissingControl', 'Could not locate expected tagged UI controls.');

    topField.Value = 40;
    topField.ValueChangedFcn(topField, []);
    leftField.Value = 20;
    leftField.ValueChangedFcn(leftField, []);
    frSpinner.Value = 15;
    frSpinner.ValueChangedFcn(frSpinner, []);

    resDD.Items = [resDD.Items, {'1024x768'}];
    resDD.Value = '1024x768';
    resDD.ValueChangedFcn(resDD, []);

    applyBtn.ButtonPushedFcn(applyBtn, []);
    drawnow;

    assert(isequal(rec.get_parameter('CropTop'), 40), 'SmokeTest:ApplyMismatch', 'CropTop not applied.');
    assert(isequal(rec.get_parameter('CropLeft'), 20), 'SmokeTest:ApplyMismatch', 'CropLeft not applied.');
    assert(isequal(rec.get_parameter('FrameRate'), 15), 'SmokeTest:ApplyMismatch', 'FrameRate not applied.');
    assert(isequal(rec.get_parameter('Resolution'), [1024 768]), ...
        'SmokeTest:ApplyMismatch', 'Explicit Resolution selection not applied.');

    clear c
    delete(g);
    drawnow;

    leakedTimers = timerfind('Tag', 'gui_VlcRecorderSetup');
    assert(isempty(leakedTimers), 'SmokeTest:TimerLeak', 'Preview timer was not cleaned up.');
    assert(~isgraphics(fig), 'SmokeTest:FigureLeak', 'Owned figure was not deleted.');

    delete(rec);

    report.steps.(stepName) = struct('passed', true, 'detail', 'Construct, Apply, and delete completed cleanly with no timer/figure leaks.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 3: live webcam preview + ROI commit (gated on real hardware)
stepName = 'previewHardware';
try
    haveSupport = exist('webcam', 'file') == 2;
    camList = {};
    if haveSupport
        try
            camList = webcamlist;
        catch
            camList = {};
        end
    end

    if ~haveSupport || isempty(camList)
        report.steps.(stepName) = struct('passed', true, 'detail', 'skipped: no webcam support package or no camera detected');
    else
        rec = hw.VlcRecorder();
        g = gui.VlcRecorderSetup(rec, PersistPrefs=false);
        c = onCleanup(@() localDelete_(g, rec));

        pause(1);
        drawnow;

        fig = g.Parent;
        applyBtn = findall(fig, 'Tag', 'VlcRecorderSetup_ApplyButton');
        topField = findall(fig, 'Tag', 'VlcRecorderSetup_CropTopField');
        resDD = findall(fig, 'Tag', 'VlcRecorderSetup_ResolutionDropDown');

        topField.Value = 32;
        topField.ValueChangedFcn(topField, []);
        applyBtn.ButtonPushedFcn(applyBtn, []);
        drawnow;

        assert(isequal(rec.get_parameter('CropTop'), 32), 'SmokeTest:ApplyMismatch', 'CropTop not applied with live preview.');

        % An explicit dropdown selection must win over the previewed frame
        % size on commit, even while the live preview is running.
        resItems = resDD.Items(~strcmp(resDD.Items, '(camera default)'));
        if ~isempty(resItems)
            pick = resItems{end};
            resDD.Value = pick;
            resDD.ValueChangedFcn(resDD, []);
            drawnow;
            applyBtn.ButtonPushedFcn(applyBtn, []);
            drawnow;
            want = sscanf(pick, '%dx%d')';
            assert(isequal(rec.get_parameter('Resolution'), want), ...
                'SmokeTest:ApplyMismatch', ...
                'Live preview: committed Resolution %s does not match dropdown selection "%s".', ...
                mat2str(rec.get_parameter('Resolution')), pick);
        end

        clear c
        delete(g);
        delete(rec);

        report.steps.(stepName) = struct('passed', true, 'detail', 'Live preview construct/Apply/delete completed without error.');
    end
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

stepNames = fieldnames(report.steps);
stepPassed = false(size(stepNames));
for i = 1:numel(stepNames)
    stepPassed(i) = logical(report.steps.(stepNames{i}).passed);
end
report.allPassed = all(stepPassed);

if report.allPassed
    fprintf('VlcRecorderSetup smoke test PASSED (%d/%d steps).\n', nnz(stepPassed), numel(stepPassed));
else
    fprintf('VlcRecorderSetup smoke test FAILED (%d/%d steps).\n', nnz(stepPassed), numel(stepPassed));
    for i = 1:numel(stepNames)
        if ~report.steps.(stepNames{i}).passed
            fprintf('  - %s failed:\n%s\n', stepNames{i}, report.steps.(stepNames{i}).detail);
        end
    end
end

end

function localDelete_(g, rec)
if ~isempty(g) && isvalid(g)
    delete(g);
end
if ~isempty(rec) && isvalid(rec)
    delete(rec);
end
end
