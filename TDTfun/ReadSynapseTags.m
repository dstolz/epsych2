function [RUNTIME,varargout]  = ReadSynapseTags(SYN,RUNTIME)
%[RUNTIME,varargout]  = ReadSynapseTags(SYN,RUNTIME)
%
%Custom function for Caras Lab.
%Reads parameter tags using Synapse API
%
%SYN is the handle to the Synapse API control
%
%Written by ML Caras Apr 7 2018
%Updated by ML Caras Oct 19 2019
%Updated by ML Caras Feb 6 2020

warning('off','MATLAB:strrep:InvalidInputType')

%Find out how many modules there are.
nMods = numel(RUNTIME.TDT.name);
       
for i = 1:nMods
    dinfo(i).tags = {[]};
    dinfo(i).datatypes = {[]};
end
    

%Get Gizmo Names
gizmo_names = SYN.getGizmoNames();

% gizmo_names = matlab.lang.makeValidName(gizmo_names);
% i = ~cellfun(@isempty,regexp(gizmo_names,'_\d_'));
% gizmo_names(i) = cellfun(@(a) a(1:end-1),gizmo_names(i),'uni',0);


%For each gizmo..
for j = 1:numel(gizmo_names)
    gizmo = gizmo_names{j};
    
    %Find the parent module
    module = SYN.getGizmoParent(gizmo);
    
    %Find the appropriate index for the module
    if isempty(module) %~module
        for m = 1:nMods
            modInfo = SYN.getGizmoInfo(RUNTIME.TDT.name{m});
            if strcmp(modInfo.cat,'Legacy')
                ind = m;
                break
            end
        end
        
    else
        continue % skip this extraneous info for now
%         module = module(1:regexp(module,'\_')-1);
%         ind = find(cell2mat(cellfun(@(x) ~isempty(x),strfind(RUNTIME.TDT.name,module),'UniformOutput',false)));
    end
    
    %Read the parameter tags
    params = SYN.getParameterNames(gizmo);
    
    %Abort if there are no tags
    if isempty(params)
        continue
    end
    
    kk = 0;
    
    %For each parameter
    for k = 1:numel(params)
        param = params{k};
        
        %Abort if the tag is an OpenEx proprietary tag
        if any(ismember(param,'/\|')) || ~isempty(strfind(param,'rPvDsHElpEr')) %#ok<*STREMP>
            continue
        end
        
        %Otherwise, get datatype for the parameter
        try
            info = SYN.getParameterInfo(gizmo,param);
            paramtype = info.Type;
        catch
            paramtype = 'Trig'; %probably a trigger embedded in an epsych macro
        end
        
        kk = kk+1;
        %Append to cell array
        dinfo(ind).tags{kk} = param; %#ok<*AGROW>
        dinfo(ind).datatypes{kk} = paramtype; 
    end

end

%Append to RUNTIME Structure
for i = 1:nMods
    RUNTIME.TDT.devinfo(i).tags = dinfo(i).tags;
    RUNTIME.TDT.devinfo(i).datatype = dinfo(i).datatypes;
    RUNTIME.TDT.tags{i} = dinfo(i).tags;
    RUNTIME.TDT.datatypes{i} = dinfo(i).datatypes;
end

if nargout > 1
    varargout{1} = dinfo;
end


warning('on','MATLAB:strrep:InvalidInputType')
