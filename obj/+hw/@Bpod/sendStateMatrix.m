function sendStateMatrix(obj, sma)
% sendStateMatrix(obj, sma)
% Validate, permute, encode and upload a state matrix to the device.
%
% ============================================================================
% VERIFICATION STATUS: TRANSCRIBED, NOT YET VERIFIED AGAINST A REAL DEVICE.
%
% The validation, the manifest permutation below, and the byte encoder in
% compileMatrix_ are a line-by-line transcription of Bpod's
% Functions/SendStateMatrix.m. They have NOT been compared against the output
% of that function on a real rig, and they cannot be: the original reads
% `BpodSystem.InputsEnabled` (a GUI-backed struct loaded from
% Settings Files/BpodInputConfig.mat) and ends by writing
% `BpodSystem.GUIHandles.CxnDisplay`, so it cannot be executed without
% starting the Bpod console. Running it is exactly what this backend exists
% to avoid.
%
% This matters more than a usual "untested" note, because a wrong matrix is
% not a loud failure. The firmware performs no validation of the 'P' payload:
% it reads nStates*40 + nStates*17 + nStates*5 + nStates*5 + 5 + 12 bytes and
% then 4*(nStates+10) more, and runs whatever that decodes to. A single
% off-by-one in the base-0 conversion, the transpose, or the nStates+1 exit
% substitution yields a matrix the device accepts and runs WRONGLY, with no
% error anywhere and no way to tell from the event stream.
%
% THE CHECK THAT CLOSES THIS GAP: on a rig with the Bpod GUI running, build a
% representative sma (several states, forward references, an 'exit', a global
% timer, a global counter, a Valve and an LED output), capture the byte
% string Bpod's own SendStateMatrix hands to BpodSerialWrite, and compare it
% against obj.compileMatrix_ for the same matrix. compileMatrix_ is kept pure
% precisely so that comparison is a one-liner. One capture, once, is enough.
% ============================================================================
%
% What this method does, in order:
%   1. Rejects an empty matrix, a matrix with undefined states, and a matrix
%      over hw.Bpod.MAX_STATES.
%   2. Permutes every matrix into MANIFEST (add) order and remaps transition
%      targets to match. This is the ordering the device's event stream
%      indexes, which is why obj.StateNames is written from it.
%   3. Substitutes nStates+1 for NaN ('exit') targets.
%   4. Encodes via compileMatrix_ and, unless the payload is byte-identical
%      to the one already on the device, writes 'P' + payload and collects the
%      one-byte acknowledgement.
%
% The acknowledgement read is the ONLY blocking call in this backend. It is
% bounded by obj.Timeout and reports a warning rather than hanging, because a
% hang here would freeze the session inside a timer callback.
%
% Parameters
%   sma - State matrix from newStateMatrix, populated with addState.
%
% See also: hw.Bpod.compileMatrix_, hw.Bpod.newStateMatrix, hw.Bpod.addState,
%           documentation/hw/hw_Bpod.md

arguments
    obj
    sma (1,1) struct
end

nStates = length(sma.StateNames);

%% Check to make sure the Placeholder state was replaced
if strcmp(sma.StateNames{1}, 'Placeholder')
    error('hw:Bpod:EmptyMatrix', ...
        'Could not send an empty matrix. You must define at least one state first.');
end

%% Check to make sure the State Matrix doesn't have undefined states
if sum(sma.StatesDefined == 0) > 0
    undefined = sma.StateNames(sma.StatesDefined == 0);
    vprintf(0, 1, ['Bpod: the state matrix contains references to undefined ' ...
        'states: %s'], strjoin(undefined, ', '));
    error('hw:Bpod:UndefinedStates', ...
        'Define these states with addState before sending: %s', strjoin(undefined, ', '));
end

%% Check to make sure the state matrix does not exceed the firmware's ceiling
if nStates > obj.MAX_STATES
    error('hw:Bpod:TooManyStates', ...
        'The state matrix can have a maximum of %d states.', obj.MAX_STATES);
end

%% Rearrange states to reflect order they were added (not referenced)
% Every index in the event stream refers to the result of this permutation.
% The three transition matrices are remapped IN PLACE against snapshots of
% their originals, then the rows themselves are permuted: doing both against
% the same live array would remap values written by an earlier iteration.
sma.Manifest = sma.Manifest(1:sma.nStatesInManifest);
StateOrder = zeros(1, sma.nStatesInManifest);
OriginalInputMatrix = sma.InputMatrix;
OriginalTimerMatrix = sma.GlobalTimerMatrix;
OriginalCounterMatrix = sma.GlobalCounterMatrix;
for i = 1:sma.nStatesInManifest
    StateOrder(i) = find(strcmp(sma.StateNames, sma.Manifest{i}));
    sma.InputMatrix(OriginalInputMatrix == StateOrder(i)) = i;
    sma.GlobalTimerMatrix(OriginalTimerMatrix == StateOrder(i)) = i;
    sma.GlobalCounterMatrix(OriginalCounterMatrix == StateOrder(i)) = i;
end
sma.InputMatrix = sma.InputMatrix(StateOrder,:);
sma.OutputMatrix = sma.OutputMatrix(StateOrder,:);
sma.GlobalTimerMatrix = sma.GlobalTimerMatrix(StateOrder,:);
sma.GlobalCounterMatrix = sma.GlobalCounterMatrix(StateOrder,:);
sma.StateNames = sma.StateNames(StateOrder);
sma.StateTimers = sma.StateTimers(StateOrder);

%% Add exit state codes to transition matrices
% nStates+1 here becomes nStates after compileMatrix_ subtracts 1, and the
% firmware ends the matrix when NewState == nStates
% (Bpod_MainModule_0_6.ino:487).
sma.InputMatrix(isnan(sma.InputMatrix)) = nStates + 1;
sma.GlobalTimerMatrix(isnan(sma.GlobalTimerMatrix)) = nStates + 1;
sma.GlobalCounterMatrix(isnan(sma.GlobalCounterMatrix)) = nStates + 1;

% nStates is captured BEFORE the permutation upstream; carry it on the struct
% so compileMatrix_ can stay pure (its signature takes only obj).
sma.nStates = nStates;

%% Publish the permuted matrix
% Written before the memo check: two different matrices can compile to the
% same payload while carrying different state names, and a stale StateNames
% would mislabel every state in the saved data.
obj.lastMatrix_ = sma;
obj.StateNames = sma.StateNames;

payload = obj.compileMatrix_();

%% Memo: an unchanged matrix reduces trial start to a single 'R' byte
if ~isempty(obj.lastPayload_) && isequal(payload, obj.lastPayload_)
    vprintf(3, 'Bpod: state matrix unchanged (%d states); skipping upload', nStates);
    return
end

% From here the device is no longer known to hold a matrix we can name. Clear
% the memo first so that an upload which fails part way cannot leave a later
% identical call believing the device is already programmed.
obj.lastPayload_ = uint8([]);

if obj.matrixRunning_ || obj.awaitingEpilogue_
    % 'P' is accepted mid-run by the firmware, and the ack byte would arrive
    % interleaved with the push stream's framed messages, desynchronising the
    % parser for the rest of the trial. Abort first.
    error('hw:Bpod:UploadWhileRunning', ...
        ['Cannot upload a state matrix while a matrix is running or its ' ...
         'epilogue is outstanding. Call abortMatrix first.']);
end

if ~obj.IsConnected
    vprintf(0, 1, ['Bpod: not connected; the %d-state matrix was compiled ' ...
        'but not uploaded'], nStates);
    return
end

% Let the pump consume anything the device left in the OS buffer, so the byte
% read back below is this upload's acknowledgement and not a leftover.
obj.pump();

% Cast the opcode separately: mixing char and uint8 in one concatenation is
% a class-promotion trap, and this buffer must be uint8 end to end.
obj.write_([uint8('P'), payload]);

ack = uint8([]);
try
    ack = obj.readExactly_(1, obj.Timeout);
catch ME
    vprintf(0, 1, ME);
end

if isempty(ack)
    vprintf(0, 1, ['Bpod: no acknowledgement of the %d-state matrix within %g s. ' ...
        'The device may hold a partial matrix; it will be re-sent on the next ' ...
        'trial. Check the cable and the firmware build.'], nStates, obj.Timeout);
    return
end

if ack(1) ~= 1
    vprintf(0, 1, ['Bpod: unexpected acknowledgement %d after uploading the ' ...
        '%d-state matrix (expected 1). Treating the upload as failed.'], ...
        ack(1), nStates);
    return
end

obj.lastPayload_ = payload;

vprintf(2, 'Bpod: uploaded a %d-state matrix (%d payload bytes)', ...
    nStates, numel(payload));
end
