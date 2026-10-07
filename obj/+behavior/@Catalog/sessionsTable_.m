function T = sessionsTable_(R)
% T = sessionsTable_(R)
%
% The Sessions table from a struct array of rows (blankRow_ shape), built
% column by column so every column keeps its type with any number of rows:
% struct2table would turn equal-length Tags into a string matrix and lose the
% types of an empty table altogether. Non-scalar values (Tags, Fields,
% Candidates, TrialTypes, ParameterMeta, QCFile) are cell columns; Outcome is
% a struct column.

proto = behavior.Catalog.blankRow_([]);
R = [proto, reshape(R, 1, [])];     % the prototype types an empty result
names = fieldnames(proto);
cellCols = ["Tags" "Fields" "Candidates" "TrialTypes" "ParameterMeta" "QCFile"];

cols = cell(1, numel(names));
for i = 1:numel(names)
    f = names{i};
    if ismember(f, cellCols)
        c = reshape({R.(f)}, [], 1);
    else
        c = reshape([R.(f)], [], 1);
    end
    cols{i} = c(2:end);
end

T = table(cols{:}, 'VariableNames', names);

end
