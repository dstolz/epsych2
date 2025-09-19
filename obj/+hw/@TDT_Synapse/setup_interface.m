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
mp = cellfun(@(a) obj.HW.getParameterNames(a),{obj.Module.Label},'uni',0);
p = characterListPattern('%/|\#'); % remove reserved TDT parameters

for m = 1:length(obj.Module)
    if isempty(mp{m}), continue; end

    mp{m} = mp{m}(~startsWith(mp{m},p));

    tagInfo = cellfun(@(a) obj.HW.getParameterInfo(obj.Module(m).Label,a),mp{m},'uni',1);
    for t = tagInfo(:)'
        % P = hw.Parameter(obj.Module(m));
        P = hw.Parameter(obj);

        P.Name = t.Name;
        P.Unit = t.Unit;
        P.Min = t.Min;
        P.Max = t.Max;
        P.Access = t.Access;
        P.Type = t.Type;
        P.isArray = isequal(t.Array,'Yes');

        P.Module = obj.Module(m);

        P.isTrigger = P.Name(1) == '!'; % our convention for indicating a trigger

        P.Visible = P.Name(1) ~= '_'; % our convention for a core macro parameter
        P.Visible = P.Name(1) ~= '~'; % our convention for a hidden parameter


        obj.Module(m).Parameters(end+1) = P;
    end

end

end


