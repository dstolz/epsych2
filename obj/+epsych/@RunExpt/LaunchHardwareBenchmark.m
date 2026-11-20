function LaunchHardwareBenchmark(self, options)
% LaunchHardwareBenchmark(self)
% LaunchHardwareBenchmark(self, Sizes=[1024 4096], Repeats=50)
% Time one of the loaded protocols' hardware interfaces with hw.benchmarkIO.
% Sizes skips the sizes dialog (and does not touch the remembered sizes), for
% scripts and tests; the menu item passes nothing and so asks. Repeats is
% hw.benchmarkIO's, for the same callers.
%
% The interface is taken from the protocols already committed to the session,
% so the operator benchmarks the hardware the session would actually run on.
% With several interfaces a picker asks which; one that is not connected (the
% usual state between sessions, since interfaces connect at Run) is connected
% on the operator's say-so. A small dialog asks which buffer sizes to time
% (default 1024 4096, then the sizes last used on this machine). Results go to
% the command window and a figure; call hw.benchmarkIO directly for SaveTo,
% Repeats, or named roles.
%
% It writes to the benchmark's contract parameters only, and shares the MATLAB
% thread with the trial loop, so the menu item carries the 'setup' tag prefix
% and is unavailable while a session is RUNNING. While it runs, Run, Preview
% and Pause (and the other setup items) are locked and Stop ends the benchmark,
% after the call in progress and with no results kept. A failure is logged and
% put on the status bar rather than thrown.
%
% See also: hw.benchmarkIO, documentation/hw/hw_benchmarkIO.md
arguments
    self
    options.Sizes (1,:) double {mustBeInteger, mustBePositive} = []
    options.Repeats (1,1) double {mustBeInteger, mustBePositive} = 50
end

self.AlwaysOnTop(false);

% An empty session has CONFIG entries with no protocol, so test the type of
% each rather than assuming one.
ifs = hw.Interface.empty;
for k = 1:numel(self.CONFIG)
    p = self.CONFIG(k).PROTOCOL;
    if isa(p, 'epsych.Protocol')
        ifs = [ifs, p.Interfaces(:)'];
    end
end
ifs = unique(ifs, 'stable');

if isempty(ifs)
    self.setStatus('No hardware interface to benchmark.', ...
        'Add a subject with a protocol first (Subjects > Subjects & Projects).');
    return
end

if isscalar(ifs)
    iface = ifs;
else
    labels = arrayfun(@(i) sprintf('%s (%s)', i.displayLabel(), class(i)), ifs, 'UniformOutput', false);
    [idx, ok] = listdlg('ListString', labels, 'SelectionMode', 'single', ...
        'Name', 'I/O Benchmark', 'PromptString', 'Interface to benchmark:', ...
        'ListSize', [320 120]);
    if ~ok, return, end
    iface = ifs(idx);
end

label = sprintf('%s (%s)', iface.displayLabel(), class(iface));

if ~iface.IsConnected && ~iface.isSimulated()
    answer = questdlg(sprintf(['%s is not connected.\n\nConnect it now to ' ...
        'benchmark it? It stays connected for the session.'], label), ...
        'I/O Benchmark', 'Connect', 'Cancel', 'Cancel');
    if ~strcmp(answer, 'Connect'), return, end
    try
        iface.connect();
    catch ME
        vprintf(0,1,ME);
        self.setStatus(sprintf('Could not connect %s: %s', label, ME.message), ...
            'see Help > Diagnostics > Open Current Error Log.');
        return
    end
end

% The linear fit needs at least two buffer lengths on the one buffer tag.
% The last sizes accepted are the next default (1024 4096 the first time).
% Read behind ispref: the three-argument getpref would create the preference.
prefGroup = 'ep_RunExpt_Setup';
prefName = 'BenchmarkBufferSizes';
sizes = options.Sizes;
if isempty(sizes)
    default = '1024 4096';
    if ispref(prefGroup, prefName)
        remembered = parseSizes_(num2str(getpref(prefGroup, prefName)));
        if ~isempty(remembered)
            default = num2str(remembered);
        end
    end
    prompt = 'Buffer sizes to test (samples, separated by spaces or commas):';
    while isempty(sizes)
        answer = inputdlg(prompt, 'I/O Benchmark', [1 60], {default});
        if isempty(answer), return, end
        sizes = parseSizes_(answer{1});
        if isempty(sizes)
            prompt = 'Enter positive whole numbers, e.g. 1024 4096:';
            default = answer{1};
        end
    end
    setpref(prefGroup, prefName, sizes)
end

% From here until the benchmark ends, Run/Preview/Pause and the setup items
% are locked and Stop ends the benchmark (see dispatchCommand_). The cleanup
% hands the controls back on every exit, including an error.
self.BenchmarkStopRequested_ = false;
self.BenchmarkLastYield_ = uint64(0);
self.BenchmarkRunning_ = true;
unlock = onCleanup(@() self.endBenchmark_());
self.UpdateGUIstate
self.setStatus(sprintf('Benchmarking %s ...', label), 'press Stop to end it.');
drawnow

try
    R = hw.benchmarkIO(iface, Sizes = sizes, Repeats = options.Repeats, ...
        CancelFcn = @() self.benchmarkStopRequested_());
catch ME
    if strcmp(ME.identifier, 'hw:benchmarkIO:Cancelled')
        vprintf(1, 'I/O benchmark of %s stopped by the operator; no results.', label);
        self.setStatus(sprintf('I/O benchmark of %s stopped.', label), ...
            'no results were kept; start it again from Utilities > Hardware.');
        return
    end
    vprintf(0,1,ME);
    self.setStatus(sprintf('I/O benchmark failed on %s: %s', label, ME.message), ...
        'see Help > Diagnostics > Open Current Error Log.');
    return
end

assignin('base', 'benchmarkIO_results', R);
vprintf(1,'I/O benchmark of %s finished; results in base workspace as benchmarkIO_results.', label);

% A size the buffer cannot hold is skipped rather than failed, so it would
% otherwise vanish from the plot unremarked.
skipped = R.Unsupported(R.Unsupported.Role == "Buffers" & contains(R.Unsupported.Reason, "exceeds"), :);
if isempty(skipped)
    self.setStatus(sprintf('I/O benchmark of %s finished.', label), ...
        'Results are in the base workspace as benchmarkIO_results.');
else
    vprintf(1, 'I/O benchmark: %d requested buffer size(s) skipped: %s', ...
        height(skipped), strjoin(skipped.Reason, '; '))
    self.setStatus(sprintf('I/O benchmark of %s finished; %d buffer size(s) skipped.', ...
        label, height(skipped)), ...
        'A requested size is larger than the buffer holds; see the note on the buffer plot. Enlarge the buffer, or ask for smaller sizes.');
end

end


function sizes = parseSizes_(txt)
% Positive whole numbers from free text, or [] if any token is not one.
% Parsed with str2double, never evaluated.
tok = strsplit(strtrim(txt), {' ', ',', ';'}, 'CollapseDelimiters', true);
tok = tok(~cellfun(@isempty, tok));
v = str2double(tok);
if isempty(v) || any(~isfinite(v)) || any(v < 1) || any(v ~= round(v))
    sizes = [];
else
    sizes = unique(v, 'stable');
end
end
