function [s, why] = readFile_(file)
% [s, why] = behavior.Project.readFile_(file)
% A project file decoded, or why it could not be. Never throws: an unreadable
% file is a state the project opens in (read-only), not an error.
%
% Returns:
%   s   - jsondecode output ([] when why is not "")
%   why - "" on success, else a short reason

s = [];
why = "";
try
    txt = fileread(file, 'Encoding', 'UTF-8');
catch ME
    why = "it could not be read: " + string(ME.message);
    return
end
if strtrim(string(txt)) == ""
    why = "it is empty";
    return
end
try
    s = jsondecode(txt);
catch ME
    why = "it is not valid JSON: " + string(ME.message);
    s = [];
    return
end
if ~isstruct(s) || ~isscalar(s)
    why = "it is JSON but not a project (no top-level object)";
    s = [];
end

end
