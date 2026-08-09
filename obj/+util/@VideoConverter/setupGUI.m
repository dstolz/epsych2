function g = setupGUI(obj, varargin)
% g = obj.setupGUI()
% g = obj.setupGUI(Name=Value,...)
% Open gui.VideoConverterSetup for this converter.
% See also: gui.VideoConverterSetup, documentation/util/VideoConverter.md
g = gui.VideoConverterSetup(obj, varargin{:});
end
