function idx = interfaceIndexForLabel(obj, label)
% idx = interfaceIndexForLabel(obj, label)
% Current position of the interface a dropdown label names, whatever position
% the label recorded.
%
% Interface labels lead with their position ('3: TDT_RPcox'), so removing an
% earlier interface renames every later one and a plain text match against the
% new items loses it. Protocol.addInterface allows one interface per type, so
% the type after the colon still identifies the interface once its position no
% longer does.
%
% Parameters:
%	label	- Dropdown value, e.g. '3: TDT_RPcox', 'All Interfaces', '<none>'.
%
% Returns:
%	idx	- 1-based position in Protocol.Interfaces; 0 when the label names no
%		  interface at all; -1 when it names one the protocol no longer has.
    tokens = regexp(char(string(label)), '^\d+:\s*(.+)$', 'tokens', 'once');
    if isempty(tokens)
        idx = 0;
        return
    end

    types = arrayfun(@(iface) char(string(iface.Type)), obj.Protocol.Interfaces, 'UniformOutput', false);
    idx = find(strcmp(types, strtrim(tokens{1})), 1);
    if isempty(idx)
        idx = -1;
    end
end
