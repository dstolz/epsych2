function writeParametersProtocol(obj, filepath, description)
% writeParametersProtocol(obj, filepath, description)
% Save the current session state as a protocol (.eprot) phase file.
%
% Phases and protocols share one format: saving a phase serializes the session's
% epsych.Protocol. Because the Runtime borrows the Protocol's own hw.Interface
% handles (see RunExpt.ExptDispatch), the protocol's parameters already hold the
% live runtime values, so its toStruct output is an exact snapshot of the current
% session: parameter values, design-time Values, Expressions, trial options, and
% compiled trials. The resulting file opens anywhere a protocol does
% (ProtocolDesigner, RunExpt, epsych.Protocol.load) and loads as a phase via
% readParameters.
%
% The live protocol object is not mutated: the snapshot is serialized directly
% rather than through Protocol.save, which would bump the live protocol's
% version/lastModified metadata as a side effect. The saved file keeps the source
% protocol's version so the phase records its lineage.
%
% Parameters:
%   obj                        The runtime object; obj.Protocol must be set.
%   filepath (1,:) string      Path for the output .eprot file. If not provided,
%                              prompts user to select a location.
%   description (1,1) string   Optional phase description; stored as the saved
%                              protocol's Info text.
%
% See also: readParameters, phaseParameterData, epsych.Protocol.save,
%   writeParametersJSON

arguments
    obj
    filepath (1,:) string = ""
    description (1,1) string = ""
end

assert(~isempty(obj.Protocol) && isvalid(obj.Protocol), ...
    'epsych:Runtime:NoProtocol', ...
    'Runtime.Protocol is not set. It is assigned from the session protocol when the experiment is dispatched (see RunExpt.ExptDispatch); assign it manually for scripted use.');

% If filepath is not provided, prompt user to select file
if filepath == ""
    [fn,pth] = uiputfile({'*.eprot','Phase Protocol (*.eprot)'}, 'Save Current Parameters As Phase Protocol');
    if isequal(fn,0) || isequal(pth,0)
        vprintf(3,'User canceled save operation.')
        return
    end
    filepath = fullfile(pth, fn);
end

[~,~,ext] = fileparts(filepath);
if strlength(ext) == 0
    filepath = filepath + ".eprot";
end

% toStruct captures the live parameter values (shared handles, see above) and
% stamps lastModified itself.
protocol = obj.Protocol.toStruct();
if strlength(description) > 0
    protocol.Info = char(description);
end

% Same MAT layout as epsych.Protocol.save: a single 'protocol' struct variable.
builtin('save', char(filepath), 'protocol', '-mat');

vprintf(0, 'Phase protocol saved to: %s', filepath)

end
