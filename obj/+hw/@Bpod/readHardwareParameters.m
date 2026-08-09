function [tf, msg] = readHardwareParameters(obj, module, options)
% [tf, msg] = readHardwareParameters(obj, module, Name=Value)
% Rebuild the canonical Bpod parameter table on a module.
%
% Backs ProtocolDesigner's "Read HW Params" button. For hw.Teensy this opens the
% port and reads a DESC? descriptor; for Bpod there is nothing to ask. The
% 0.5/0.6 main module's channel inventory is fixed in firmware — eight behaviour
% ports with their PWM lines, two BNC in/out, four wire in/out, eight valves —
% so "reading from hardware" means repopulating the same hardcoded table
% populateModule_ builds at connect. That is why this works with no board
% attached, on a rig that has never seen a Bpod, which is exactly the situation
% a protocol is usually designed in.
%
% Per the hw.Interface contract this never throws: a failure returns tf = false
% with a human-readable message for the caller to display.
%
% Parameters:
%   obj          - hw.Bpod instance.
%   module       - hw.Module to populate. Must be the module that owns the table
%                  (see canReadHardwareParameters).
%   options.Mode - 'merge' (default) keeps existing parameters and appends only
%                  what is missing, preserving user edits. 'replace' rebuilds the
%                  table purely from the firmware inventory.
%
% Returns:
%   tf  - True when the table was repopulated.
%   msg - Outcome summary, e.g. 'Bpod: added 12 parameter(s)'.
%
% See also: hw.Bpod.canReadHardwareParameters, hw.Interface.readHardwareParameters,
%           documentation/hw/hw_Bpod.md

arguments
    obj
    module (1,1) hw.Module
    options.Mode (1,:) char {mustBeMember(options.Mode, {'merge', 'replace'})} = 'merge'
end

tf = false;
msg = '';

try
    if ~obj.canReadHardwareParameters(module)
        msg = sprintf(['Module "%s" does not hold the Bpod parameter table, so there is ' ...
            'nothing to read into it. Select the interface''s Bpod module and read again.'], ...
            module.Name);
        return
    end

    nBefore = numel(module.Parameters);

    % No connection is opened. The inventory is hardcoded, and connecting would
    % be worse than useless mid-session: an 'I' probe issued while a matrix is
    % running desynchronizes the event stream.
    obj.populateModule_(module, Mode = options.Mode);
    obj.ensureUniqueParameterNames();

    nAfter = numel(module.Parameters);
    tf = true;

    switch options.Mode
        case 'replace'
            msg = sprintf('Bpod: defined %d parameter(s)', nAfter);
        otherwise
            msg = sprintf('Bpod: added %d parameter(s)', max(0, nAfter - nBefore));
    end
    vprintf(2, '%s on module "%s" (mode: %s)', msg, module.Name, options.Mode);

catch ME
    tf = false;
    msg = sprintf('Bpod: reading the parameter table failed: %s', ME.message);
    vprintf(0, 1, ME);
end

end
