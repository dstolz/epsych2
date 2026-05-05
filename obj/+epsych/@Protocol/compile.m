function compile(obj)
% compile(obj)
% Validate the protocol and populate obj.COMPILED when no blocking errors remain.
%
% Call validate() to inspect nonblocking issues before compilation.

report = obj.validate();
if ~isempty(report)
    severity_levels = [report.severity];
    if any(severity_levels == 2)
        vprintf(0, 1, 'Cannot compile: validation errors present:\n');
        for idx = 1:numel(report)
            if report(idx).severity == 2
                vprintf(0, 1, '  [ERROR] %s\n', report(idx).message);
            end
        end
        return
    end
end

obj.compile_internal();
end
