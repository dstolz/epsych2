function files = write(Tbls, folder, options)
% files = behavior.Export.write(Tbls, folder)
% files = behavior.Export.write(Tbls, folder, Formats = ["csv" "xlsx" "mat"], Prefix = "study_")
% Writes the tables from behavior.Export.tables, and the column dictionary.
%
% Parameters:
%   Tbls    - struct of tables (behavior.Export.tables).
%   folder  - destination; created when missing.
%   Formats - "csv" (one <prefix><table>.csv per table, UTF-8), "xlsx" (one
%             <prefix>tables.xlsx, a sheet per table; a table over 1,048,575
%             rows is skipped with a log record) and/or "mat" (one
%             <prefix>export.mat holding the struct EPsychExport). Default csv.
%   Prefix  - file-name prefix (default "epsych_").
%
% <prefix>columns.csv, the dictionary of every column written, is always
% written beside them. A non-finite number is never written: an empty CSV
% field, an empty XLSX cell.
%
% Returns:
%   files - string column, every path written.

arguments
    Tbls (1,1) struct
    folder (1,1) string
    options.Formats (1,:) string = "csv"
    options.Prefix (1,1) string = "epsych_"
end

formats = lower(options.Formats);
bad = formats(~ismember(formats, ["csv" "xlsx" "mat"]));
if ~isempty(bad)
    error('behavior:Export:UnknownFormat', ...
        'Unknown export format "%s"; use csv, xlsx or mat.', strjoin(bad, ", "));
end

if ~isfolder(folder)
    [ok, msg] = mkdir(folder);
    if ~ok
        error('behavior:Export:NoFolder', 'Cannot create "%s": %s', folder, msg);
    end
end

names = string(fieldnames(Tbls))';
files = strings(numel(names) + 3, 1);   % a CSV per table, the workbook, the MAT, the dictionary
nf = 0;

if any(formats == "csv")
    for name = names
        nf = nf + 1;
        files(nf) = localWriteText(fullfile(folder, options.Prefix + name + ".csv"), Tbls.(name));
    end
end

if any(formats == "xlsx")
    book = fullfile(folder, options.Prefix + "tables.xlsx");
    if isfile(book), delete(book); end
    wrote = false;
    for name = names
        X = Tbls.(name);
        if height(X) > behavior.Export.MAX_XLSX_ROWS
            vprintf(1, 'Export: table %s has %d rows, over the %d an Excel sheet holds; left out of the workbook.', ...
                name, height(X), behavior.Export.MAX_XLSX_ROWS);
            continue
        end
        try
            writetable(localFiniteOnly(X), book, 'Sheet', char(extractBetween(name, 1, min(strlength(name), 31))));
            wrote = true;
        catch ME
            vprintf(0, 1, ME);
        end
    end
    if wrote
        nf = nf + 1;
        files(nf) = string(book);
    end
end

if any(formats == "mat")
    file = fullfile(folder, options.Prefix + "export.mat");
    EPsychExport = Tbls;
    save(file, 'EPsychExport');
    nf = nf + 1;
    files(nf) = string(file);
end

D = behavior.Export.dictionary(Tbls);
nf = nf + 1;
files(nf) = localWriteText(fullfile(folder, options.Prefix + "columns.csv"), D);
files = files(1:nf);

end


function path = localWriteText(path, X)
% One table as a UTF-8 CSV file.
lines = formatTable(X, ",", true);
fid = fopen(path, 'w', 'n', 'UTF-8');
if fid < 0
    error('behavior:Export:CannotWrite', 'Cannot open "%s" for writing.', path);
end
closer = onCleanup(@() fclose(fid));
fwrite(fid, unicode2native(char(strjoin(lines, newline) + newline), 'UTF-8'), 'uint8');
clear closer
path = string(path);
end


function X = localFiniteOnly(X)
% Infinities become NaN (an empty cell): none is ever written.
for j = 1:width(X)
    v = X.(j);
    if isnumeric(v)
        v(isinf(v)) = NaN;
        X.(j) = v;
    end
end
end
