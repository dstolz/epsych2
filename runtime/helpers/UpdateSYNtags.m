function e = UpdateSYNtags(SYN,TRIALS)
% e = UpdateSYNtags(SYN,TRIALS)
% 
% SYN is the handle to the SynapseAPI
% 
% 
% TRIALS.NextIndex is the trial index which will be used to update parameter tags
% running on RPvds circuits
% 
% 
% See also, ReadSYNtags, SetupSYNexpt
% 
% Daniel.Stolzberg@gmail.com 2024


wp = TRIALS.writeparams_;

trial = TRIALS.trials(TRIALS.NextTrialID,:);
module = TRIALS.moduleName;

for i = 1:length(wp)
    e = 0;
    param = wp{i};

    if any(ismember(param,'*!')), continue; end
    
    par = trial{i};
    
    if TRIALS.randparams(i)
        par = par(1) + abs(diff(par)) .* rand(1);
    end

    if isstruct(par) && ~isfield(par,'buffer') 
        % file buffer (usually WAV file) that needs to be loaded
        wfn = fullfile(par.path,par.file);
        par.buffer = audioread(wfn);
        SYN.setParameterVal(module,['~' param '_Size'],par.nsamps);
        e = SYN.setParameterValues(module,param,single(par.buffer(:)'));
        
    elseif isstruct(par)
        % preloaded file buffer
        e = SYN.setParameterValues(module,param,single(par.buffer(:)'));
    
    elseif isscalar(par) % set value
        e = SYN.setParameterValue(module,param,par);
    end
    
    if ~e
        fprintf(2,'** WARNING: Parameter: ''%s'' was not updated **\n',param);
    end
end



