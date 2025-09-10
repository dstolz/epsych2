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

td = datetime('today');
td.Format ="dd-MMM-uuuu";
letters = char(65:90);
for i = 1:RUNTIME.NSubjects
    name  = RUNTIME.TRIALS(i).Subject.Name;
    boxid = RUNTIME.TRIALS(i).Subject.BoxID;

    vprintf(3,'Save Data for ''%s'' in Box ID %d',name,boxid)

    h = msgbox(sprintf('Save Data for ''%s'' in Box ID %d',name,boxid), ...
        'Save Behavioural Data','help','modal');
    
    uiwait(h);
    
    subjPath = fullfile(hcDefaultPath,name);
    
    if ~isfolder(subjPath)
        mkdir(subjPath)
    end
    
    fn = sprintf('%s_%s.mat',name,td);
    ffn = fullfile(subjPath,fn);

    % avoid overwriting existing files
    % append _A, _B, etc.
    k = 1;
    while isfile(ffn)
        fn = sprintf('%s_%s_%s.mat',name,td,letters(k));
        ffn = fullfile(subjPath,fn);
        k = k + 1;
    end
    

    % prompt user for file location
    % suggest default location
    [fn,pn] = uiputfile({'*.mat','MATLAB File'}, ...
        sprintf('Save ''%s (%d)'' Data',name,boxid), ...
        ffn);
    
    % user cancelled
    if fn == 0
        vprintf(0,1,'NOT SAVING DATA FOR SUBJECT ''%s'' IN BOX ID %d\n',name,boxid);
        continue
    end
    
    fileloc = fullfile(pn,fn);
    
    Data = RUNTIME.TRIALS(i).DATA;
    
    save(fileloc,'Data')
    
end











