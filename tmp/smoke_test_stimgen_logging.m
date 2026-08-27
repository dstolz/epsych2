function smoke_test_stimgen_logging
% smoke_test_stimgen_logging
% Verify the stimgen <-> EPsych logging seam.
%
% stimgen ships its own logger so it can run standalone. stimbridge.LogBridge
% makes it forward to granary instead, so one session produces one log. This test
% covers both halves of that: the forwarding path with a bridge installed, and
% the built-in fallback with none.
%
% The invariant that matters most is that nothing in the path throws -- stimgen
% logs from inside catch blocks, and an exception raised while reporting an
% exception destroys the report.
%
% The session logger's file sink is redirected to a scratch directory for the
% duration, so the repository .error_logs is untouched. The logger and the
% stimgen sink are both restored afterwards.
%
% Run headless: matlab -batch "addpath('c:\src\epsych2'); epsych_startup('c:\src\epsych2',false); run('c:\src\epsych2\tmp\smoke_test_stimgen_logging.m')"

global GVerbosity GLogVerbosity %#ok<GVMIS>
priorVerbosity = GVerbosity;
priorLogVerbosity = GLogVerbosity;
priorSink = stimgen.util.logSink();

scratch = fullfile(tempdir,sprintf('stimgen_logging_%d',feature('getpid')));
if isfolder(scratch), rmdir(scratch,'s'); end

cleanup = onCleanup(@() localCleanup(priorVerbosity,priorLogVerbosity,priorSink,scratch)); %#ok<NASGU>

GVerbosity = 3;
GLogVerbosity = Inf;

fprintf('\n=== smoke_test_stimgen_logging ===\n');

STIMGEN_LOGS = fullfile(tempdir,'stimgen_error_logs');

% 1. The standalone fallback -----------------------------------------------
% With no sink installed stimgen must behave exactly as it always has: a
% timestamped console line and a daily file under tempdir.
stimgen.util.logSink([]);
before = localStimgenBytes(STIMGEN_LOGS);
out = evalc('stimgen.util.vprintf(1,''fallback %d'',5)');
assert(contains(out,'fallback 5'),'the fallback must print to the console');
assert(localStimgenBytes(STIMGEN_LOGS) > before, ...
    'the fallback must append to the tempdir log');
fprintf('PASS: 1 the standalone fallback still logs to console and tempdir\n');

% 2. The contract shape -----------------------------------------------------
% A host receives (level, red, msg, args) with args a cell -- empty when the
% message is literal text.
localCapture('reset');
stimgen.util.logSink(stimgen.FcnLogSink(@(l,r,m,a) localCapture('add',l,r,m,a)));
stimgen.util.vprintf(2,'value %d',9);
rec = localCapture('get');
assert(numel(rec) == 1,'exactly one message must be delivered');
assert(rec(1).level == 2,'level must arrive unchanged');
assert(islogical(rec(1).red) && ~rec(1).red,'red must arrive as a logical false');
assert(iscell(rec(1).args) && isequal(rec(1).args,{9}),'args must be a cell of values');
localCapture('reset');
stimgen.util.vprintf(1,'literal text');
rec = localCapture('get');
assert(isempty(rec(1).args),'a message with no values must arrive with empty args');
fprintf('PASS: 2 the sink receives (level, red, msg, args)\n');

% 3. Red-flag parsing -------------------------------------------------------
% The old ~ischar test read a string scalar message as the red flag and then
% failed on it. All three shapes below must be read correctly.
localCapture('reset');
stimgen.util.vprintf(1,1,'explicitly red');
stimgen.util.vprintf(1,2,'red as a stray 2');
stimgen.util.vprintf(1,"a string message");
rec = localCapture('get');
assert(rec(1).red,'a numeric 1 must be read as the red flag');
assert(rec(2).red,'a numeric 2 must normalize to a red flag');
assert(~rec(3).red,'a string scalar message must NOT be read as the red flag');
assert(strcmp(char(rec(3).msg),'a string message'),'the string message must survive');
fprintf('PASS: 3 red-flag parsing survives the string-scalar case\n');

% 4. Exceptions are forwarded RAW -------------------------------------------
% Forwarding the object, rather than text stimgen already flattened, is what
% lets the host make ONE record out of it.
localCapture('reset');
try
    localThrow();
catch ME
    stimgen.util.vprintf(0,1,ME);
end
rec = localCapture('get');
assert(numel(rec) == 1,'an exception must produce exactly one delivery, not one per frame');
assert(isa(rec(1).msg,'MException'),'the exception must arrive unexpanded');
fprintf('PASS: 4 an exception is forwarded raw, as a single message\n');

% 5. Caller attribution through the real bridge -----------------------------
% Without the LogBridge marker in granary.callerFrame, every stimgen message is
% stamped with the bridge instead of its call site. This is the regression
% guard for that fix.
L = granary.Logger.instance('-reset');
L.removeSink(L.sinkOfType('granary.sink.FileSink'));
sink = granary.sink.TextFile(scratch);
L.addSink(sink);
stimgen.util.logSink(stimbridge.LogBridge());

stimgen.util.vprintf(1,'through the bridge');
L.flush();
txt = fileread(sink.Path);
assert(contains(txt,'through the bridge'),'the message must reach the session log');
assert(contains(txt,'smoke_test_stimgen_logging'), ...
    'the log must name the stimgen call site');
assert(~contains(txt,'LogBridge'), ...
    'the log must NOT be attributed to the bridge');
line = localLastLineWith(txt,'through the bridge');
assert(~contains(line,',vprintf,'), ...
    'the log must not be attributed to vprintf either');
fprintf('PASS: 5 messages are attributed to the stimgen call site\n');

% 6. One nested record per exception ----------------------------------------
before = localBytes(sink.Path);
try
    localThrow();
catch ME
    stimgen.util.vprintf(0,1,ME);
end
L.flush();
txt = fileread(sink.Path);
added = txt(before+1:end);
assert(contains(added,'smoke:probe'),'the identifier must be recorded');
assert(contains(added,'localThrow'),'the stack must be recorded');
assert(count(added,'smoke:probe') == 1, ...
    'the exception must be ONE record, not one per stack frame');
assert(contains(added,'    at '),'stack frames must be indented under the record');
fprintf('PASS: 6 an exception logs as one nested record\n');

% 7. No duplicate destination -----------------------------------------------
% While a bridge is installed stimgen must write nothing of its own; otherwise
% unifying the logs would simply have produced a third copy.
before = localStimgenBytes(STIMGEN_LOGS);
stimgen.util.vprintf(1,'must not reach tempdir');
stimgen.util.vprintf(0,1,'nor this one');
L.flush();
assert(localStimgenBytes(STIMGEN_LOGS) == before, ...
    'stimgen must not write its own log while a sink is installed');
fprintf('PASS: 7 nothing is written to the tempdir log while bridged\n');

% 8. Malformed calls degrade instead of throwing ----------------------------
% Every one of these has a real call site somewhere, or is one typo away.
stimgen.util.vprintf(1);
stimgen.util.vprintf(1,'%d %d',1);
stimgen.util.vprintf(1,struct('a',1));
stimgen.util.vprintf(1,'100% done and C:\new\tmp');
stimgen.util.vprintf('oops','bad level');
stimgen.util.logSink([]);
stimgen.util.vprintf(1);
stimgen.util.vprintf(1,'%d %d',1);
stimgen.util.vprintf('oops','bad level');
stimgen.util.logSink(stimbridge.LogBridge());
L.flush();
txt = fileread(sink.Path);
assert(contains(txt,'100% done and C:\new\tmp'), ...
    'a literal message must survive percent and backslash intact');
fprintf('PASS: 8 malformed calls degrade instead of throwing\n');

% 9. A broken sink is contained ---------------------------------------------
% It must not throw, must not silence stimgen, and must not latch logging off:
% latching is the host's job, and a mute logger is the one unacceptable outcome.
stimgen.util.logSink(stimgen.FcnLogSink(@(l,r,m,a) error('smoke:sink','sink is broken')));
before = localStimgenBytes(STIMGEN_LOGS);
evalc('stimgen.util.vprintf(1,''survives a broken sink'')');
assert(localStimgenBytes(STIMGEN_LOGS) > before, ...
    'a message must fall back to the built-in logger when the sink fails');
assert(~isempty(stimgen.util.logSink()), ...
    'a failing sink must stay installed rather than latching off');
stimgen.util.logSink(stimbridge.LogBridge());
fprintf('PASS: 9 a broken sink falls back without throwing or latching\n');

% 10. Gate delegation -------------------------------------------------------
% With the bridge installed, granary.isEnabled is the single reader of the
% verbosity globals for both code bases -- including the split between them, so
% a stimgen message the console is too quiet for still reaches the session log
% instead of being dropped by stimgen's own single-destination gate.
GVerbosity = 1;
GLogVerbosity = Inf;
assert(stimgen.util.isEnabled(1),'level 1 must be enabled at GVerbosity 1');
assert(stimgen.util.isEnabled(3),'the log wants level 3 even when the console does not');
beforeSession = localBytes(sink.Path);
beforeTemp = localStimgenBytes(STIMGEN_LOGS);
out = evalc('stimgen.util.vprintf(3,''console-suppressed but logged'')');
L.flush();
assert(isempty(strtrim(out)),'a message above GVerbosity must not print');
assert(localBytes(sink.Path) > beforeSession, ...
    'a console-suppressed stimgen message must still reach the session log');
assert(localStimgenBytes(STIMGEN_LOGS) == beforeTemp, ...
    'a forwarded message must never reach the tempdir log');

% Lowering the log level suppresses it in both code bases.
GLogVerbosity = 1;
assert(~stimgen.util.isEnabled(3),'level 3 must be suppressed once the log is capped too');
beforeSession = localBytes(sink.Path);
stimgen.util.vprintf(3,'suppressed');
L.flush();
assert(localBytes(sink.Path) == beforeSession, ...
    'a suppressed message must not reach the session log');
assert(localStimgenBytes(STIMGEN_LOGS) == beforeTemp, ...
    'a suppressed message must not reach the tempdir log either');

% A NaN GVerbosity used to make level > NaN false, so everything printed.
GVerbosity = NaN;
assert(~stimgen.util.isEnabled(3),'a NaN GVerbosity must be repaired, not open the floodgates');
GVerbosity = Inf;
assert(~stimgen.util.isEnabled(3),'an Inf GVerbosity must be repaired too');
GVerbosity = 3;
GLogVerbosity = Inf;
fprintf('PASS: 10 the gate is delegated, split by destination and hardened\n');

% 11. The install is idempotent ---------------------------------------------
% epsych_startup is routinely re-run; it must not discard a working bridge.
first = stimgen.util.logSink();
epsych_startup(epsych_path,false);
second = stimgen.util.logSink();
assert(isa(second,'stimbridge.LogBridge'),'startup must leave a bridge installed');
assert(first == second,'re-running startup must not replace a working bridge');

% epsych_startup rebuilt the logger, so redirect the fresh one back to scratch.
L = granary.Logger.instance();
L.removeSink(L.sinkOfType('granary.sink.FileSink'));
sink = granary.sink.TextFile(scratch);
L.addSink(sink);
fprintf('PASS: 11 installing the bridge is idempotent\n');

% 12. Self-test reports the seam --------------------------------------------
st = epsych.SelfTest();
r = st.run("Environment");
a6 = r(strcmp([r.id],"A6_StimgenLogging"));
assert(~isempty(a6),'the Environment group must report A6_StimgenLogging');
assert(strcmp(a6.status,"pass"),'A6 must pass while the bridge is installed');

% Simulate a stimgen pinned before the seam, or a "clear functions" that
% dropped the registry: the check must warn, never fail, and never take the
% other environment checks down with it.
stimgen.util.logSink([]);
r = st.run("Environment");
a6 = r(strcmp([r.id],"A6_StimgenLogging"));
assert(strcmp(a6.status,"warn"),'A6 must warn, not fail, when no bridge is installed');
others = r(~strcmp([r.id],"A6_StimgenLogging"));
assert(all(strcmp([others.status],"pass")), ...
    'the other environment checks must be unaffected');
stimgen.util.logSink(stimbridge.LogBridge());
fprintf('PASS: 12 self-test A6 reports the seam and degrades to a warning\n');

fprintf('\nAll smoke_test_stimgen_logging checks passed.\n');
end


% -----------------------------------------------------------------------
function localThrow()
error('smoke:probe','a probe failure at 100%% capacity');
end

% -----------------------------------------------------------------------
function out = localCapture(mode,level,red,msg,args)
% Accumulate what a sink was handed. A subfunction with a persistent rather
% than a closure, because an anonymous function cannot assign to its parent.
persistent recs
if isempty(recs)
    recs = struct('level',{},'red',{},'msg',{},'args',{});
end

out = [];
switch mode
    case 'reset'
        recs = struct('level',{},'red',{},'msg',{},'args',{});
    case 'add'
        recs(end+1) = struct('level',level,'red',red,'msg',msg,'args',{args});
    case 'get'
        out = recs;
end
end

% -----------------------------------------------------------------------
function n = localBytes(ffn)
n = 0;
d = dir(ffn);
if ~isempty(d), n = d(1).bytes; end
end

% -----------------------------------------------------------------------
function n = localStimgenBytes(d)
% Total bytes in stimgen's own log directory.
%
% The handle is closed first. MATLAB buffers writes and exposes no fflush, so
% without this a freshly written record has not reached disk yet -- which would
% make "the fallback wrote something" fail and, worse, make "the bridge wrote
% nothing" pass for the wrong reason.
try
    stimgen.util.vprintfFallback('-close');
catch
    % Nothing open; the byte count below is still correct.
end

n = 0;
f = dir(fullfile(d,'*.txt'));
for k = 1:numel(f)
    n = n + f(k).bytes;
end
end

% -----------------------------------------------------------------------
function s = localLastLineWith(txt,needle)
s = '';
lines = strsplit(txt,newline);
for k = numel(lines):-1:1
    if contains(lines{k},needle)
        s = lines{k};
        return
    end
end
end

% -----------------------------------------------------------------------
function localCleanup(priorVerbosity,priorLogVerbosity,priorSink,scratch)
global GVerbosity GLogVerbosity %#ok<GVMIS>
GVerbosity = priorVerbosity;
GLogVerbosity = priorLogVerbosity;

% Put the stimgen registry back the way it was found, then rebuild the session
% logger against the real log directory.
try
    if isempty(priorSink) || ~isvalid(priorSink)
        stimgen.util.logSink([]);
    else
        stimgen.util.logSink(priorSink);
    end
catch
    stimgen.util.logSink([]);
end

granary.Logger.instance('-reset');

if isfolder(scratch)
    try
        rmdir(scratch,'s');
    catch
        % A handle may still be open; the scratch directory is disposable.
    end
end
end
