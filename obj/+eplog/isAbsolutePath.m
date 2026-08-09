function tf = isAbsolutePath(p)
% tf = eplog.isAbsolutePath(p)
% True when p names a location that does not depend on the working directory.
%
% A relative log directory is the one failure mode the logger cannot recover
% from quietly: every cd would start a new .error_logs somewhere else, and the
% "Open Current Error Log" menu would point at whichever one is current. Both
% eplog.defaultLogDir and eplog.setLogDir refuse relative paths on that basis.
%
% Parameters:
%	p	- candidate path (char or string)
%
% Returns:
%	tf	- logical scalar
%
% See also: eplog.defaultLogDir, eplog.setLogDir

p = char(p);
if isempty(p)
    tf = false;
    return
end

if ispc
    % Drive-qualified (C:\ or C:/) or a UNC share (\\host\share).
    tf = ~isempty(regexp(p,'^([A-Za-z]:[\\/]|[\\/][\\/])','once'));
else
    tf = p(1) == '/';
end
end
