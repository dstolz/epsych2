function found = readConfigSubjects_(configFile)
% found = epsych.SubjectRoster.readConfigSubjects_(configFile)
% Extract subject metadata and protocol paths from a .ecfg, cheaply.
%
% Reads the raw MAT contents only. SaveConfig flattens each SUBJECT to a plain
% struct before writing, so nothing here needs epsych.Protocol or the hardware
% classes a full LoadConfig would touch — which is what lets the import preview
% open a colleague's config whose backend this rig does not have.
%
% Parameters:
%   configFile - path to a .ecfg file.
%
% Returns:
%   found - (1,:) struct with Name, Sex, Species, Weight, Notes, protocol_fn.
%           Empty when the file is unreadable or holds no subjects.
%
% See also: epsych.SubjectRoster.importFromConfig, epsych.RunExpt.SaveConfig
arguments
    configFile (1,:) char
end

found = struct('Name', {}, 'Sex', {}, 'Species', {}, 'Weight', {}, ...
    'Notes', {}, 'protocol_fn', {});

if ~isfile(configFile)
    vprintf(1, 'Config file not found: %s', configFile);
    return
end

try
    % A .ecfg stores function handles; loading one whose target is missing
    % warns rather than fails, and the warning is noise here.
    warnState = warning('off', 'MATLAB:dispatcher:UnresolvedFunctionHandle');
    restoreWarn = onCleanup(@() warning(warnState));
    S = load(configFile, '-mat', 'config');
catch ME
    vprintf(0, 1, ME);
    return
end

if ~isfield(S, 'config') || isempty(S.config), return, end

config = S.config;
for i = 1:numel(config)
    subj = config(i).SUBJECT;
    if isempty(subj), continue, end

    if isa(subj, 'epsych.Subject')
        subj = subj.toStruct();
    end
    if ~isstruct(subj) || ~isfield(subj, 'Name'), continue, end

    rec = struct('Name', char(string(subj.Name)), 'Sex', '', 'Species', '', ...
        'Weight', NaN, 'Notes', '', 'protocol_fn', '');
    for f = ["Sex" "Species" "Weight" "Notes"]
        if isfield(subj, f)
            rec.(f) = subj.(f);
        end
    end
    if isfield(config, 'protocol_fn') && ~isempty(config(i).protocol_fn)
        rec.protocol_fn = char(config(i).protocol_fn);
    end

    if ~isempty(rec.Name)
        found(end+1) = rec;
    end
end
