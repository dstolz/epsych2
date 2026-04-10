function onInfoChanged(obj)
    if isempty(obj.EditInfo) || ~isvalid(obj.EditInfo)
        return
    end
    obj.Protocol.Info = obj.EditInfo.Value;
    obj.LabelStatus.Text = 'Protocol info updated';
end

