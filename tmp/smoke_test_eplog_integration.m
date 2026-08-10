function smoke_test_eplog_integration
% smoke_test_eplog_integration
% Verify that EPsych actually logs THROUGH the +eplog package.
%
% smoke_test_eplog proves the package works in isolation. This one proves the
% seam: that vprintf is a façade over eplog.Logger, that the calling
% conventions used across the repository still mean what they meant, and that
% the consumers which name the log file agree with the sink about where it is.
%
% The session logger's file sink is redirected to a scratch directory for the
% duration, so the repository .error_logs is untouched. The logger is reset
% afterwards.
%
% Run headless: matlab -batch "addpath('c:\src\epsych2'); epsych_startup('c:\src\epsych2',false); run('c:\src\epsych2\tmp\smoke_test_eplog_integration.m')"

global GVerbosity %#ok<GVMIS>
priorVerbosity = GVerbosity;

% The log directory override is a real user preference. Capture and clear it so
% the checks below run against a known state, and put it back afterwards.
priorLogDir = '';
if ispref('eplog','LogDir')
    priorLogDir = char(getpref('eplog','LogDir'));
    rmpref('eplog','LogDir');
end

scratch = fullfile(tempdir,sprintf('eplog_integration_%d',feature('getpid')));
if isfolder(scratch), rmdir(scratch,'s'); end

cleanup = onCleanup(@() localCleanup(priorVerbosity,priorLogDir,scratch));

GVerbosity = 3;

fprintf('\n=== smoke_test_eplog_integration ===\n');

% Redirect the singleton's file sink into the scratch directory. Everything
% below goes through vprintf, so it exercises the real path.
L = eplog.Logger.instance('-reset');
L.removeSink(L.sinkOfType('eplog.sink.FileSink'));
sink = eplog.sink.TextFile(scratch);
L.addSink(sink);

% 1. vprintf reaches the sink, attributed to its caller ---------------------
vprintf(1,'plain message');
L.flush();
txt = fileread(sink.Path);
assert(contains(txt,': plain message'),'vprintf did not reach the file sink');
assert(contains(txt,'smoke_test_eplog_integration'), ...
    'the log must name the function that called vprintf, not vprintf');
fprintf('PASS: 1 vprintf routes through the session logger\n');

% 2. The four calling conventions -------------------------------------------
% These are the shapes in use across the repository; all four must survive
% the move to eplog.
before = localBytes(sink.Path);
out = evalc('vprintf(1,''level %d for box %d'',2,7)');
assert(contains(out,'level 2 for box 7'),'msg + values path broken');

out = evalc('vprintf(1,1,''red with %s'',''values'')');
assert(contains(out,'red with values'),'red + msg + values path broken');

out = evalc('vprintf(1,0,''explicit non-red'')');
assert(contains(out,'explicit non-red'),'red + msg path broken');

out = evalc('vprintf(1,"a string message")');
assert(contains(out,'a string message'), ...
    'a string scalar message must be a message, not the red flag');

out = evalc('vprintf(1,"box %d ready",4)');
assert(contains(out,'box 4 ready'),'string format with values broken');
L.flush();
assert(localBytes(sink.Path) > before,'none of those reached the log');
fprintf('PASS: 2 every vprintf calling convention still means the same thing\n');

% 3. Literal messages survive ------------------------------------------------
% The no-values path is literal, which is what protects the messages built at
% runtime: data paths and tool output.
p = fullfile('C:','new','tmp','data_%s.mat');
out = evalc('vprintf(1,p)');
assert(contains(out,p),'a Windows path passed as the whole message must survive');
out = evalc('vprintf(1,''ffmpeg reported 90% at frame 12'')');
assert(contains(out,'90%'),'a stray percent must survive');
fprintf('PASS: 3 runtime-built messages are not reinterpreted as formats\n');

% 4. Level -1 logs without printing -----------------------------------------
before = localBytes(sink.Path);
out = evalc('vprintf(-1,''log only marker'')');
assert(isempty(strtrim(out)),'level -1 must not reach the console');
L.flush();
assert(localBytes(sink.Path) > before,'level -1 must still reach the log');
fprintf('PASS: 4 level -1 logs without printing\n');

% 5. A suppressed message costs nothing and writes nothing -------------------
GVerbosity = 1;
before = localBytes(sink.Path);
out = evalc('vprintf(3,''suppressed'')');
assert(isempty(strtrim(out)),'a suppressed message must not print');
L.flush();
assert(localBytes(sink.Path) == before,'a suppressed message must not be logged');
assert(~visenabled(3) && visenabled(1) && visenabled(0), ...
    'visenabled must agree with the gate vprintf uses');
GVerbosity = 3;
fprintf('PASS: 5 suppressed levels write nothing; visenabled agrees\n');

% 6. Exceptions log once, at the catch site ---------------------------------
before = localBytes(sink.Path);
try
    localThrow();
catch ME
    vprintf(0,1,ME);
end
L.flush();
lines = localNewLines(sink.Path,before);
assert(contains(lines{1},'smoke_test_eplog_integration'), ...
    sprintf('the exception must be stamped with the catch site, got: %s',lines{1}));
assert(contains(lines{1},'epsych:integration:deliberate'),'identifier must be logged');
assert(any(contains(lines,'    at localThrow')),'the stack must be indented under the record');
fprintf('PASS: 6 catch-block logging is attributed to the catch site\n');

% 7. RUNTIME.ERROR shapes ---------------------------------------------------
% ep_TimerFcn_Error passes RUNTIME.ERROR, which is either an MException or a
% timer ErrorFcn event struct. Both must log rather than throw.
before = localBytes(sink.Path);
evtStruct = struct('message','timer callback failed', ...
    'messageID','epsych:integration:timer', ...
    'stack',struct('file','t.m','name','tfcn','line',3));
vprintf(0,1,evtStruct);
L.flush();
body = strjoin(localNewLines(sink.Path,before),newline);
assert(contains(body,'epsych:integration:timer') && contains(body,'timer callback failed'), ...
    'a timer error struct must log identifier and message');
fprintf('PASS: 7 a timer ErrorFcn struct logs like an exception\n');

% 8. vprintf never throws ----------------------------------------------------
ok = true;
try
    evalc('vprintf(1)');                       % nothing to say
    evalc('vprintf(1,''%d %d'',1)');           % too few values
    evalc('vprintf(1,struct(''a'',1))');       % unprintable message
    evalc('vprintf(''oops'',''bad level'')');  % malformed level
catch
    ok = false;
end
assert(ok,'vprintf must never propagate an exception into its caller');
fprintf('PASS: 8 malformed vprintf calls degrade instead of throwing\n');

% 9. Consumers agree with the sink about where the log is --------------------
% RunExpt.OpenCurrentErrorLog, the SelfTest window's Open Log button and
% SelfTest check A4 all resolve the path this way.
assert(strcmp(L.LogFile,sink.Path), ...
    sprintf('LogFile (%s) disagrees with the open sink (%s)',L.LogFile,sink.Path));

fresh = eplog.sink.TextFile(fullfile(scratch,'never_written'));
LF = eplog.Logger({fresh});
assert(endsWith(LF.LogFile,sprintf('error_log_%s.txt',eplog.dateTag(clock))), ...
    'LogFile must name today''s file even before anything is written');
assert(~isfile(LF.LogFile),'querying LogFile must not create the file');
delete(LF);
fprintf('PASS: 9 LogFile names the file the next record will land in\n');

% 10. The default logger writes where EPsych has always written -------------
D = eplog.Logger.instance('-reset');
expected = fullfile(epsych_path,'.error_logs', ...
    sprintf('error_log_%s.txt',eplog.dateTag(clock)));
assert(strcmp(D.LogFile,expected), ...
    sprintf('default log path moved: %s (expected %s)',D.LogFile,expected));
assert(~isempty(D.sinkOfType('eplog.sink.Console')),'the default logger must echo to the console');
fprintf('PASS: 10 the default log path is unchanged\n');

% 11. SelfTest check A4 passes against the live logger ----------------------
% A4 is the check that proves the report itself is trustworthy; run the whole
% Environment group so it runs exactly as an operator would see it.
st = epsych.SelfTest();
st.Verbosity = 1;
evalc('results = st.run("Environment")');
a4 = results(strcmp([results.id],"A4_Logging"));
assert(isscalar(a4),'A4_Logging is missing from the Environment group');
assert(a4.status == "pass", ...
    sprintf('SelfTest A4 failed against the eplog logger: %s',a4.summary));
fprintf('PASS: 11 SelfTest A4 passes through the eplog file sink\n');

% 12. saveReport lands beside the daily log ---------------------------------
ffn = st.saveReport(results);
assert(isfile(ffn),'the self-test report was not written');
assert(strcmp(fileparts(char(ffn)),eplog.defaultLogDir()), ...
    'the report must be written to the logger''s own directory');
delete(ffn);
fprintf('PASS: 12 self-test reports are written beside the daily log\n');

% 13. The log directory override --------------------------------------------
% Customize > Paths > Error Log Path, and eplog.setLogDir behind it. The move
% must take effect immediately, not at the next MATLAB session.
alt = fullfile(scratch,'alt_logs');
d = eplog.setLogDir(alt);
assert(strcmp(d,alt),'setLogDir must report the directory now in effect');
assert(strcmp(eplog.defaultLogDir(),alt),'the override must win over the built-in default');

vprintf(1,'written after the move');
M = eplog.Logger.instance();
M.flush();
assert(strcmp(fileparts(M.LogFile),alt), ...
    sprintf('the live logger did not follow the move: %s',M.LogFile));
assert(contains(fileread(M.LogFile),'written after the move'), ...
    'records after the move must land in the new directory');

threw = false;
try
    eplog.setLogDir(fullfile('relative','logs'));
catch relErr
    threw = strcmp(relErr.identifier,'eplog:setLogDir:RelativePath');
end
assert(threw,'a relative log directory must be refused');
assert(strcmp(eplog.defaultLogDir(),alt),'a refused path must not disturb the current one');

d = eplog.setLogDir('');
assert(strcmp(d,fullfile(epsych_path,'.error_logs')), ...
    'clearing the override must restore the built-in default');
assert(~ispref('eplog','LogDir'),'clearing must remove the preference, not blank it');
M.flush();
assert(strcmp(fileparts(M.LogFile),fullfile(epsych_path,'.error_logs')), ...
    'the live logger must follow the revert too');
fprintf('PASS: 13 the log directory override applies to the running logger\n');

% 14. The external viewer default -------------------------------------------
% OpenCurrentErrorLog(self,true) falls back to this when no viewer is set.
viewer = epsych.RunExpt.defaultLogViewer();
assert(ischar(viewer) && ~isempty(viewer),'a platform default viewer must be named');
fprintf('PASS: 14 an external log viewer default exists (%s)\n',viewer);

fprintf('\nAll smoke_test_eplog_integration checks passed.\n\n');
end


% -------------------------------------------------------------------------
function localThrow()
error('epsych:integration:deliberate','a deliberate failure');
end

function n = localBytes(p)
d = dir(p);
if isempty(d)
    n = 0;
else
    n = d(1).bytes;
end
end

function lines = localNewLines(p,fromByte)
% The lines appended to the log since fromByte.
txt = fileread(p);
txt = txt(min(fromByte,numel(txt))+1:end);
lines = strsplit(strtrim(txt),newline);
end

function localCleanup(priorVerbosity,priorLogDir,scratch)
global GVerbosity %#ok<GVMIS>
GVerbosity = priorVerbosity;
if isempty(priorLogDir)
    if ispref('eplog','LogDir'), rmpref('eplog','LogDir'); end
else
    setpref('eplog','LogDir',priorLogDir);
end
eplog.Logger.instance('-reset');
if isfolder(scratch)
    try
        rmdir(scratch,'s');
    catch
        % scratch cleanup is best effort
    end
end
end
