function smoke_test_eplog
% smoke_test_eplog
% Fitness and reliability tests for the +eplog logging package.
%
% Covers every defect the package was built to fix, plus the invariant that
% matters most: nothing in the logger may throw, because EPsych logs from
% inside catch blocks and an exception raised while reporting an exception
% destroys the report.
%
% Writes only to a scratch directory; the repository .error_logs is untouched.
%
% Run headless: matlab -batch "addpath('c:\src\epsych2'); epsych_startup('c:\src\epsych2'); run('c:\src\epsych2\tmp\smoke_test_eplog.m')"

global GVerbosity %#ok<GVMIS>
priorVerbosity = GVerbosity;
cleanupVerbosity = onCleanup(@() localRestore(priorVerbosity));
GVerbosity = 3;

scratch = fullfile(tempdir,sprintf('eplog_smoke_%d',feature('getpid')));
if isfolder(scratch), rmdir(scratch,'s'); end
cleanupScratch = onCleanup(@() localRmdir(scratch)); %#ok<NASGU>

fprintf('\n=== smoke_test_eplog ===\n');

% 1. Format policy --------------------------------------------------------
% With values the message is a printf format string, as documented.
assert(isequal(eplog.format('  [ERROR] %s\nx',{'boom'}), ...
    ['  [ERROR] boom' newline 'x']), 'format string path broken');
assert(isequal(eplog.format('%d of %d',{3,7}),'3 of 7'),'numeric conversion broken');
fprintf('PASS: 1 the with-values path is a printf format string\n');

% 2. The no-values path is literal ----------------------------------------
% This is what protects the ~10 sites that pass a message built at runtime:
% ME.message, ffmpeg output, and data paths. Interpreting those would turn
% 'C:\new\tmp' into a newline and a tab, and eat '%' as a conversion.
assert(isequal(eplog.format('100% done',{}),'100% done'), ...
    'a stray percent must survive');
assert(isequal(eplog.format('50% complete, 3% left',{}),'50% complete, 3% left'), ...
    'the "%% c" conversion trap must not fire');
winPath = 'C:\new\tmp\file_%s_%d.mat';
assert(isequal(eplog.format(winPath,{}),winPath), ...
    'a Windows path must survive byte-for-byte on the no-values path');
assert(isequal(eplog.format('ffmpeg: 90% at frame\rate',{}),'ffmpeg: 90% at frame\rate'), ...
    'runtime tool output must not be reinterpreted');
fprintf('PASS: 2 the no-values path is literal, so paths and percents survive\n');

% 3. Trailing newlines are stripped ---------------------------------------
% 20+ call sites append \n against convention, which produced the blank lines
% visible in the shipped .error_logs.
assert(isequal(eplog.format('Configuration saved as: %s\n',{'a.ecfg'}), ...
    'Configuration saved as: a.ecfg'),'trailing newline must be stripped');
assert(isequal(eplog.format('a%s\n\n',{'b'}),'ab'), ...
    'repeated trailing newlines must be stripped');
assert(isequal(eplog.format(['x' newline newline],{}),'x'), ...
    'real trailing newlines must be stripped on the literal path too');
assert(isequal(eplog.format(['keep' newline 'interior'],{}),['keep' newline 'interior']), ...
    'interior newlines must be preserved');
fprintf('PASS: 3 trailing newlines stripped, interior preserved\n');

% 4. string messages -------------------------------------------------------
% The old parser read a string message as the red flag and then threw on
% "if red".
assert(isequal(eplog.format("plain string",{}),'plain string'), ...
    'string scalar message must work');
assert(isequal(eplog.format("Box %d ready",{3}),'Box 3 ready'), ...
    'string format with values must work');
assert(ischar(eplog.format(string(missing),{})),'missing string must not throw');
fprintf('PASS: 4 string messages format correctly\n');

% 5. A bad format string never throws --------------------------------------
bad = eplog.format('%d %d %s',{'only-one'});
assert(ischar(bad) && ~isempty(bad),'bad format must degrade, not throw');
assert(ischar(eplog.format(struct('a',1),{})),'unprintable message must not throw');
assert(ischar(eplog.format({1,2,3},{})),'cell message must not throw');
fprintf('PASS: 5 malformed input degrades instead of throwing\n');

% 6. Level labels ----------------------------------------------------------
assert(double(eplog.Level.Debug)==2,'Level values must match the numeric levels in use');
assert(eplog.Level.label(-1)=="LogOnly");
assert(eplog.Level.label(4)=="Trace");
assert(eplog.Level.label(9)=="L9",'levels without a member must still label');
assert(eplog.Level.label(NaN)=="L?",'label must never throw');
fprintf('PASS: 6 level labels cover named, unnamed and invalid values\n');

% 7. Verbosity gating, including the values that broke the old compare -----
GVerbosity = 1;
assert(eplog.isEnabled(0) && eplog.isEnabled(1),'levels at or below must pass');
assert(~eplog.isEnabled(2),'levels above must be suppressed');
GVerbosity = NaN;
assert(~eplog.isEnabled(3),'NaN previously let EVERY message through');
assert(GVerbosity==1,'NaN must be repaired to the documented default');
GVerbosity = [0 3];
assert(~eplog.isEnabled(3),'a non-scalar global previously suppressed nothing');
GVerbosity = [];
assert(eplog.isEnabled(1) && GVerbosity==1,'empty must reset to 1');
GVerbosity = 3;
assert(eplog.isEnabled('oops'),'a malformed level must stay loud, not vanish');
fprintf('PASS: 7 gating handles NaN, non-scalar, empty and bad levels\n');

% 8. Caller attribution ----------------------------------------------------
% The old logger hardcoded dbstack frame 3.
[n1,l1] = localDirectCaller();
assert(contains(n1,'localDirectCaller'), ...
    sprintf('direct caller misattributed as "%s"',n1));
assert(l1 > 0,'line number must be recorded');

% Mirrors the real pattern at Runtime/find_parameter.m, where the call sits
% inside a cellfun body. The old fixed frame index resolved that to the wrong
% function entirely.
f = @() localDirectCaller();
[n2,l2,f2] = f();
assert(endsWith(f2,'smoke_test_eplog.m'), ...
    sprintf('anonymous-function caller resolved to the wrong file: %s',f2));
assert(contains(n2,'localDirectCaller') && l2 > 0, ...
    sprintf('anonymous-function caller misattributed as "%s"',n2));

% Extra depth must not shift the answer: the immediate caller is reported.
[n3,~,f3] = localNestedCaller();
assert(endsWith(f3,'smoke_test_eplog.m') && contains(n3,'localDirectCaller'), ...
    sprintf('nested caller misattributed as "%s"',n3));
fprintf('PASS: 8 caller attribution survives depth and anonymous functions\n');

% 8b. Timestamp and date helpers ------------------------------------------
% These replace datestr/datetime formatting on the hot path, so they have to
% agree with it exactly -- the daily filename in particular is hardcoded by
% RunExpt's log menu and by SelfTest check A4.
c = clock; %#ok<CLOCK>
assert(strcmp(eplog.stamp(c),datestr(datenum(c),'HH:MM:SS.FFF')), ...
    'stamp must match the datestr rendering it replaces');
assert(strcmp(eplog.dateTag(c),datestr(datenum(c),'ddmmmyyyy')), ...
    'dateTag must match the daily filename pattern');
assert(strcmp(eplog.stamp([2026 8 9 0 0 0]),'00:00:00.000'),'midnight');
assert(strcmp(eplog.stamp([2026 8 9 23 59 59.999]),'23:59:59.999'),'end of day');
assert(strcmp(eplog.stamp([2026 8 9 12 5 9.9996]),'12:05:10.000'), ...
    'sub-millisecond rounding must carry into seconds');
assert(strcmp(eplog.stamp([2026 8 9 12 5 59.9996]),'12:05:59.999'), ...
    'rounding at the end of a minute must not produce ":60"');
assert(strcmp(eplog.dateTag([2026 1 1 0 0 0]),'01Jan2026'),'new year');
assert(strcmp(eplog.dateTag([2026 12 31 0 0 0]),'31Dec2026'),'year end');
fprintf('PASS: 8b stamp and dateTag agree with the formatters they replace\n');

% 9. Text sink line shape and multi-line indent ----------------------------
tf = eplog.sink.TextFile(scratch);
L  = eplog.Logger({tf});
L.emit(1,false,'hello %s',{'world'});
L.flush();
logPath = tf.Path;
assert(isfile(logPath),'the sink must create its file');
txt = fileread(logPath);
assert(contains(txt,'smoke_test_eplog'),'log line must name the calling function');
assert(contains(txt,': hello world'),'log line must carry the formatted text');
assert(count(txt,newline)==1,'a single-line record must occupy exactly one line');
fprintf('PASS: 9 text sink writes the established line shape\n');

% 10. Exception records: one entry, attributed to the catch site -----------
try
    localThrow();
catch ME
    L.emit(0,true,ME);
end
L.flush();
txt = fileread(logPath);
lines = strsplit(strtrim(txt),newline);
head = lines{2};
assert(contains(head,'smoke_test_eplog'), ...
    sprintf('exception must be stamped with the catch site, got: %s',head));
assert(~contains(head,'vprintf') && ~contains(head,'callerFrame'), ...
    'exception must not be attributed to the logger');
assert(contains(txt,'epsych:smoke:deliberate'),'identifier must be logged');
assert(contains(txt,'    at localThrow'),'stack frames must be indented under the record');
fprintf('PASS: 10 exceptions log as one record at the catch site\n');

% 11. Percent inside an exception message ---------------------------------
try
    error('epsych:smoke:pct','failed at 90%% on C:\\new\\path');
catch ME2
    L.emit(0,true,ME2);
end
L.flush();
txt = fileread(logPath);
assert(contains(txt,'90%'),'exception text must keep its percent sign');
assert(contains(txt,'C:\new\path'),'exception text must keep its backslashes');
fprintf('PASS: 11 exception text is never treated as a format string\n');

% 12. lasterror-style struct ----------------------------------------------
% ep_TimerFcn_Error passes RUNTIME.ERROR, a struct, which used to throw
% inside the error handler.
errStruct = struct('message','struct failure','identifier','epsych:smoke:struct', ...
    'stack',struct('file','f.m','name','fname','line',7));
L.emit(0,true,errStruct);
L.flush();
txt = fileread(logPath);
assert(contains(txt,'epsych:smoke:struct') && contains(txt,'struct failure'), ...
    'a lasterror-style struct must log rather than throw');
% A MATLAB timer's ErrorFcn event data names the field messageID instead.
timerData = struct('message','timer callback failed', ...
    'messageID','epsych:smoke:timer', ...
    'stack',struct('file','t.m','name','tfcn','line',3));
L.emit(0,true,timerData);
L.flush();
txt = fileread(logPath);
assert(contains(txt,'epsych:smoke:timer'), ...
    'timer event data must log its identifier from messageID');
fprintf('PASS: 12 lasterror and timer-event structs log without throwing\n');

% 13. Nested causes --------------------------------------------------------
inner = MException('epsych:smoke:inner','the real reason');
outer = MException('epsych:smoke:outer','the wrapper');
outer = addCause(outer,inner);
L.emit(0,true,outer);
L.flush();
txt = fileread(logPath);
assert(contains(txt,'caused by') && contains(txt,'the real reason'), ...
    'exception causes must be logged');
fprintf('PASS: 13 exception causes are preserved\n');

% 14. Console honours log-only and the red stream -------------------------
cs = eplog.sink.Console();
LC = eplog.Logger({cs});
out = evalc('LC.emit(-1,false,''must not appear'')');
assert(~contains(out,'must not appear'),'level -1 must never reach the console');
out = evalc('LC.emit(1,false,''visible message'')');
assert(contains(out,'visible message'),'a normal message must reach the console');
assert(~isempty(regexp(out,'^\d\d:\d\d:\d\d\.\d\d\d: ','once')), ...
    'console timestamp shape changed');
fprintf('PASS: 14 console suppresses log-only and keeps the timestamp shape\n');

% 15. Structured sink round-trips -----------------------------------------
js = eplog.sink.JsonLines(scratch);
LJ = eplog.Logger({js});
LJ.emit(2,true,'structured %d',{7});
try
    error('epsych:smoke:json','json path');
catch ME3
    LJ.emit(0,true,ME3);
end
LJ.flush();
jl = strsplit(strtrim(fileread(js.Path)),newline);
r1 = jsondecode(jl{1});
assert(r1.level==2 && r1.red && strcmp(r1.message,'structured 7'), ...
    'structured record fields are wrong');
assert(strcmp(r1.levelName,'Debug'),'level name must be carried');
assert(contains(r1.caller,'smoke_test_eplog'),'structured caller is wrong');
r2 = jsondecode(jl{2});
assert(strcmp(r2.identifier,'epsych:smoke:json'),'identifier must reach the structured log');
assert(~isempty(r2.stack),'stack must reach the structured log');
fprintf('PASS: 15 JSON Lines sink round-trips through jsondecode\n');

% 16. Open failure latches instead of retrying forever ---------------------
% The old code retried epsych_path + isfolder + mkdir + fopen on every call.
badDir = fullfile(scratch,'nul','deeper');   % 'nul' is a reserved device on Windows
bs = eplog.sink.TextFile(badDir);
LB = eplog.Logger({bs});
warnOut = evalc('LB.emit(1,false,''first attempt'')');
if bs.Failed
    assert(contains(warnOut,'file logging disabled'),'the failure must be reported once');
    quietOut = evalc('LB.emit(1,false,''second attempt'')');
    assert(isempty(strtrim(quietOut)),'a latched failure must stay silent afterwards');
    fprintf('PASS: 16 open failure latches and reports exactly once\n');
else
    fprintf('SKIP: 16 filesystem accepted the reserved path; latch untested here\n');
end

% 17. Rotation uses the date and reopens ----------------------------------
expected = sprintf('error_log_%s.txt',char(datetime('now'),'ddMMMyyyy'));
assert(strcmp(cellstr_last(strsplit(tf.Path,filesep)),expected), ...
    'daily filename must match the established .error_logs pattern');
tf.close();
L.emit(1,false,'after close');
L.flush();
assert(isfile(tf.Path),'the sink must reopen after being closed');
assert(contains(fileread(tf.Path),'after close'),'records after reopen must be written');
fprintf('PASS: 17 filename pattern preserved and handle reopens\n');

% 18. Per-process filenames -----------------------------------------------
pp = eplog.sink.TextFile(scratch);
pp.PerProcess = true;
LP = eplog.Logger({pp});
LP.emit(1,false,'per process');
LP.flush();
assert(contains(pp.Path,sprintf('pid%d',feature('getpid'))), ...
    'PerProcess must put the pid in the filename');
pp.close();
fprintf('PASS: 18 per-process log files are addressable\n');

% 18b. Midnight rollover ---------------------------------------------------
% A rig left running overnight must roll into a new file and keep writing.
rot = eplog.sink.TextFile(scratch);
LR  = eplog.Logger({rot});
yesterday = [2026 8 9 23 59 59.5];
today     = [2026 8 10 0 0 0.25];
LR.log(eplog.record(yesterday,eplog.stamp(yesterday),1,false,'late night','f',1,'f.m'));
pathY = rot.Path;
LR.log(eplog.record(today,eplog.stamp(today),1,false,'early morning','f',2,'f.m'));
pathT = rot.Path;
LR.flush();
assert(~strcmp(pathY,pathT),'the log must roll over to a new file at midnight');
assert(contains(pathY,'09Aug2026') && contains(pathT,'10Aug2026'), ...
    'rolled files must be named for their own day');
assert(contains(fileread(pathY),'late night'),'the previous day must keep its record');
assert(contains(fileread(pathT),'early morning'),'the new day must receive its record');
rot.close();
fprintf('PASS: 18b log rolls over at midnight without losing records\n');

% 18c. A stolen file handle is recovered ----------------------------------
% fclose('all') and "clear all" are routine in MATLAB debugging and used to
% leak the handle or, worse, let the logger write into an unrelated file.
st = eplog.sink.TextFile(scratch);
LS = eplog.Logger({st});
LS.emit(1,false,'before the handle is closed');
fclose(st.Fid);                              % simulate fclose('all')
LS.emit(1,false,'after the handle is closed');
LS.flush();
body = fileread(st.Path);
assert(contains(body,'after the handle is closed'), ...
    'the sink must recover when its handle is closed underneath it');
st.close();
fprintf('PASS: 18c a closed handle is detected and reopened\n');

% 19. A broken sink cannot break the caller -------------------------------
LX = eplog.Logger({BrokenSink()});
ok = true;
try
    out = evalc('LX.emit(0,false,''survives'')'); %#ok<NASGU>
catch
    ok = false;
end
assert(ok,'a throwing sink must never propagate into the caller');
fprintf('PASS: 19 a throwing sink is contained\n');

% 20. Singleton and LogFile ------------------------------------------------
S = eplog.Logger.instance();
assert(S == eplog.Logger.instance(),'instance() must be a singleton');
assert(isa(S.sinkOfType('eplog.sink.TextFile'),'eplog.sink.TextFile'), ...
    'the default logger must carry a text file sink');
assert(ischar(S.LogFile),'LogFile must be queryable so consumers stop rebuilding the path');
fprintf('PASS: 20 singleton exposes LogFile for RunExpt and SelfTest\n');

% 21. Fitness: cost per call ----------------------------------------------
localBenchmark(scratch);

fprintf('\nAll smoke_test_eplog checks passed.\n\n');
end


% -------------------------------------------------------------------------
function localBenchmark(scratch)
% Old vs new cost per message. The old logger's fixed overhead was two datestr
% calls, a dbstack and an ftell; the new one is a clock read, two hand-built
% strings and one dbstack.
%
% Measured with loops rather than timeit: timeit runs its payload beneath
% several of its own frames, which inflates every dbstack in the measurement.

fprintf('\n--- fitness ---\n');

N = 2000;

global GVerbosity %#ok<GVMIS>
GVerbosity = 1;

% Suppressed path: what the 100 Hz-1 kHz trial loop pays for the level-3 and
% level-4 traces it never prints.
eplog.isEnabled(3);
t0 = tic; for k = 1:N, eplog.isEnabled(3); end, tGate = toc(t0)/N;
fprintf('suppressed gate      : %8.2f us\n',tGate*1e6);

% Old fixed overhead, measured directly rather than by calling vprintf, which
% would append benchmark noise to the repository's own .error_logs.
t0 = tic; for k = 1:N, localOldOverhead(); end, tOld = toc(t0)/N;
fprintf('old fixed overhead   : %8.2f us  (2x datestr + dbstack)\n',tOld*1e6);

t0 = tic; for k = 1:N, localNewOverhead(); end, tNew = toc(t0)/N;
fprintf('new fixed overhead   : %8.2f us  (clock + stamp + dateTag + dbstack)\n',tNew*1e6);

% End-to-end, including formatting and the file write.
bench = eplog.sink.TextFile(scratch);
bench.FlushLevel = -Inf;            % do not flush per record while timing
LB = eplog.Logger({bench});
LB.emit(1,false,'warmup');
t0 = tic;
for k = 1:N
    LB.emit(1,false,'trial %d of %d for box %d',{k,N,3});
end
tEmit = toc(t0)/N;
bench.close();
fprintf('full emit to file    : %8.2f us/message\n',tEmit*1e6);
fprintf('  at a 0.01 s timer  : %8.3f %% of one tick\n',100*tEmit/0.01);

if tNew < tOld
    fprintf('=> fixed overhead reduced %.1fx\n',tOld/tNew);
else
    fprintf('=> WARNING: no improvement in fixed overhead\n');
end

assert(tGate < tEmit,'the suppressed path must be cheaper than an emit');
assert(tNew < tOld,'the rework must not be slower than what it replaces');
assert(tEmit < 0.001,'a single log message must stay under one millisecond');
GVerbosity = 3;
end

function localOldOverhead()
% What helpers/vprintf.m does today on every emitted message.
s1 = datestr(now,'HH:MM:SS.FFF'); %#ok<NASGU,DATST,TNOW1>
s2 = datestr(now,'ddmmmyyyy');    %#ok<NASGU,DATST,TNOW1>
st = dbstack;                     %#ok<NASGU>
end

function localNewOverhead()
c = clock;                        %#ok<CLOCK>
s1 = eplog.stamp(c);              %#ok<NASGU>
s2 = eplog.dateTag(c);            %#ok<NASGU>
st = dbstack('-completenames');   %#ok<NASGU>
end

function [n,l,f] = localDirectCaller()
[n,l,f] = eplog.callerFrame();
end

function [n,l,f] = localNestedCaller()
[n,l,f] = localDirectCaller();
end

function localThrow()
error('epsych:smoke:deliberate','a deliberate failure');
end

function s = cellstr_last(c)
s = c{end};
end

function localRestore(v)
global GVerbosity %#ok<GVMIS>
GVerbosity = v;
end

function localRmdir(d)
if isfolder(d)
    try
        rmdir(d,'s');
    catch
        % scratch cleanup is best effort
    end
end
end
