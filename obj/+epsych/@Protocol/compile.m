function compile(obj)
% compile(obj)
% Validate the protocol and populate obj.COMPILED when no blocking errors remain.
%
% Call validate() to inspect nonblocking issues before compilation.

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
