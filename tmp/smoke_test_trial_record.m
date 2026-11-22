function smoke_test_trial_record
% smoke_test_trial_record
% epsych.Runtime.trialRecord is the trial-end read. With the defaults it is
% all_parameters(Access='Read', asStruct=true, valueOnly=true), field for
% field. Two opt-in session settings change what a record holds of the two
% kinds of value that are big:
%
%   RecordBuffers = false          buffers are not read and not recorded
%   RecordStimulusSettings = true  a stimulus is recorded as its settings
%                                  struct, not as the live handle object
%
% Verifies:
%   1) defaults: the record equals the all_parameters sweep exactly
%   2) RecordBuffers = false: no buffer field, and the buffer is not read
%      off the device; every other field is unchanged
%   3) RecordStimulusSettings = true: the stimulus field is a plain struct of
%      its settings, a parameter with no stimulus stays empty, and the record
%      does not change when the stimulus is edited afterwards
%   4) the default record of a stimulus IS the live object, shared by every
%      trial (the reason the setting exists)
%   5) through the real trial loop: every record of a session has the same
%      fields, and the journal is a fraction of the size
%
% No hardware, no windows.
%
%   matlab -batch "run('tmp/smoke_test_trial_record.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(here);

fprintf('\n=== smoke_test_trial_record ===\n');

scratch = fullfile(tempdir, sprintf('smoke_trialrecord_%d', feature('getpid')));
if isfolder(scratch), rmdir(scratch, 's'); end
mkdir(scratch);
cleanupScratch = onCleanup(@() localRmdir(scratch));

% --- a runtime with every kind of value a record meets -----------------------
[rt, dev, tone, pEmpty] = localRuntime();

% --- 1. the defaults are the sweep -------------------------------------------
assert(rt.RecordBuffers && ~rt.RecordStimulusSettings, 'the defaults record what has always been recorded');
swept = rt.all_parameters(Access = 'Read', asStruct = true, valueOnly = true);
rec = rt.trialRecord();
assert(isequal(fieldnames(rec), fieldnames(swept)), 'default record: field names or their order differ');
fn = fieldnames(swept);
for k = 1:numel(fn)
    a = swept.(fn{k});
    b = rec.(fn{k});
    assert(strcmp(class(a), class(b)) && (isequaln(a, b) || (isa(a, 'handle') && all(a == b))), ...
        'default record: field %s differs', fn{k});
end
assert(isfield(rec, 'Buf') && numel(rec.Buf) == 4096, 'the buffer is in the default record, whole');
fprintf('PASS: 1 the default record is the all_parameters sweep (%d fields)\n', numel(fn));

% --- 4. (shown here, while the defaults stand) the object is shared ----------
first = rt.trialRecord();
tone.Frequency = 2222;
second = rt.trialRecord();
assert(isa(first.Stim, 'stimgen.Tone') && first.Stim == second.Stim, ...
    'the default record holds the live stimulus object');
assert(first.Stim.Frequency == 2222, ...
    'and so an earlier record shows the stimulus as it is NOW, not as it was');
tone.Frequency = 1000;
fprintf('PASS: 4 by default every record holds the same live stimulus object\n');

% --- 2. buffers left out -----------------------------------------------------
rt.RecordBuffers = false;
dev.resetCounts();
rec = rt.trialRecord();
readsWithout = dev.Counts.Read;
assert(~isfield(rec, 'Buf'), 'RecordBuffers = false: the buffer has no field');
rest = rmfield(swept, 'Buf');
assert(isequal(fieldnames(rec), fieldnames(rest)), 'the other fields and their order are unchanged');
rt.RecordBuffers = true;
dev.resetCounts();
rt.trialRecord();
assert(dev.Counts.Read == readsWithout + 1, ...
    'the buffer is not read off the device when it is not recorded (%d vs %d reads)', ...
    readsWithout, dev.Counts.Read);
rt.RecordBuffers = false;
rec2 = rt.trialRecord();
assert(isequal(fieldnames(rec2), fieldnames(rec)), 'the plan is rebuilt for the shorter list and reused');
rt.RecordBuffers = true;
fprintf('PASS: 2 RecordBuffers = false: not read, not recorded, nothing else changed\n');

% --- 3. stimuli as settings --------------------------------------------------
rt.RecordStimulusSettings = true;
rec = rt.trialRecord();
assert(isequal(fieldnames(rec), fieldnames(swept)), 'the same fields in the same order');
s = rec.Stim;
assert(isstruct(s) && isscalar(s), 'the stimulus is recorded as a struct (got %s)', class(s));
assert(strcmp(string(s.Class), "stimgen.Tone") && s.Frequency == 1000 && s.Duration == tone.Duration, ...
    'the struct carries the stimulus''s class and settings');
assert(~isfield(s, 'Signal'), 'and not its samples');
assert(isempty(rec.(pEmpty.validName)), 'a parameter with no stimulus stays empty');
tone.Frequency = 3333;
assert(s.Frequency == 1000 && rec.Stim.Frequency == 1000, 'a record does not change when the stimulus does');
later = rt.trialRecord();
assert(later.Stim.Frequency == 3333, 'and the next record has the new setting');
tone.Frequency = 1000;
others = setdiff(fn, {'Stim'});
for k = 1:numel(others)
    assert(isequaln(rec.(others{k}), swept.(others{k})), 'field %s changed with RecordStimulusSettings', others{k});
end
fprintf('PASS: 3 RecordStimulusSettings = true: a plain struct of settings, fixed at the trial\n');
delete(rt);

% --- 5. through the trial loop -----------------------------------------------
NTRIALS = 8;
[bytesObj, fieldsObj] = localSession(scratch, 'objects', false, NTRIALS);
[bytesSet, fieldsSet, D] = localSession(scratch, 'settings', true, NTRIALS);
assert(isequal(fieldsObj, fieldsSet), 'the two sessions record the same fields');
assert(numel(D) == NTRIALS, 'every trial has a record');
assert(all(arrayfun(@(d) isstruct(d.Stim) && isscalar(d.Stim), D)), 'every record holds the settings struct');
assert(~any(arrayfun(@(d) isfield(d, 'Buf'), D)), 'and no buffer');
assert(bytesSet < bytesObj / 10, ...
    'each trial should add a fraction of what it did (%.0f vs %.0f bytes per trial)', bytesSet, bytesObj);
fprintf('PASS: 5 in the loop: the journal grows %.0f KB per trial as objects, %.1f KB as settings without buffers\n', ...
    bytesObj / 1024, bytesSet / 1024);

fprintf('smoke_test_trial_record: ALL PASS\n');
end


% -----------------------------------------------------------------------------
function [rt, dev, tone, pEmpty] = localRuntime()
P = epsych.Protocol(Info = 'trial_record');
dev = CountingProbeInterface(CoerceSingle = true);
P.addInterface(dev);

p = dev.add_parameter('Gain', 0.1);  p.Value = 0.1;
p = dev.add_parameter('RespCode', 0, Type = 'Integer', Access = 'Read'); dev.put(p, uint32(17));
p = dev.add_parameter('Buf', 0, Type = 'Buffer', Access = 'Read', isArray = true); dev.put(p, single(1:4096));
tone = stimgen.Tone();
tone.Duration = 0.05;
pStim = dev.add_parameter('Stim', {tone}, Type = 'StimType');
pStim.Value = tone;
pEmpty = dev.add_parameter('StimNone', [], Type = 'StimType');
for nm = ["x_NewTrial_1" "x_ResetTrig_1" "x_TrialComplete_1"]
    q = dev.add_parameter(char(nm), 0, isTrigger = true);
    dev.put(q, 0);
end
sw = P.SoftwareModule;
p = sw.add_parameter('SoftA', 11); p.Value = 11;

rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;
rt.Interfaces = P.Interfaces;
end

function [bytes, fields, D] = localSession(scratch, tag, compact, nTrials)
% One short session through the real loop; returns what each trial adds to
% the journal (its growth from the first trial to the last, per trial, so
% the session's one-off header is not counted), the record's fields, and the
% records.
P = epsych.Protocol(Info = 'trial_record_loop');
dev = CountingProbeInterface(CoerceSingle = true);
P.addInterface(dev);
dev.add_parameter('Level', [10 20 30]);
p = dev.add_parameter('RespCode', 0, Type = 'Integer', Access = 'Read'); dev.put(p, uint32(1));
p = dev.add_parameter('Buf', 0, Type = 'Buffer', Access = 'Read', isArray = true); dev.put(p, single(1:20000));
tone = stimgen.Tone();
tone.Duration = 0.5;
tone.update_signal();
dev.add_parameter('Stim', {tone}, Type = 'StimType');
for nm = ["x_NewTrial_1" "x_ResetTrig_1" "x_TrialComplete_1"]
    q = dev.add_parameter(char(nm), 0, isTrigger = true);
    dev.put(q, 0);
end
P.compile();

CONFIG = struct('PROTOCOL', P, 'SUBJECT', struct('Name', 'RecSubj', 'BoxID', 1));
RUNTIME = epsych.Runtime;
RUNTIME.isTest = true;
RUNTIME.RecordBuffers = ~compact;
RUNTIME.RecordStimulusSettings = compact;
RUNTIME.TempDataDir = scratch;
RUNTIME.DefaultDataPath = scratch;
RUNTIME.SessionDataFilename = string(fullfile(scratch, sprintf('rec_%s.mat', tag)));
RUNTIME.EVENTS = epsych.EventHub;
RUNTIME.Interfaces = P.Interfaces;
set(RUNTIME.Interfaces, 'mode', hw.DeviceState.Preview);
RUNTIME = ep_TimerFcn_Start(RUNTIME, CONFIG);

journalFile = RUNTIME.Journal(1).FilePath;
assert(strlength(journalFile) > 0, 'the session has no journal');
afterFirst = 0;
for k = 1:nTrials
    RUNTIME.TRIALS(1).FORCE_TRIAL = true;
    RUNTIME = ep_TimerFcn_RunTime(RUNTIME);
    if k == 1
        afterFirst = dir(journalFile).bytes;
    end
end
D = RUNTIME.TRIALS(1).DATA;
fields = setdiff(fieldnames(D), {'Buf'});
bytes = (dir(journalFile).bytes - afterFirst) / (nTrials - 1);

RUNTIME = ep_TimerFcn_Stop(RUNTIME);
delete(RUNTIME);
end

function localRmdir(d)
try
    if isfolder(d), rmdir(d, 's'); end
catch
end
end
