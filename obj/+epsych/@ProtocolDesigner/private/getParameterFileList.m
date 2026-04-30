function fileList = getParameterFileList(obj, parameter)
% fileList = getParameterFileList(obj, parameter)
% Return the normalized file list stored in a File parameter.
%
% Parameters:
%	parameter	- File parameter whose Values property is being interpreted.
%
% Returns:
%	fileList	- Cell array of file paths extracted from the parameter value.
    fileList = obj.normalizeFileValueToList(parameter.Values);
end

