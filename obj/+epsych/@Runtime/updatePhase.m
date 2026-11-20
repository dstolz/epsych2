function report = updatePhase(obj, phaseFile, options)
% report = updatePhase(obj, phaseFile)
% report = updatePhase(obj, phaseFile, DryRun=false)
% Bring a phase file up to the protocol version this session runs.
%
% The phase keeps its values and the protocol wins on structure; see
% epsych.Protocol.updatePhase for the rule and the report. This supplies the
% target: the session's protocol FILE (ProtocolFile) at the version its
% protocol object was loaded at (Protocol.meta.protocolVersion) -- which is an
% archived version for a pinned membership, and stays the version the session
% started with when someone saves the protocol again mid-session.
%
% Nothing is loaded into the session. Never throws.
%
% Parameters:
%   obj        The runtime; ProtocolFile and Protocol must be set (RunExpt
%              sets both at dispatch).
%   phaseFile  The phase (.eprot) to update.
%
% Options:
%   DryRun        (default true) report what would change, write nothing
%   AllowForeign  (default false) see epsych.Protocol.updatePhase
%
% Returns:
%   report     epsych.Protocol.updatePhase's report
%
% See also: epsych.Protocol.updatePhase, writeParametersProtocol,
%   readParameters, gui.components.PhaseSelector

arguments
    obj
    phaseFile (1,1) string
    options.DryRun (1,1) logical = true
    options.AllowForeign (1,1) logical = false
end

protocolFile = obj.ProtocolFile;
why = "";
if isempty(obj.Protocol) || ~isvalid(obj.Protocol)
    why = "This session has no protocol to update phases to.";
elseif strlength(protocolFile) == 0
    why = "This session's protocol was not loaded from a file, so there is no protocol version to update phases to.";
elseif ~isfile(protocolFile)
    why = sprintf("The session's protocol file is gone: %s", protocolFile);
end
if strlength(why) > 0
    % The same report epsych.Protocol.updatePhase returns, refused.
    report = epsych.Protocol.updatePhase('', '');
    report.PhaseFile = char(phaseFile);
    report.ProtocolFile = char(protocolFile);
    report.message = char(why);
    return
end

version = '';
if isfield(obj.Protocol.meta, 'protocolVersion')
    version = char(string(obj.Protocol.meta.protocolVersion));
end

report = epsych.Protocol.updatePhase(char(phaseFile), char(protocolFile), version, ...
    DryRun = options.DryRun, AllowForeign = options.AllowForeign);
end
