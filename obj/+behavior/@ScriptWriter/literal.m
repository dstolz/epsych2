function txt = literal(v, options)
% txt = behavior.ScriptWriter.literal(v)
% txt = behavior.ScriptWriter.literal(v, LineWidth=96, Indent=4)
% MATLAB source text that evaluates back to v exactly: eval(txt) is isequaln
% to v, of the same class and the same size.
%
% A generated script is a record of an analysis only if every value in it is
% the value the analysis used, so nothing here is approximate: a double is
% written in the shortest decimal that reads back to the same bits (never
% more than %.17g); NaN, Inf, -Inf and -0 survive; an empty keeps its size;
% text keeps every character -- control and non-ASCII characters are written
% as char codes rather than escaped, so no reader has to decode them by hand;
% a datetime keeps its sub-millisecond time, its zone and its display format;
% a struct keeps its field order; a table its variable and row names.
%
% Supported: double, single, the integer classes, logical, char, string,
% cell, struct (arrays too), datetime, duration, categorical, enumerations
% (written Class.Member), and table. Anything else -- a function handle, a
% graphics object, an arbitrary object -- throws behavior:ScriptWriter:Unsupported,
% because a value that cannot be written down must not quietly become
% something else. Complex numbers are not supported either.
%
% Long lists are continued with "..." at LineWidth, continuation lines
% indented by Indent spaces, so the text can be pasted into a script as is.
%
% Parameters:
%   v         - The value.
%   LineWidth - Characters per line before a continuation (default
%               behavior.ScriptWriter.LineWidth).
%   Indent    - Spaces at the start of a continuation line (default 4).
%
% Returns:
%   txt - char, possibly several lines.
%
% See also: behavior.ScriptWriter, isequaln

arguments
    v
    options.LineWidth (1,1) double {mustBePositive} = behavior.ScriptWriter.LineWidth
    options.Indent (1,1) double {mustBeNonnegative, mustBeInteger} = 4
end

txt = localLiteral(v, options.LineWidth, options.Indent);

end



function txt = localLiteral(v, width, indent)
% Dispatch by kind. Enumerations come before numerics because an enumeration
% class may derive from a numeric one (epsych.BitMask < uint32).
if isa(v, 'table')
    txt = localTable(v, width, indent);
elseif iscategorical(v)
    txt = localCategorical(v, width, indent);
elseif isenum(v)
    txt = localEnum(v, width, indent);
elseif isdatetime(v)
    txt = localDatetime(v, width, indent);
elseif isduration(v)
    txt = localDuration(v, width, indent);
elseif isstring(v)
    txt = localString(v, width, indent);
elseif ischar(v)
    txt = localChar(v, width, indent);
elseif iscell(v)
    txt = localCell(v, width, indent);
elseif isstruct(v)
    txt = localStruct(v, width, indent);
elseif islogical(v)
    txt = localLogical(v, width, indent);
elseif isnumeric(v)
    txt = localNumeric(v, width, indent);
else
    error('behavior:ScriptWriter:Unsupported', ...
        'A %s cannot be written as a literal.', class(v));
end
end



% ---------------------------------------------------------------- numbers
function txt = localNumeric(v, width, indent)
cls = class(v);
if ~isreal(v)
    error('behavior:ScriptWriter:Unsupported', 'A complex %s cannot be written as a literal.', cls);
end
if isempty(v)
    if isa(v, 'double') && isequal(size(v), [0 0])
        txt = '[]';
    else
        txt = sprintf('zeros(%s, ''%s'')', localSizeList(size(v)), cls);
    end
    return
end

isSingle = isa(v, 'single');
elems = arrayfun(@(x) localNumber(x, isSingle), v(:), 'UniformOutput', false);
body = localArray(elems, size(v), width, indent);
if isa(v, 'double')
    txt = body;
else
    txt = sprintf('%s(%s)', cls, body);
end
end



function s = localNumber(x, isSingle)
% One number as text that reads back to the same value of the same class.
if isinteger(x)
    s = char(string(x));   % exact for 64-bit values too, where %d falls back to %e
    return
end
if isnan(x)
    s = 'NaN';
    return
end
if isinf(x)
    if x > 0, s = 'Inf'; else, s = '-Inf'; end
    return
end
if x == 0
    if 1 / x < 0, s = '-0'; else, s = '0'; end
    return
end

% The shortest decimal that survives the round trip. A single is compared
% after narrowing, since its literal is read as a double and cast back.
if isSingle
    precisions = 6:9;
else
    precisions = 15:17;
end
for p = precisions
    s = sprintf('%.*g', p, x);
    back = str2double(s);
    if isSingle, back = single(back); end
    if back == x
        return
    end
end
s = sprintf('%.17g', x);
end



% --------------------------------------------------------------- logicals
function txt = localLogical(v, width, indent)
if isscalar(v)
    if v, txt = 'true'; else, txt = 'false'; end
    return
end
if isempty(v) || all(~v(:))
    txt = sprintf('false(%s)', localSizeList(size(v)));
    return
end
if all(v(:))
    txt = sprintf('true(%s)', localSizeList(size(v)));
    return
end
elems = arrayfun(@(x) char('0' + x), v(:), 'UniformOutput', false);
txt = sprintf('logical(%s)', localArray(elems, size(v), width, indent));
end



% ------------------------------------------------------------------- text
function tf = localIsPlainText(codes)
% Printable ASCII only: what a quoted literal can carry without any escape.
tf = all(codes >= 32 & codes <= 126);
end



function txt = localChar(v, width, indent)
sz = size(v);
if isequal(sz, [0 0])
    txt = '''''';
    return
end
if isempty(v)
    txt = sprintf('char(zeros(%s))', localSizeList(sz));
    return
end
codes = double(v);
if isrow(v) && localIsPlainText(codes)
    txt = ['''' strrep(v, '''', '''''') ''''];
    return
end
% Control or non-ASCII characters, or a char matrix: the codes themselves.
elems = arrayfun(@(c) sprintf('%d', c), codes(:), 'UniformOutput', false);
txt = sprintf('char(%s)', localArray(elems, sz, width, indent));
end



function txt = localString(v, width, indent)
if isempty(v)
    txt = sprintf('strings(%s)', localSizeList(size(v)));
    return
end
if isscalar(v)
    txt = localStringScalar(v, width, indent);
    return
end
elems = arrayfun(@(s) localStringScalar(s, width, indent), v(:), 'UniformOutput', false);
txt = localArray(elems, size(v), width, indent);
end



function txt = localStringScalar(s, width, indent)
if ismissing(s)
    txt = 'string(missing)';
    return
end
c = char(s);
if isempty(c)
    txt = '""';
    return
end
if localIsPlainText(double(c))
    txt = ['"' strrep(c, '"', '""') '"'];
    return
end
txt = sprintf('string(%s)', localChar(c, width, indent));
end



% ------------------------------------------------------------ containers
function txt = localCell(v, width, indent)
if isempty(v)
    txt = sprintf('cell(%s)', localSizeList(size(v)));
    return
end
elems = cellfun(@(x) localLiteral(x, width, indent + 4), v(:), 'UniformOutput', false);
txt = localArray(elems, size(v), width, indent, '{', '}', ',');
end



function txt = localStruct(v, width, indent)
names = fieldnames(v);
sz = size(v);
if isempty(v)
    if isempty(names)
        txt = sprintf('struct.empty(%s)', localSizeList(sz));
    else
        args = strjoin(cellfun(@(n) sprintf('''%s'', {}', n), names, 'UniformOutput', false), ', ');
        txt = sprintf('struct(%s)', args);
        if ~isequal(sz, [0 0])
            txt = sprintf('reshape(%s, %s)', txt, localSizeList(sz));
        end
    end
    return
end

if isscalar(v)
    txt = localStructScalar(v, names, width, indent);
    return
end
elems = arrayfun(@(s) localStructScalar(s, names, width, indent + 4), v(:), 'UniformOutput', false);
txt = localArray(elems, sz, width, indent, '[', ']', ',');
end



function txt = localStructScalar(s, names, width, indent)
% Every value wrapped in a cell, so a cell or an array value does not expand
% the struct into an array.
if isempty(names)
    txt = 'struct()';
    return
end
parts = cell(1, numel(names));
for k = 1:numel(names)
    parts{k} = sprintf('''%s'', {%s}', names{k}, localLiteral(s.(names{k}), width, indent + 4));
end
txt = localJoinCall('struct', parts, width, indent);
end



% ------------------------------------------------------------------ times
function txt = localDatetime(v, width, indent)
% ISO text when it carries the value to the last bit; else the millisecond
% text plus what is left of it; else the epoch plus milliseconds in two
% parts. A datetime holds more than one double's worth of precision (a time
% read off the clock has a sub-millisecond part no text format holds), and
% each tier is verified by reading it back before it is written.
tz = v.TimeZone;
tzArg = '';
if ~isempty(tz), tzArg = sprintf(', TimeZone=''%s''', tz); end
fmtArg = '';
if ~isempty(v.Format), fmtArg = sprintf(', Format=''%s''', strrep(v.Format, '''', '''''')); end

if isempty(v) || all(isnat(v(:)))
    txt = sprintf('NaT(%s%s%s)', localSizeList(size(v)), tzArg, fmtArg);
    return
end

fmts = {'yyyy-MM-dd''T''HH:mm:ss', 'yyyy-MM-dd''T''HH:mm:ss.SSS', 'yyyy-MM-dd''T''HH:mm:ss.SSSSSSSSS'};
for k = 1:numel(fmts)
    [strs, back] = localDatetimeText(v, fmts{k});
    if isequaln(back, v)
        txt = sprintf('datetime(%s, InputFormat=''%s''%s%s)', localQuotedArray(strs, width, indent), ...
            strrep(fmts{k}, '''', ''''''), tzArg, fmtArg);
        return
    end
end

[strs, base] = localDatetimeText(v, fmts{2});
rest = milliseconds(v - base);
rest(isnat(v)) = 0;
if isequaln(base + milliseconds(rest), v)
    txt = sprintf('datetime(%s, InputFormat=''%s''%s%s) + milliseconds(%s)', ...
        localQuotedArray(strs, width, indent), strrep(fmts{2}, '''', ''''''), tzArg, fmtArg, ...
        localNumeric(rest, width, indent));
    return
end

if isempty(tz)
    E = datetime(1970, 1, 1);
else
    E = datetime(1970, 1, 1, 'TimeZone', tz);
end
hi = milliseconds(v - E);
lo = milliseconds(v - (E + milliseconds(hi)));
lo(isnan(hi)) = NaN;
txt = sprintf('datetime(1970, 1, 1%s%s) + milliseconds(%s)', tzArg, fmtArg, localNumeric(hi, width, indent));
if any(lo(:) ~= 0 & ~isnan(lo(:)))
    txt = sprintf('%s + milliseconds(%s)', txt, localNumeric(lo, width, indent));
end
end



function [strs, back] = localDatetimeText(v, fmt)
% The datetimes as text in fmt (NaT written as "NaT"), and what that text
% reads back as in the same zone.
strs = string(v, fmt);
strs(isnat(v)) = "NaT";
if isempty(v.TimeZone)
    back = datetime(strs, 'InputFormat', fmt);
else
    back = datetime(strs, 'InputFormat', fmt, 'TimeZone', v.TimeZone);
end
end



function txt = localQuotedArray(strs, width, indent)
% A string array of plain text as a "..." literal, scalar or bracketed.
if isscalar(strs)
    txt = sprintf('"%s"', strs);
    return
end
elems = arrayfun(@(s) sprintf('"%s"', s), strs(:), 'UniformOutput', false);
txt = localArray(elems, size(strs), width, indent);
end



function txt = localDuration(v, width, indent)
% milliseconds is the duration's own unit, so the double round-trips exactly.
txt = sprintf('milliseconds(%s)', localNumeric(milliseconds(v), width, indent));
end



% ------------------------------------------------------------- categories
function txt = localCategorical(v, width, indent)
cats = string(categories(v));
vals = string(v);          % missing where undefined
txt = sprintf('categorical(%s, %s', localString(vals, width, indent), ...
    localString(reshape(cats, 1, []), width, indent));
if isordinal(v)
    txt = [txt ', Ordinal=true'];
end
txt = [txt ')'];
end



function txt = localEnum(v, width, indent)
cls = class(v);
if isempty(v)
    txt = sprintf('%s.empty(%s)', cls, localSizeList(size(v)));
    return
end
elems = arrayfun(@(e) sprintf('%s.%s', cls, char(e)), v(:), 'UniformOutput', false);
txt = localArray(elems, size(v), width, indent);
end



% ------------------------------------------------------------------ tables
function txt = localTable(T, width, indent)
names = T.Properties.VariableNames;
if isempty(names)
    txt = sprintf('table.empty(%d, 0)', height(T));
    return
end
parts = cell(1, numel(names));
for k = 1:numel(names)
    parts{k} = localLiteral(T.(names{k}), width, indent + 4);
end
parts{end+1} = sprintf('VariableNames=%s', localString(string(names), width, indent + 4));
if ~isempty(T.Properties.RowNames)
    parts{end+1} = sprintf('RowNames=%s', localString(string(T.Properties.RowNames), width, indent + 4));
end
txt = localJoinCall('table', parts, width, indent);
end



% ------------------------------------------------------------- formatting
function s = localSizeList(sz)
s = strjoin(arrayfun(@(d) sprintf('%d', d), sz, 'UniformOutput', false), ', ');
end



function txt = localArray(elems, sz, width, indent, open, close, sep)
% Bracketed, row-major text of elements given in column-major order; an N-D
% array is a reshape of its column-major list.
if nargin < 5
    open = '[';
    close = ']';
    sep = '';
end
if isscalar(elems) && isempty(sep)
    txt = elems{1};
    return
end
if numel(sz) > 2
    txt = sprintf('reshape(%s, [%s])', ...
        localArray(elems, [1 numel(elems)], width, indent, open, close, sep), localSizeList(sz));
    return
end
nRows = sz(1);
nCols = sz(2);
tokens = cell(1, numel(elems));
t = 0;
for r = 1:nRows
    for c = 1:nCols
        t = t + 1;
        if c < nCols
            suffix = sep;
        elseif r < nRows
            suffix = ';';
        else
            suffix = '';
        end
        tokens{t} = [elems{(c - 1) * nRows + r} suffix];
    end
end
txt = localJoin(tokens, open, close, width, indent);
end



function txt = localJoinCall(fname, parts, width, indent)
% fname(part1, part2, ...) continued at LineWidth.
tokens = parts;
for k = 1:numel(tokens) - 1
    tokens{k} = [tokens{k} ','];
end
txt = localJoin(tokens, [fname '('], ')', width, indent);
end



function txt = localJoin(tokens, open, close, width, indent)
% open + tokens separated by one space + close, broken with "..." where a
% token would carry the line past width. A token that is itself several lines
% (a nested literal) is measured by its last line.
n = numel(tokens);

% Pass 1: where the breaks go, from lengths alone. A multi-line token leaves
% the line as long as its own last line.
firstLen = zeros(1, n);
lastLen = -ones(1, n);          % -1: single-line token
for k = 1:n
    L = splitlines(string(tokens{k}));
    firstLen(k) = strlength(L(1));
    if numel(L) > 1
        lastLen(k) = strlength(L(end));
    end
end
breakBefore = false(1, n);
curLen = numel(open) + firstLen(1);
if lastLen(1) >= 0, curLen = lastLen(1); end
for k = 2:n
    if curLen + 1 + firstLen(k) > width
        breakBefore(k) = true;
        curLen = indent + firstLen(k);
    else
        curLen = curLen + 1 + firstLen(k);
    end
    if lastLen(k) >= 0, curLen = lastLen(k); end
end

% Pass 2: the lines themselves.
pad = repmat(' ', 1, indent);
starts = [1 find(breakBefore)];
stops = [starts(2:end) - 1, n];
lines = cell(1, numel(starts));
for j = 1:numel(starts)
    if j == 1, prefix = open; else, prefix = pad; end
    if j < numel(starts), suffix = ' ...'; else, suffix = close; end
    lines{j} = [prefix strjoin(tokens(starts(j):stops(j)), ' ') suffix];
end
txt = strjoin(lines, newline);
end
