function cl_SaveDataFcn(RUNTIME)
% cl_SaveDataFcn(RUNTIME)
% 
% Default function fo saving behavioral data
% 
% Use ep_RunExpt GUI to specify custom function.
% 
% Daniel.Stolzberg@gmail.com 2025

% Copyright (C) 2016  Daniel Stolzberg, PhD

hcDefaultPath = "D:\matlab_data_files";

for i = 1:RUNTIME.NSubjects
    name  = RUNTIME.TRIALS(i).Subject.Name;
    boxid = RUNTIME.TRIALS(i).Subject.BoxID;

    vprintf(3,'Save Data for ''%s'' in Box ID %d',name,boxid)

    h = msgbox(sprintf('Save Data for ''%s'' in Box ID %d',name,boxid), ...
        'Save Behavioural Data','help','modal');
    
    uiwait(h);
    
    subjPath = fullfile(hcDefaultPath,name);
    
    if ~isfolder(subjPath), mkdir(subjPath); end
    

    if isfield(RUNTIME.TRIALS(i),'DataFilename') && ~isempty(RUNTIME.TRIALS(i).DataFilename)
        % use existing filename if available
        ffn = RUNTIME.TRIALS(i).DataFilename;
    else
        % otherwise use default location
        ffn = ep_RunExpt2.defaultFilename(subjPath,name);
    end
    
    
    % prompt user for file location
    % suggest default location
    [fn,pn] = uiputfile({'*.mat','MATLAB File'}, ...
        sprintf('Save ''%s (%d)'' Data',name,boxid), ...
        ffn);
    
    % user cancelled
    if fn == 0
        vprintf(0,1,'NOT SAVING DATA FOR SUBJECT ''%s'' IN BOX ID %d',name,boxid);
        continue
    end
    
    fileloc = fullfile(pn,fn);
    
    Data = RUNTIME.TRIALS(i).DATA;
    
    save(fileloc,'Data')
    
end











