function p = parseName(base)
% p = behavior.Catalog.parseName(base)
% What a session file's name says: the subject it was saved under, when, the
% collision letter, and the free tags after the timestamp.
%
% Names have taken two shapes (epsych.RunExpt.defaultFilename, and the
% date-only names of older saving functions):
%
%   <subject>_<yyMMddTHHmmss>[_<A-Z>][_tag...]    Start to the second
%   <subject>_<dd-MMM-yyyy>[_tag...]               Start to the day
%
% The subject prefix is matched lazily, so the FIRST timestamp wins and a
% subject with underscores in its name (Rat_7_B) survives. After the stamp,
% the tokens between underscores are tags, in order, with no meaning attached
% -- except that a single capital letter in the FIRST position is
% defaultFilename's collision letter (the second session saved in the same
% second), not a tag. A single letter anywhere else is a tag.
%
%   parseName("Rat_7_B_261007T114223_A_Post_Noise")
%     NameSubject "Rat_7_B", Collision "A", Tags ["Post" "Noise"]
%
% Parameters:
%   base - File name, with or without its .mat/.epj extension (no folder).
%
% Returns:
%   p - Struct:
%       NameSubject - text before the timestamp ("" when unparsed)
%       Start       - datetime from the name (NaT when unparsed)
%       Precision   - "second", "day", or ""
%       Collision   - the collision letter, or ""
%       Tags        - (1,:) string of tags, in order
%       Parsed      - true when either shape matched
%       Format      - "stamp", "legacy", or ""
%
% See also: behavior.Catalog, epsych.SessionFiles.summarize

arguments
    base (1,1) string
end

name = char(base);
name = regexprep(name, '\.(mat|epj)$', '', 'ignorecase');

p = struct( ...
    'NameSubject', "", ...
    'Start',       NaT, ...
    'Precision',   "", ...
    'Collision',   "", ...
    'Tags',        strings(1,0), ...
    'Parsed',      false, ...
    'Format',      "");

rest = '';
tok = regexp(name, '^(?<prefix>.+?)_(?<stamp>\d{6}T\d{6})(?<rest>|_.*)$', 'names', 'once');
if ~isempty(tok)
    t = localParse(tok.stamp, 'yyMMdd''T''HHmmss');
    if ~isnat(t)
        p.NameSubject = string(tok.prefix);
        p.Start = t;
        p.Precision = "second";
        p.Format = "stamp";
        p.Parsed = true;
        rest = tok.rest;
    end
end

if ~p.Parsed
    tok = regexp(name, '^(?<prefix>.+?)_(?<date>\d{2}-[A-Za-z]{3}-\d{4})(?<rest>|_.*)$', 'names', 'once');
    if ~isempty(tok)
        t = localParse(tok.date, 'dd-MMM-yyyy');
        if ~isnat(t)
            p.NameSubject = string(tok.prefix);
            p.Start = t;
            p.Precision = "day";
            p.Format = "legacy";
            p.Parsed = true;
            rest = tok.rest;
        end
    end
end

% rest keeps its leading underscore: MATLAB drops a named token that sits
% inside an optional group, so the separator is matched as part of it.
rest = regexprep(rest, '^_', '');
if ~p.Parsed || isempty(rest), return, end

tokens = string(strsplit(rest, '_'));
tokens = tokens(strlength(tokens) > 0);
if p.Format == "stamp" && ~isempty(tokens) && ~isempty(regexp(tokens(1), '^[A-Z]$', 'once'))
    p.Collision = tokens(1);
    tokens(1) = [];
end
p.Tags = reshape(tokens, 1, []);

end




function t = localParse(txt, fmt)
% A datetime from text, or NaT when the text only looks like a timestamp.
try
    t = datetime(txt, 'InputFormat', fmt, 'Locale', 'en_US');
    t.Format = 'yyyy-MM-dd HH:mm:ss';
catch
    t = NaT;
end
end
