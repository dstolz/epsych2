function [tf, msg] = readHardwareParameters(obj, module, options)
% [tf, msg] = readHardwareParameters(obj, module, Name=Value)
% Populate a module's parameters from the board's DESC? descriptor.
%
% Backs ProtocolDesigner's "Read HW Params" button. Designer interfaces are
% never connected, so when the interface is offline this opens a temporary
% serial connection, reads the descriptor, and closes it again — leaving the
% interface exactly as it found it.
%
% Per the hw.Interface contract this never throws: a failure returns
% tf = false with a human-readable message for the caller to display.
%
% Parameters:
%   obj          - hw.Teensy instance.
%   module       - hw.Module to populate.
%   options.Mode - 'merge' (default) or 'replace'. See
%                  populateModuleParametersFromDescriptor.
%
% Returns:
%   tf  - True when parameters were read and applied.
%   msg - Explanation, populated on failure.
%
% See also: documentation/hw/hw_Interface.md, hw.Teensy.populateModuleParametersFromDescriptor

arguments
    obj
    module (1,1) hw.Module
    options.Mode (1,:) char {mustBeMember(options.Mode, {'merge', 'replace'})} = 'merge'
end

tf = false;
msg = '';

wasConnected = obj.IsConnected;

try
    if ~wasConnected
        if isempty(obj.Port) && ~obj.AutoDetect
            msg = ['No serial port is configured for this Teensy interface. ' ...
                   'Set the Port option, or enable Auto Detect, then read again.'];
            return
        end
        obj.connect();
    end

    if ~obj.IsConnected
        msg = sprintf('Could not connect to a Teensy board on %s.', obj.Port);
        return
    end

    descriptor = obj.transactBlock_('DESC?', 'DESC');
    if isempty(descriptor)
        msg = 'The board returned an empty parameter descriptor.';
        return
    end

    obj.populateModuleParametersFromDescriptor(module, descriptor, Mode = options.Mode);
    obj.ensureUniqueParameterNames();

    tf = true;
    msg = sprintf('Read %d parameters from %s on %s.', ...
        numel(module.Parameters), obj.BoardType, obj.Port);

catch ME
    msg = sprintf('Reading parameters from the Teensy failed: %s', ME.message);
end

% Restore the connection state we found, whatever happened above.
try
    if ~wasConnected && obj.IsConnected
        obj.disconnect();
    end
catch ME
    vprintf(0, 1, ME);
end

end
