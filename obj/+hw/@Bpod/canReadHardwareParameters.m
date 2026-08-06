function tf = canReadHardwareParameters(obj, module)
% tf = canReadHardwareParameters(obj, module)
% True when this module is the one that holds the Bpod parameter table.
%
% Backs ProtocolDesigner's "Read HW Params" button. This is not a blanket true:
% the Bpod channel inventory is fixed in firmware and belongs to one module, so
% pouring it into some other module the user added would fabricate a duplicate
% channel set and, worse, a second copy of the readable-result parameters whose
% field set the runtime relies on being stable.
%
% No connection is required. Unlike hw.Teensy, which reads its table out of the
% board's DESC? descriptor, the Bpod inventory is hardcoded — eight ports, two
% BNCs, four wires, eight valves, eight PWM lines — so the table can be rebuilt
% with no board attached.
%
% Parameters:
%   obj    - hw.Bpod instance.
%   module - hw.Module to test.
%
% Returns:
%   tf - True when readHardwareParameters would populate this module.
%
% See also: hw.Bpod.readHardwareParameters, hw.Interface.canReadHardwareParameters

tf = false;

if nargin < 2 || isempty(module) || ~isa(module, 'hw.Module') || ~isscalar(module)
    return
end

% Identity first. When the module belongs to this interface the answer is
% settled without consulting names at all: the first module is the table owner
% by construction, whatever it happens to be called, and any later module the
% user added is not. == on a handle class is object identity, which is what is
% wanted here.
if ~isempty(obj.Module)
    isMine = obj.Module == module;
    if any(isMine)
        tf = isMine(1);
        return
    end
end

% Otherwise match by name. hw.Module.Name and .Label are immutable, so this is
% stable for the life of the module and survives a protocol save/restore, where
% createInterfaceFromStruct_ rebuilds modules from the saved label and name.
% Matched loosely so a module named 'Bpod', 'BpodSM', or 'Bpod 0.6' all resolve.
tf = local_isBpodName(module.Name) || local_isBpodName(module.Label);

end


% ------------------------------------------------------------------------
function tf = local_isBpodName(name)
% tf = local_isBpodName(name)
% Case-insensitive test for a Bpod-flavoured module name.
tf = ~isempty(name) && contains(lower(char(name)), 'bpod');
end
