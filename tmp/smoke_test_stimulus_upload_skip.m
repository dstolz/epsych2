function smoke_test_stimulus_upload_skip
% smoke_test_stimulus_upload_skip
% A 'StimType' parameter regenerates its stimulus on every write and used to
% upload the whole waveform every time, changed or not -- on every trial, in
% the trial boundary. hw.Interface.SkipUnchangedStimulus leaves the transfer
% out when the tag was last uploaded the same samples. The risk in that is a
% device that no longer holds what the host believes it does, so most of this
% is about when the backend FORGETS.
%
% Runs hw.TDT_Synapse over tmp/SynapseAPI_Mock, which records every
% setParameterValues call. hw.TDT_RPcox shares the bookkeeping
% (hw.Interface.stimulusOnDevice_ and friends) and is checked on a device.
%
% Verifies:
%   1) the first write uploads; an identical second write does not, and
%      still reports success
%   2) a changed stimulus uploads, and so does changing it back (only the
%      LAST upload is remembered, which is what the buffer holds)
%   3) samples decide, not the object: another stimulus that generates the
%      same waveform is not uploaded
%   4) SkipUnchangedStimulus = false uploads every time
%   5) a mode change forgets; so does a reconnect
%   6) any other write to the tag forgets
%   7) a transfer the device refused forgets
%   8) the same holds through hw.Parameter.Value inside a trial dispatch
%
% No hardware, no windows.
%
%   matlab -batch "run('tmp/smoke_test_stimulus_upload_skip.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(here);

fprintf('\n=== smoke_test_stimulus_upload_skip ===\n');

api = SynapseAPI_Mock();
I = TDT_Synapse_Mock(api, Connect = true);
Ps = I.find_parameter('Stim');
Ps.Type = 'StimType';   % as the protocol's author would
GIZMO = 'RZ6(1)';

tone = stimgen.Tone();
tone.Duration = 0.05;
assert(I.SkipUnchangedStimulus, 'skipping an unchanged upload is the default');

% --- 1. first write uploads, an identical one does not -----------------------
api.clearLog();
ok = I.set_parameter(Ps, tone);
assert(ok && localUploads(api) == 1, 'the first write must upload');
held = api.value(GIZMO, 'Stim');
assert(isequal(held(1:tone.N), reshape(tone.Signal, 1, [])), 'the signal is in the buffer');
assert(I.StimulusUploads == 1 && I.StimulusUploadsSkipped == 0, 'counters after the first upload');

ok = I.set_parameter(Ps, tone);
assert(ok, 'a write that found the samples already there is a success');
assert(localUploads(api) == 1, 'an identical second write must not transfer');
assert(I.StimulusUploads == 1 && I.StimulusUploadsSkipped == 1, 'the skip is counted');
fprintf('PASS: 1 the first write uploads; an identical one is left out\n');

% --- 2. a changed stimulus uploads, and so does changing it back -------------
tone.Frequency = 2000;
I.set_parameter(Ps, tone);
assert(localUploads(api) == 2, 'a changed stimulus must upload');
held = api.value(GIZMO, 'Stim');
assert(isequal(held(1:tone.N), reshape(tone.Signal, 1, [])), 'the new signal is in the buffer');
tone.Frequency = 1000;
I.set_parameter(Ps, tone);
assert(localUploads(api) == 3, 'changing it back uploads again: only the last upload is remembered');
I.set_parameter(Ps, tone);
assert(localUploads(api) == 3, 'and then it is unchanged again');
fprintf('PASS: 2 a changed stimulus uploads, in either direction\n');

% --- 3. samples decide, not the object ---------------------------------------
twin = stimgen.Tone();
twin.Duration = 0.05;
twin.Frequency = 1000;
I.set_parameter(Ps, twin);
assert(localUploads(api) == 3, 'another object generating the same samples is not uploaded');
shorter = stimgen.Tone();
shorter.Duration = 0.02;
I.set_parameter(Ps, shorter);
assert(localUploads(api) == 4, 'a shorter stimulus is different samples');
fprintf('PASS: 3 the comparison is of samples\n');

% --- 4. the opt-out ----------------------------------------------------------
I.SkipUnchangedStimulus = false;
n0 = localUploads(api);
I.set_parameter(Ps, shorter);
I.set_parameter(Ps, shorter);
assert(localUploads(api) == n0 + 2, 'with skipping off every write transfers');
I.SkipUnchangedStimulus = true;
I.set_parameter(Ps, shorter);
assert(localUploads(api) == n0 + 2, 'switched back on, it starts from what was last sent');
fprintf('PASS: 4 SkipUnchangedStimulus = false uploads every time\n');

% --- 5. a mode change forgets; so does a reconnect ---------------------------
n0 = localUploads(api);
I.mode = hw.DeviceState.Preview;
I.set_parameter(Ps, shorter);
assert(localUploads(api) == n0 + 1, 'after a mode change the next write is a real one');
I.set_parameter(Ps, shorter);
assert(localUploads(api) == n0 + 1, 'and then unchanged again');

I.disconnect();
I.connect();
Ps = I.find_parameter('Stim');
Ps.Type = 'StimType';
n0 = localUploads(api);
I.set_parameter(Ps, shorter);
assert(localUploads(api) == n0 + 1, 'after a reconnect the next write is a real one');
fprintf('PASS: 5 a mode change and a reconnect forget what was sent\n');

% --- 6. any other write to the tag forgets -----------------------------------
n0 = localUploads(api);
Ps.Type = 'Buffer';                             % the same tag, written as raw samples
I.set_parameter(Ps, {zeros(1, 16)});
Ps.Type = 'StimType';
assert(localUploads(api) == n0 + 1, 'the raw write itself goes out');
I.set_parameter(Ps, shorter);
assert(localUploads(api) == n0 + 2, 'the stimulus is uploaded again over a raw write');
held = api.value(GIZMO, 'Stim');
assert(isequal(held(1:shorter.N), reshape(shorter.Signal, 1, [])), 'and the buffer holds it');
fprintf('PASS: 6 another write to the tag forgets\n');

% --- 7. a refused transfer forgets -------------------------------------------
other = stimgen.Tone();
other.Duration = 0.03;
other.Frequency = 3000;
modeWas = api.Mode;
api.Mode = 0;                                   % the device dropped to Idle on its own
ok = I.set_parameter(Ps, other);
api.Mode = modeWas;
assert(~ok, 'the refused transfer is reported');
n0 = localUploads(api);
ok = I.set_parameter(Ps, other);
assert(ok && localUploads(api) == n0 + 1, 'a stimulus whose transfer failed is sent again');
fprintf('PASS: 7 a refused transfer is not remembered as sent\n');

% --- 8. through hw.Parameter.Value, as the dispatcher writes it --------------
n0 = localUploads(api);
skipped0 = I.StimulusUploadsSkipped;
I.InDispatch = true;
restore = onCleanup(@() localEndDispatch(I));
Ps.Value = other;
Ps.Value = other;
other.Frequency = 3500;
Ps.Value = other;
clear restore
assert(localUploads(api) == n0 + 1, 'in a dispatch: two unchanged writes skipped, the changed one sent');
assert(I.StimulusUploadsSkipped == skipped0 + 2, 'both skips counted');
assert(isequal(Ps.Value, other), 'the parameter still holds the stimulus object');
fprintf('PASS: 8 the same through hw.Parameter.Value inside a dispatch\n');

I.disconnect();
fprintf('smoke_test_stimulus_upload_skip: ALL PASS\n');
end


function n = localUploads(api)
n = api.callCount('setParameterValues');
end

function localEndDispatch(I)
if isvalid(I), I.InDispatch = false; end
end
