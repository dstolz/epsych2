function cl_SaveDataFcn(RUNTIME)
% cl_SaveDataFcn(RUNTIME)
% 
% Default function fo saving behavioral data
% 
% Use ep_RunExpt GUI to specify custom function.
% 
% Daniel.Stolzberg@gmail.com 2025

% Copyright (C) 2016  Daniel Stolzberg, PhD

hcDefaultPath = "D:\epsych_files\Data"; % DS 11/6/25


% Create modal figure
fig = figure( ...
    'Color','#ffc4c4', ...
    'NumberTitle','off', ...
    'Name','Don''t forget!', ...
    'WindowStyle','modal', ...
    'MenuBar','none', ...
    'ToolBar','none', ...
    'Resize','off', ...
    'Position',[400 400 600 250]);

movegui(fig,'center');

% Header text
uicontrol(fig, ...
    'Style','text', ...
    'String','CLICK A BUTTON TO UPDATE THE APPROPRIATE LOG', ...
    'FontSize',20, ...
    'FontWeight','bold', ...
    'ForegroundColor','k', ...
    'BackgroundColor','#ffc4c4', ...
    'Units','normalized', ...
    'Position',[0.1 0.65 0.8 0.3], ...
    'HorizontalAlignment','center');

% Prepare callbacks as strings that open the URL, resume uiwait, then delete the figure
urlWater = 'https://docs.google.com/spreadsheets/d/16K5feX8aGY3xGdmJ6O37GXMOHygtng-4ZERRrnFiZXk/edit?usp=sharing';
cbWater  = sprintf('web(''%s'',''-browser''); if isvalid(gcbf), uiresume(gcbf); delete(gcbf); end', urlWater);

urlFood  = 'https://docs.google.com/spreadsheets/d/1QALug3eZWdRmkbBWlQZmmFO655eQhyPcufRjBcNrXlg/edit?usp=sharing';
cbFood   = sprintf('web(''%s'',''-browser''); if isvalid(gcbf), uiresume(gcbf); delete(gcbf); end', urlFood);

% WATER button
uicontrol(fig, ...
    'Style','pushbutton', ...
    'String','WATER', ...
    'FontSize',18, ...
    'FontWeight','bold', ...
    'ForegroundColor','white', ...
    'BackgroundColor','#00c91e', ...
    'Units','normalized', ...
    'Position',[0.15 0.30 0.25 0.25], ...
    'Callback',cbWater);


% FOOD button
uicontrol(fig, ...
    'Style','pushbutton', ...
    'String','FOOD', ...
    'FontSize',18, ...
    'FontWeight','bold', ...
    'ForegroundColor','white', ...
    'BackgroundColor','#fab923', ...
    'Units','normalized', ...
    'Position',[0.60 0.30 0.25 0.25], ...
    'Callback',cbFood);

uiwait(fig);
    


for i = 1:RUNTIME.NSubjects
    name  = RUNTIME.TRIALS(i).Subject.Name;
    boxid = RUNTIME.TRIALS(i).Subject.BoxID;

    vprintf(3,'Save Data for ''%s'' in Box ID %d',name,boxid)

    % h = msgbox(sprintf('Save Data for ''%s'' in Box ID %d',name,boxid), ...
    %     'Save Behavioural Data','help','modal');

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











