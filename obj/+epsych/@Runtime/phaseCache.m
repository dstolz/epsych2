function varargout = phaseCache(action, filepath, entry)
% varargout = epsych.Runtime.phaseCache(action, filepath, entry)
% Session-lifetime memo for parsed phase files, backing phaseParameterData.
%
% One preview-plus-load of a phase asks for the same file three times (the
% dropdown preview, the pre-load snapshot, and the apply pass), and browsing a
% list of phases asks once per selection. Parsing an .eprot is expensive --
% Protocol.load rebuilds every interface, module, parameter and stimgen object
% before phaseParameterData serializes them straight back to structs -- so the
% result is memoized here instead.
%
% Entries are keyed on the file's canonical path, modification time, and size,
% so a phase re-saved mid-session is re-parsed automatically. The cache holds
% only value data (see phaseParameterData), never handles, so a hit is
% indistinguishable from a fresh parse.
%
% Actions:
%   [hit, entry] = phaseCache('get', filepath)   Look up a parsed file.
%                  phaseCache('put', filepath, entry)  Store a parse result.
%                  phaseCache('parsed')          Record that a parse occurred.
%                  phaseCache('clear' [, file])  Drop one file, or everything.
%                  phaseCache('disable')         Turn caching off (and empty it).
%                  phaseCache('enable')          Turn caching back on.
%   stats        = phaseCache('stats')           .Hits .Parses .Entries .Enabled
%                  phaseCache('resetstats')      Zero the counters.
%
% `clear functions` also empties the cache.
%
% See also: phaseParameterData, readParameters, writeParametersProtocol

arguments
    action (1,1) string
    filepath (1,:) string = ""
    entry = []
end

% Capped at a small number of entries: enough to make dropdown browsing free,
% small enough that StimType phases carrying calibration vectors cannot grow
% the session's memory without bound.
MAXENTRIES = 8;

persistent KEYS VALS ENABLED HITS PARSES

if isempty(ENABLED), ENABLED = true;         end
if isempty(KEYS),    KEYS = strings(1,0); VALS = {}; end
if isempty(HITS),    HITS = 0;               end
if isempty(PARSES),  PARSES = 0;             end

varargout = {};

switch lower(action)
    case 'get'
        varargout = {false, []};
        if ~ENABLED, return, end
        key = localKey(filepath);
        if strlength(key) == 0, return, end
        idx = find(KEYS == key, 1);
        if isempty(idx), return, end

        value = VALS{idx};
        KEYS(idx) = []; VALS(idx) = [];
        KEYS = [key KEYS]; VALS = [{value} VALS];   % most-recently-used first
        HITS = HITS + 1;
        varargout = {true, value};

    case 'put'
        if ~ENABLED, return, end
        key = localKey(filepath);
        if strlength(key) == 0, return, end
        idx = find(KEYS == key, 1);
        if ~isempty(idx), KEYS(idx) = []; VALS(idx) = []; end
        KEYS = [key KEYS]; VALS = [{entry} VALS];
        if numel(KEYS) > MAXENTRIES
            KEYS(MAXENTRIES+1:end) = [];
            VALS(MAXENTRIES+1:end) = [];
        end

    case 'parsed'
        % Counted separately from 'put' so the tally reflects work actually
        % done, including parses whose result was not cacheable.
        PARSES = PARSES + 1;

    case 'clear'
        if strlength(filepath) == 0
            KEYS = strings(1,0); VALS = {};
            return
        end
        prefix = localPath(filepath);
        if strlength(prefix) == 0
            KEYS = strings(1,0); VALS = {};   % cannot canonicalize; clear all
            return
        end
        drop = startsWith(KEYS, prefix + "|");
        KEYS(drop) = []; VALS(drop) = [];

    case 'disable'
        ENABLED = false;
        KEYS = strings(1,0); VALS = {};

    case 'enable'
        ENABLED = true;

    case 'stats'
        varargout = {struct('Hits', HITS, 'Parses', PARSES, ...
            'Entries', numel(KEYS), 'Enabled', ENABLED)};

    case 'resetstats'
        HITS = 0; PARSES = 0;

    otherwise
        error('epsych:Runtime:phaseCache:UnknownAction', ...
            'Unknown phaseCache action "%s"', action);
end

end


function key = localKey(filepath)
% Path plus modification time plus size: a re-saved phase misses the cache
% without anyone having to remember to invalidate it.
key = "";
d = dir(char(filepath));
if isempty(d) || d(1).isdir, return, end
key = lower(string(fullfile(d(1).folder, d(1).name))) + "|" ...
    + string(sprintf('%.10f', d(1).datenum)) + "|" + string(d(1).bytes);
end


function p = localPath(filepath)
% Canonical, case-folded absolute path. Windows paths are case-insensitive, so
% two spellings of one file must share a key prefix.
p = "";
d = dir(char(filepath));
if isempty(d) || d(1).isdir, return, end
p = lower(string(fullfile(d(1).folder, d(1).name)));
end
