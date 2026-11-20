function [status, detail] = benchmarkStatus_(R, label)
% [status, detail] = epsych.RunExpt.benchmarkStatus_(R, label)
% The status-bar text for a finished hw.benchmarkIO run, worst news first: a
% failed round trip, then requested buffer sizes the buffer could not hold.
% Static and headless so tmp/smoke_test_hw_benchmark_runexpt.m can check the
% wording for a device's failure, which a session with no hardware cannot
% produce. Logs the skipped sizes at level 1.
%
% Parameters:
%   R     - results struct from hw.benchmarkIO.
%   label - the interface as the operator knows it.
%
% Returns:
%   status, detail - the two arguments of RunExpt.setStatus.
failedRT = R.Problems(R.Problems.Role == "RoundTrip", :);
otherProblems = R.Problems(R.Problems.Role ~= "RoundTrip", :);
skipped = R.Unsupported(R.Unsupported.Role == "Buffers" & contains(R.Unsupported.Reason, "exceeds"), :);
if ~isempty(skipped)
    vprintf(1, 'I/O benchmark: %d requested buffer size(s) skipped: %s', ...
        height(skipped), strjoin(skipped.Reason, '; '))
end

parts = strings(0, 1);
simulated = R.Environment.IsSimulated;
if ~isempty(failedRT)
    names = strjoin(unique(failedRT.Parameter, 'stable'), ', ');
    if simulated
        % hw.Software keeps nothing it is written, so there it fails by design.
        parts(end+1) = sprintf('round trip failed on %s (simulated interface: expected if it keeps no data)', names);
    else
        parts(end+1) = sprintf('ROUND TRIP FAILED on %s (%d check(s))', names, height(failedRT));
    end
end
if ~isempty(skipped)
    parts(end+1) = sprintf('%d buffer size(s) skipped', height(skipped));
end
if ~isempty(otherProblems)
    parts(end+1) = sprintf('%d other problem(s) in benchmarkIO_results.Problems', height(otherProblems));
end

if isempty(parts)
    status = sprintf('I/O benchmark of %s finished.', label);
    detail = 'Results are in the base workspace as benchmarkIO_results.';
    return
end

status = sprintf('I/O benchmark of %s finished; %s.', label, strjoin(parts, '; '));
if ~isempty(failedRT) && ~simulated
    detail = ['What was read back differs from what was written; see benchmarkIO_results.RoundTrip ' ...
        'and the figure heading. If the circuit writes its input into the buffer, stop it doing so ' ...
        '(documentation/hw/hw_benchmarkIO.md).'];
elseif ~isempty(skipped)
    detail = ['A requested size is larger than the buffer holds; see the note on the buffer plot. ' ...
        'Enlarge the buffer, or ask for smaller sizes.'];
else
    detail = 'Results are in the base workspace as benchmarkIO_results.';
end
end
