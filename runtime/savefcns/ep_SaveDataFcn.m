function ep_SaveDataFcn(RUNTIME)
% ep_SaveDataFcn(RUNTIME)
% 
% Default function fo saving behavioral data
% 
% Use ep_RunExpt GUI to specify custom function.
% 
% Daniel.Stolzberg@gmail.com 2014

% Copyright (C) 2025  Daniel Stolzberg, PhD



for i = 1:RUNTIME.NSubjects
    S = RUNTIME.TRIALS(i).Subject;

    vprintf(3,'Save Data for ''%s'' in Box ID %d',S.Name,S.BoxID)
    
    h = msgbox(sprintf('Save Data for ''%s'' in Box ID %d',S.Name,S.BoxID), ...
        'Save Behavioural Data','help','modal');
    
    uiwait(h);
    
    [fn,pn] = uiputfile({'*.mat','MATLAB File'}, ...
        sprintf('Save ''%s (%d)'' Data',S.Name,S.BoxID), ...
        RUNTIME.TRIALS(i).DataFilename);
    
    if fn == 0
        vprintf(0,1,'NOT SAVING DATA FOR SUBJECT ''%s'' IN BOX ID %d', ...
            S.Name,S.BoxID);
        continue
    end
    
    fileloc = fullfile(pn,fn);
    
    Data = RUNTIME.TRIALS(i).DATA;
    
    save(fileloc,'Data')
    
end











