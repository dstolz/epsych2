function dinfo = TDT_GetDeviceInfo_Synapse(SYN)
% dinfo = TDT_GetDeviceInfo_Synapse(SYN)
% 
% Get Device Names and Sampling rates from SYNAPSE API
% 
% SYN is a handle to the SYNAPSE API control after a conneciton
% has already been established.
% 
% The original version of this function relied on Open Developer controls
% which are being phased out by TDT and are no longer supported. This newer
% function uses SYNAPSE API, which is more stable and will be supported
% moving forward.
% 
% See also TDT_GetDeviceInfo
% 
% Daniel.Stolzberg@gmail.com 2014 
% Edited by ML Caras 02.15.2020

warning('off','MATLAB:strrep:InvalidInputType')

dinfo = [];
vprintf(0,'Collecting RPVds info...')

%Get Gizmo Names
gizmo_names = SYN.getGizmoNames();
rates = SYN.getSamplingRates();

j = 1;

%Find the hardware modules
for i = 1:numel(gizmo_names)
    name = gizmo_names{i};
    modInfo = SYN.getGizmoInfo(name);
    
    switch modInfo.cat
        case {'Hardware Access','Legacy'} %RZ2 and RZ6
             module = name(1:3);
             parent = SYN.getGizmoParent(name);
             
             %Parent device won't be found for RZ6 because it's
             %operating in legacy mode. Define the device here.
             if isempty(parent)% || ~parent 
                 parent = [module,'_1'];
             end
             
             fs = rates.(parent);
 
        otherwise
            continue
    end
   
    
    dinfo.name{j} = name; %#ok<*AGROW>
    
    dinfo.Module{j} = module;
    
    dinfo.Fs(j) = fs;
    
    j = j+1;

end

vprintf(0,'RPVds info collected. Initializing...');

warning('on','MATLAB:strrep:InvalidInputType')

