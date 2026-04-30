function onInfoChanged(obj)
% onInfoChanged(obj)
% Copy the info editor text into obj.Protocol.Info and mark the protocol modified.
    if isempty(obj.EditInfo) || ~isvalid(obj.EditInfo)
        return
    end
    obj.Protocol.Info = obj.EditInfo.Value;
    obj.IsModified_ = true;
    obj.setStatus('Protocol info updated', 'Continue editing or save when the description is complete.');
end

