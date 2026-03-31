
function cl_SaveDataFcn(RUNTIME)
% cl_SaveDataFcn(RUNTIME)
%
% Save behavioral data for all subjects in RUNTIME.TRIALS.
%
% This is the default function for saving behavioral data in the ePsych system.
% Use the ep_RunExpt GUI to specify a custom save function if needed.
%
% Parameters:
%   RUNTIME (struct): Structure containing experiment runtime information, including TRIALS and NSubjects fields.
%
% This function prompts the user to update the appropriate log (WATER or FOOD) and then saves each subject's data to a .mat file in the default data directory. If a DataFilename is already specified, it is used; otherwise, the user is prompted for a save location.
%
% For more details, see documentation/cl_SaveDataFcn.md
%
% Copyright (C) 2016-2025 Daniel Stolzberg, PhD
% Contact: Daniel.Stolzberg@gmail.com


hcDefaultPath = "D:\epsych_files\Data"; 

try
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
catch
end


for i = 1:RUNTIME.NSubjects
    name  = RUNTIME.TRIALS(i).Subject.Name;
    boxid = RUNTIME.TRIALS(i).Subject.BoxID;


    % h = msgbox(sprintf('Save Data for ''%s'' in Box ID %d',name,boxid), ...
    %     'Save Behavioural Data','help','modal');

    subjPath = fullfile(hcDefaultPath,name);

    if ~isfolder(subjPath), mkdir(subjPath); end

    Data = RUNTIME.TRIALS(i).DATA;

    if isfield(RUNTIME.TRIALS(i),'DataFilename') && ~isempty(RUNTIME.TRIALS(i).DataFilename)
        % use existing filename if available
        fileloc = RUNTIME.TRIALS(i).DataFilename;
        vprintf('File saving to: "%s"',fileloc)
    else
        vprintf(0,'Save Data for ''%s'' in Box ID %d',name,boxid)
        fileloc = prompt_user(subjPath,name,boxid);
        if isequal(fileloc,0), continue; end
    end

    try
        save(fileloc,'Data')
    catch me
        vprintf(0,1,me);
        vprintf(0,1,'Failed to save the file, try again!')
        fileloc = prompt_user(subjPath,name,boxid);
        if isequal(fileloc,0), continue; end
    end

    vprintf(0,'Data file: "%s"',fileloc)

end


end








function fileloc = prompt_user(subjPath,name,boxid)
% fileloc = prompt_user(subjPath, name, boxid)
%
% Prompt the user for a file location to save subject data.
% Suggests a default location and filename based on subject and box ID.
%
% Parameters:
%   subjPath (char): Directory path for the subject's data.
%   name (char): Subject name.
%   boxid (numeric): Box ID for the subject.
%
% Returns:
%   fileloc (char or 0): Full path to the file selected by the user, or 0 if cancelled.

ffn = epsych.RunExpt.defaultFilename(subjPath,name);

[fn,pn] = uiputfile({'*.mat','MATLAB File'}, ...
    sprintf('Save ''%s (%d)'' Data',name,boxid), ...
    ffn);

if fn == 0
    vprintf(0,1,'NOT SAVING DATA FOR SUBJECT ''%s'' IN BOX ID %d',name,boxid);
    fileloc = 0;
    return
end

fileloc = fullfile(pn,fn);
end