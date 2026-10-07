function D = dictionary(Tbls)
% D = behavior.Export.dictionary(Tbls)
% The schema rows of the columns the tables actually hold, the dynamic
% tag_<k> and group_<name> placeholders expanded. It is what write() saves
% as <prefix>columns.csv, so the file always describes the files beside it.
%
% Parameters:
%   Tbls - struct of tables (behavior.Export.tables).
%
% Returns:
%   D - table Table, Column, Type, Unit, Meaning, in table then column order.

arguments
    Tbls (1,1) struct
end

S = behavior.Export.schema();
tables = behavior.Export.TABLES;
parts = cell(1, numel(tables));
for t = 1:numel(tables)
    name = tables(t);
    if ~isfield(Tbls, name), continue, end
    rows = S(S.Table == name, :);
    cols = string(Tbls.(name).Properties.VariableNames);
    found = cell(1, numel(cols));
    for j = 1:numel(cols)
        col = cols(j);
        k = find(rows.Column == col, 1);
        if ~isempty(k)
            row = rows(k, :);
        elseif ~isempty(regexp(col, '^tag_\d+$', 'once'))
            row = rows(rows.Column == "tag_<k>", :);
            row.Column = col;
            row.Meaning = replace(row.Meaning, "Tag k", "Tag " + extractAfter(col, "tag_"));
        elseif startsWith(col, "group_")
            row = rows(rows.Column == "group_<name>", :);
            row.Column = col;
            row.Meaning = replace(row.Meaning, "<name>", extractAfter(col, "group_"));
        else
            continue    % not in the schema: tables() never produces one
        end
        found{j} = row;
    end
    found = found(~cellfun(@isempty, found));
    parts{t} = vertcat(S([], :), found{:});
end
parts = parts(~cellfun(@isempty, parts));
D = vertcat(S([], :), parts{:});
end
