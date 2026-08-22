function smoke_test_detection_respcode
% smoke_test_detection_respcode
% Standing proof that psychophysics.Detection reads the outcome field under
% EITHER of its two names.
%
% 'ResponseCode' is the older spelling and is still what many saved sessions
% carry. Detection.responseCodes used to read 'RespCode' and nothing else, so
% such a session analyzed as ZERO trials -- silently, since every count, rate
% and d' comes back empty rather than throwing, which reads as a subject who
% never responded rather than as a bug.
%
% Verifies:
%   1) a RespCode-only session scores
%   2) a ResponseCode-only session scores identically
%   3) RespCode wins where a file carries both
%   4) a session with neither returns empty and does not throw
%
% Run headless: matlab -batch "run('tmp/smoke_test_detection_respcode.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

fprintf('smoke_test_detection_respcode\n');

% Six stimulus trials at two levels (4 hits, 2 misses) and two catch trials
% (1 false alarm, 1 correct reject).
levels  = [1 1 1 2 2 2 0 0];
outcome = ["Hit" "Hit" "Miss" "Hit" "Hit" "Miss" "FalseAlarm" "CorrectReject"];
isCatch = [false false false false false false true true];

codes = zeros(1, numel(levels), 'uint32');
for k = 1:numel(levels)
    tt = epsych.BitMask.TrialType_1;
    if ~isCatch(k), tt = epsych.BitMask.TrialType_0; end
    codes(k) = bitset(bitset(uint32(0), uint32(epsych.BitMask(outcome(k)))), uint32(tt));
end

% 1 & 2. Either spelling alone -------------------------------------------
r1 = analyze(levels, codes, "RespCode");
r2 = analyze(levels, codes, "ResponseCode");

assert(isequal(r1.uniqueValues, [1 2]), ...
    'RespCode: expected levels [1 2], got %s', mat2str(r1.uniqueValues));
assert(isequal(r1.hits, [2 2]) && isequal(r1.misses, [1 1]), ...
    'RespCode: expected 2 hits and 1 miss per level, got %s / %s', ...
    mat2str(r1.hits), mat2str(r1.misses));
fprintf('  1) RespCode-only     : %d levels, hits %s, d'' %s\n', ...
    numel(r1.uniqueValues), mat2str(r1.hits), mat2str(round(r1.dprime, 3)));

assert(isequal(r2.uniqueValues, r1.uniqueValues) && isequal(r2.hits, r1.hits) ...
    && isequal(r2.misses, r1.misses) && isequaln(r2.dprime, r1.dprime), ...
    'ResponseCode-only scored differently from RespCode-only');
fprintf('  2) ResponseCode-only : identical\n');

% 3. Both present, RespCode wins -----------------------------------------
% Deliberately disagreeing codes: if the fallback were preferred, every
% stimulus trial would score a Miss.
allMiss = repmat(bitset(bitset(uint32(0), uint32(epsych.BitMask.Miss)), ...
    uint32(epsych.BitMask.TrialType_0)), 1, numel(levels));
D = makeData(levels, codes, "RespCode");
c = num2cell(allMiss);
[D.ResponseCode] = c{:};
r3 = analyzeData(D);
assert(isequal(r3.hits, r1.hits), ...
    'with both fields present RespCode must win; got hits %s', mat2str(r3.hits));
fprintf('  3) both present      : RespCode wins\n');

% 4. Neither ---------------------------------------------------------------
% Only the resolver is checked here. Count/Rate/DPrime THROW on such a
% session -- get.Count indexes the decoded masks, which are empty, by a mask
% sized to the trials -- and that is a separate defect from the one this test
% covers. Reading Count here would be asserting on that bug rather than this
% resolver.
D = makeData(levels, codes, "RespCode");
D = rmfield(D, 'RespCode');
r4 = analyzeData(D, CodesOnly=true);
assert(isempty(r4.codes), 'expected no response codes, got %s', mat2str(r4.codes));
fprintf('  4) neither field     : resolver returns empty\n');

fprintf('smoke_test_detection_respcode PASSED\n');
end


function D = makeData(levels, codes, fieldName)
% One DATA record per trial, with the outcome under the requested name.
D = struct('Level', num2cell(levels), 'TrialType', num2cell(double(levels == 0)));
c = num2cell(codes);
[D.(fieldName)] = c{:};
end


function r = analyze(levels, codes, fieldName)
r = analyzeData(makeData(levels, codes, fieldName));
end


function r = analyzeData(D, options)
% Score one DATA array through psychophysics.Detection, the way a live session
% does: a real runtime, a real event hub, and one NewData carrying every trial.
% CodesOnly stops at the resolved response codes.
arguments
    D struct
    options.CodesOnly (1,1) logical = false
end

rt = epsych.Runtime;
rt.isTest = true;
rt.ReviewMode = true;      % suppress the one-shot dispatch in set.TRIALS
rt.EVENTS = epsych.EventHub;

iface = hw.Software();
P = iface.Module.add_parameter('Level', 1);

T = struct('DATA', D, 'TrialIndex', numel(D), 'Subject', struct('Name', 'smoke'), ...
    'BoxID', 1, 'NextTrialID', 1);
rt.TRIALS = T;

psy = psychophysics.Detection(rt, P, epsych.BitMask.TrialType_0);
cleanup = onCleanup(@() delete(psy));
psy.update_data([], epsych.TrialsData(T));

r.codes = psy.responseCodes;
if options.CodesOnly, return; end

r.uniqueValues = psy.uniqueValues;
r.hits         = [psy.Count.Hit];
r.misses       = [psy.Count.Miss];
r.dprime       = psy.DPrime;
end
