function tf = copyTable(T)
% tf = behavior.Export.copyTable(T)
% Copies the table to the system clipboard as tab-separated text
% (behavior.Export.toTSV). Never throws: where there is no clipboard (a
% headless session) it logs at debug level and returns false.
%
% Returns:
%   tf - true when the text reached the clipboard.

arguments
    T table
end

tf = false;
try
    clipboard('copy', char(behavior.Export.toTSV(T)));
    tf = true;
catch ME
    vprintf(2, 'Export: the clipboard is not available: %s', ME.message);
end
end
