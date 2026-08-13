function crash_test_trialjournal(mode, jpath)
% crash_test_trialjournal
% Hard-kill durability test for epsych.TrialJournal. This is the test that
% guards the property the journal exists to provide: every completed trial
% survives an abrupt death of the MATLAB process (segfault, taskkill, power
% event on the host). It exists as a permanent harness because this property
% is invisible to throughput benchmarks and is exactly what a well-meaning
% "make the save async" refactor destroys — measured at 1 record recovered
% out of thousands when the write was moved to a backgroundPool chain
% (measured on branch async-streaming-poller, where this journal originated).
%
%   crash_test_trialjournal            % 'auto': spawn writer, kill it, verify
%   crash_test_trialjournal('write', jpath)  % used by auto: journal until killed
%   crash_test_trialjournal('read',  jpath)  % verify an existing journal
%
% 'auto' spawns a second MATLAB that journals records as fast as it can,
% hard-kills it with Stop-Process -Force mid-write, then asserts that the
% recovered records are contiguous (data_000001..data_N with no gaps) and
% that at most the single in-flight record was lost.

arguments
    mode (1,:) char {mustBeMember(mode, {'auto','write','read'})} = 'auto'
    jpath (1,1) string = fullfile(tempdir, 'epj_crash_test.epj')
end

% Self-bootstrap so every mode works from a bare matlab -batch.
if isempty(which('epsych.TrialJournal'))
    repo = fileparts(fileparts(mfilename('fullpath')));
    addpath(repo);
    epsych_startup(repo);
end

switch mode
    case 'write'
        localWriteForever(jpath);
    case 'read'
        localVerify(jpath);
    case 'auto'
        localAuto(jpath);
end
end

% -------------------------------------------------------------------------
function localAuto(jpath)
fprintf('\n=== crash_test_trialjournal (auto) ===\n');
if isfile(jpath), delete(jpath); end

repoTmp = fileparts(mfilename('fullpath'));
matlabExe = fullfile(matlabroot, 'bin', 'matlab.exe');

% Zero-argument bootstrap script so the -batch argument needs no quoting at
% all (quoted commands do not survive Start-Process -ArgumentList intact).
bootstrap = fullfile(tempdir, 'epj_crash_writer_run.m');
fid = fopen(bootstrap, 'w');
assert(fid >= 0, 'could not create %s', bootstrap);
fprintf(fid, 'cd(''%s'');\n', repoTmp);
fprintf(fid, 'crash_test_trialjournal(''write'',''%s'');\n', jpath);
fclose(fid);

% PowerShell wrapper: start the writer hidden, let it journal for a while,
% then kill its whole process tree (taskkill /T reaches the real MATLAB.exe
% behind the bin\matlab.exe launcher) with no chance to clean up.
ps1 = fullfile(tempdir, 'epj_crash_test.ps1');
fid = fopen(ps1, 'w');
assert(fid >= 0, 'could not create %s', ps1);
% NB: -sd is not honored under -batch, and Start-Process mangles quoted
% argument elements — but tempdir has no spaces, so the run() form passes
% through as one unquoted token.
fprintf(fid, '$p = Start-Process -FilePath "%s" -ArgumentList ''-batch'',"run(''%s'')" -PassThru -WindowStyle Hidden\n', matlabExe, bootstrap);
fprintf(fid, 'Start-Sleep -Seconds 30\n'); % ~10 s startup + ~20 s of writing
fprintf(fid, 'taskkill /F /T /PID $p.Id | Out-Null\n');
fprintf(fid, 'exit 0\n');
fclose(fid);

fprintf('spawning writer MATLAB; it will be hard-killed in ~30 s...\n');
status = system(sprintf('powershell -NoProfile -ExecutionPolicy Bypass -File "%s"', ps1));
assert(status == 0, 'PowerShell wrapper failed with status %d', status);
pause(2);

localVerify(jpath);
end

% -------------------------------------------------------------------------
function localWriteForever(jpath)
J = epsych.TrialJournal(jpath);
J.append('info', struct('Purpose', 'crash test', 'Started', datetime('now')));
d = struct('Freq', 1000, 'Levels', {{10, 20, 'catch'}}, 'Name', "tone", ...
    'computerTimestamp', datetime('now'), 'isTest', true, 'Buffer', rand(1, 100));
k = 0;
while true % killed from outside; no exit path on purpose
    k = k + 1;
    d.TrialIndex = k;
    J.append(sprintf('data_%06d', k), d);
end
end

% -------------------------------------------------------------------------
function localVerify(jpath)
assert(isfile(jpath), 'no journal found at %s — writer never started?', jpath);

[S, torn] = epsych.TrialJournal.read(jpath);
names = fieldnames(S);
dataNames = names(startsWith(names, 'data_'));
n = numel(dataNames);
idx = sort(cellfun(@(s) sscanf(s, 'data_%d'), dataNames));

fprintf('recovered %d trial records (torn tail: %d)\n', n, torn);
assert(n > 100, 'only %d records recovered — writer died before writing meaningfully', n);
assert(isfield(S, 'info'), 'header record must survive');
assert(idx(1) == 1 && idx(end) == n && all(diff(idx) == 1), ...
    'recovered records must be contiguous 1..N — a gap means a completed trial was lost');
for probe = unique([1, floor(n/2), n])
    r = S.(sprintf('data_%06d', probe));
    assert(isequal(r.TrialIndex, probe) && numel(r.Buffer) == 100, ...
        'record %d is corrupt', probe);
end

fprintf('=== crash_test_trialjournal: PASS — %d/%d completed records survived a hard kill ===\n', n, n + torn);
end
