function compile(obj)
% compile(obj)
%
% Compile protocol into COMPILED struct containing writeparams, readparams,
% randparams, trials, OPTIONS, and ntrials. Validates first; errors abort.
%
% See also: validate, compile_internal

report = obj.validate();
if ~isempty(report)
    severity_levels = [report.severity];
    if any(severity_levels == 2)
        vprintf(0, 1, 'Cannot compile: validation errors present. Call validate() for details.');
        return
    end
end

obj.compile_internal();
end
