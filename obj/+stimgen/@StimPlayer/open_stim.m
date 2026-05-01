function open_stim(obj, stimObj, options)
% open_stim(obj, stimObj)
% open_stim(obj, stimObj, Name=name)
% Add an existing StimType object to the StimPlayer bank and select it.
%
% Parameters:
%   stimObj - stimgen.StimType object to append to the bank.
%   Name=   - Optional display name for the new bank item.

arguments
    obj (1,1) stimgen.StimPlayer
    stimObj (1,1) stimgen.StimType
    options.Name (1,1) string = ""
end

sp = stimgen.StimPlay(stimObj);
if options.Name == ""
    name = string(stimObj.DisplayName);
    if name == ""
        className = string(class(stimObj));
        parts = split(className, ".");
        name = parts(end);
    end
else
    name = options.Name;
end
sp.Name = name;
sp.SelectionType = "Serial";

obj.StimPlayObjs(end + 1, 1) = sp;
obj.refresh_listbox_();

if isfield(obj.handles, 'BankList') && isvalid(obj.handles.BankList)
    obj.handles.BankList.Value = numel(obj.StimPlayObjs);
    obj.on_bank_selection_changed(obj.handles.BankList, []);
end

vprintf(2, 'StimPlayer: opened existing stimulus "%s"', char(name));
end
