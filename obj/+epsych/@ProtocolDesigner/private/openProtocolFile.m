function convertedNames = openProtocolFile(obj, filePath)
% convertedNames = openProtocolFile(obj, filePath)
% Load a protocol file and refresh the designer state around it.
%
% Parameters:
%	filePath	- Protocol file to load.
%
% Returns:
%	convertedNames	- Names of parameters whose literal-constant Expressions
%			  were converted to fixed Values on load (see
%			  normalizeConstantExpressions); empty when none.
    if isstring(filePath)
        filePath = char(filePath);
    end

    warning('off', 'MATLAB:dispatcher:UnresolvedFunctionHandle');
    obj.Protocol = epsych.Protocol.load(filePath);
    warning('on', 'MATLAB:dispatcher:UnresolvedFunctionHandle');

    obj.CurrentProtocolPath = filePath;
    obj.setLastProtocolFilePath(filePath);
    obj.setLastBrowseDirectory(fileparts(filePath));
    obj.addRecentProtocolPath(filePath);
    obj.refreshRecentProtocolMenu();
    obj.IsModified_ = false;

    % Protocols written before the designer stored constants as values carry a
    % literal Expression on every numeric parameter; converting marks the
    % protocol modified so the healed state gets saved.
    convertedNames = obj.normalizeConstantExpressions();
    if ~isempty(convertedNames)
        obj.IsModified_ = true;
        vprintf(1, 'Converted %d constant expression(s) to fixed values on load: %s', ...
            numel(convertedNames), strjoin(convertedNames, ', '))
    end

    obj.setParameterNameFilter('');
    obj.refreshUI();
end