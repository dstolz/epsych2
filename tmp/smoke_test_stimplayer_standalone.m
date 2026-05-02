function report = smoke_test_stimplayer_standalone()
% report = smoke_test_stimplayer_standalone()
% Lightweight smoke test for standalone StimPlayer behavior.
%
% Verifies:
%   1) Constructor and cleanup succeed.
%   2) Constructor accepts a loaded epsych.Protocol.
%   3) Run/Stop path executes in speaker-preview mode with one Tone in bank.

report = struct();
report.timestamp = datetime('now');
report.steps = struct();

% Step 1: constructor / delete
stepName = 'constructor';
try
    sp = stimgen.StimPlayer();
    delete(sp);
    report.steps.(stepName) = struct('passed', true, 'detail', 'StimPlayer constructor and delete succeeded.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 2: protocol constructor path
stepName = 'constructorWithProtocol';
try
    pfn = fullfile(fileparts(mfilename('fullpath')), 'test_protocol_StimType_TONE.eprot');
    assert(isfile(pfn), 'SmokeTest:MissingProtocolFixture', 'Missing protocol fixture: %s', pfn);
    P = epsych.Protocol.load(pfn);
    sp = stimgen.StimPlayer(P);
    delete(sp);
    report.steps.(stepName) = struct('passed', true, 'detail', 'StimPlayer constructor accepted epsych.Protocol input.');
catch ME
    report.steps.(stepName) = struct('passed', false, 'detail', getReport(ME, 'basic', 'hyperlinks', 'off'));
end

% Step 3: run/stop speaker-preview flow
stepName = 'runStopNoProtocol';
try
    sp = stimgen.StimPlayer();
    c = onCleanup(@() localDelete_(sp));

    sp.open_stim(stimgen.Tone(), Name="SmokeTone");
    sp.playback_control(struct('Text', 'Run'), []);
    drawnow;
    pause(0.15);
    sp.playback_control(struct('Text', 'Stop'), []);
    drawnow;
    pause(0.05);

    clear c
    delete(sp);

    report.steps.(stepName) = struct('passed', true, 'detail', 'Run/Stop completed without throwing exceptions.');
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
    fprintf('StimPlayer standalone smoke test PASSED (%d/%d steps).\n', nnz(stepPassed), numel(stepPassed));
else
    fprintf('StimPlayer standalone smoke test FAILED (%d/%d steps).\n', nnz(stepPassed), numel(stepPassed));
    for i = 1:numel(stepNames)
        if ~report.steps.(stepNames{i}).passed
            fprintf('  - %s failed:\n%s\n', stepNames{i}, report.steps.(stepNames{i}).detail);
        end
    end
end

end

function localDelete_(sp)
if ~isempty(sp) && isvalid(sp)
    delete(sp);
end
end
