% setup hardware interface. CONFIG is platform dependent
function setup_interface(obj) % hw.TDT_Synapse

vprintf(2,'Establishing Synapse API')


% check if SynapseAPI is on the path
w = which('SynapseAPI');
if isempty(w)
    error('SynapseAPI not found on Matlab''s path.')
end

% Establish SynapseAPI object
obj.HW = SynapseAPI(obj.Server);


% ensure we start in Idle
if obj.HW.getMode > 0
    obj.HW.setMode(0);
end


%Switch Synapse into Standby Mode.
obj.HW.setModeStr('Standby');







%Get Device Names and Sampling rates
h = obj.HW.getSamplingRates;
fn = fieldnames(h);
xind = startsWith(fn,'x_');
h = rmfield(h,fn(xind));

m = fieldnames(h);

mName  = cellfun(@(a) a(1:find(a=='_')-1),m,'uni',0);
mIdx   = cellfun(@(a) str2double(a(find(a=='_')+1:end)),m);
mIdx   = uint8(mIdx);
mLabel = cellfun(@(a,b) sprintf('%s(%d)',a,b),mName,num2cell(mIdx),'uni',0);
mFs    = struct2array(h);


% update module info
for m = 1:length(mName)
    modInfo = obj.HW.getGizmoInfo(mLabel{m});
    obj.Module(m) = hw.Module(obj,mLabel{m},mName{m},mIdx(m));
    obj.Module(m).Info.Legacy = isequal(modInfo.cat,'Legacy');
    obj.Module(m).Fs = mFs(m);
end




% setup parameters
for m = 1:length(obj.Module)
    obj.populateModuleParametersFromGizmo(obj.Module(m), obj.HW);
end

obj.ensureUniqueParameterNames();

end


