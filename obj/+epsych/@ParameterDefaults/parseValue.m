function [value, ok, message] = parseValue(text, P)
% [value, ok, message] = epsych.ParameterDefaults.parseValue(text, P)
% Read what an operator typed into the editor's Default cell as a value for
% hw.Parameter P.
%
% Blank is not an error: it means "no default", and comes back as [] with ok
% true. Numbers are read without eval -- each token of a comma, semicolon or
% space separated list goes through str2double, optionally inside [ ] -- so a
% cell in a window that ends up on the hardware can never run code. Booleans
% accept true/false, 1/0, on/off and yes/no. String and File parameters take
% the text as typed.
%
% Range, integer levels and pairing are not checked here; that is
% epsych.ParameterDefaults.check, which needs the bounds the same row may be
% changing.
%
% Parameters:
%   text - char/string from the editor.
%   P    - hw.Parameter the value is for.
%
% Returns:
%   value   - double row vector, logical scalar, char, or [] for blank.
%   ok      - false when the text cannot be read as P's type.
%   message - why not, for the status line.
%
% See also: epsych.ParameterDefaults.formatValue, epsych.ParameterDefaults.check

value = [];
ok = true;
message = '';

text = strtrim(char(string(text)));
if isempty(text), return, end

switch P.Type
    case {'Float','Integer'}
        body = regexprep(text, '^\[\s*|\s*\]$', '');
        tokens = regexp(strtrim(body), '[,;\s]+', 'split');
        tokens = tokens(~cellfun(@isempty, tokens));
        v = str2double(tokens);
        if isempty(v) || any(isnan(v)) || any(~isfinite(v))
            ok = false;
            message = sprintf(['"%s" is not a number or a list of numbers. ' ...
                'Separate several levels with commas.'], text);
            return
        end
        value = v;

    case 'Boolean'
        switch lower(text)
            case {'true','1','on','yes'}
                value = true;
            case {'false','0','off','no'}
                value = false;
            otherwise
                ok = false;
                message = sprintf('"%s" is not true or false.', text);
        end

    otherwise
        value = text;
end
end
