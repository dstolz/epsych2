function txt = toTSV(T)
% txt = behavior.Export.toTSV(T)
% Tab-separated text of any table, header first, cells formatted exactly as
% in the CSV export (non-finite numbers empty, TRUE/FALSE, ISO datetimes).
% Tabs and line breaks inside a text cell become spaces, so a paste into a
% spreadsheet keeps one cell per field. No trailing newline.
%
% Returns:
%   txt - string scalar, height(T) + 1 lines.

arguments
    T table
end

txt = strjoin(formatTable(T, string(char(9)), false), newline);
end
