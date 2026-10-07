function lines = formatTable(T, delimiter, quoted)
% lines = formatTable(T, delimiter, quoted)
% A table as text lines (header first), one cell formatted the same way for
% every text export: logicals TRUE/FALSE, datetimes ISO 8601, numbers to 10
% significant digits, and a number that is not finite as an EMPTY field.
%
% quoted = true quotes a field holding the delimiter, a quote, a line break
% or edge spaces (CSV); false replaces tabs and line breaks by a space (TSV).
%
% Returns:
%   lines - string column, header then one line per row; no trailing newline.

arguments
    T table
    delimiter (1,1) string
    quoted (1,1) logical
end

n = height(T);
names = string(T.Properties.VariableNames);
m = numel(names);
if m == 0
    lines = "";
    return
end

cells = strings(n, m);
for j = 1:m
    cells(:, j) = localColumn(T.(names(j)), n);
end
cells = localProtect(cells, delimiter, quoted);
head = localProtect(names, delimiter, quoted);

lines = join(head, delimiter);
if n > 0
    lines = [lines; join(cells, delimiter, 2)];
end
end


function s = localColumn(v, n)
% One column as n strings.
if iscell(v)
    v = cellfun(@(x) strjoin(reshape(string(x), 1, []), "|"), v);
end
if isdatetime(v)
    s = string(v, behavior.Export.TIME_FORMAT);
    s(isnat(v)) = "";
elseif islogical(v)
    s = repmat("FALSE", size(v));
    s(v) = "TRUE";
elseif isduration(v)
    s = localNumbers(seconds(v));
elseif isnumeric(v)
    s = localNumbers(double(v));
else
    s = string(v);
end
s = reshape(s, n, 1);
s(ismissing(s)) = "";
end


function s = localNumbers(x)
s = strings(size(x));
ok = isfinite(x);
s(ok) = compose("%.10g", x(ok));
end


function c = localProtect(c, delimiter, quoted)
if quoted
    needs = contains(c, [delimiter, """", newline, char(13)]) | startsWith(c, " ") | endsWith(c, " ");
    c(needs) = """" + replace(c(needs), """", """""") + """";
else
    c = replace(c, [string(char(9)), newline, string(char(13))], " ");
end
end
