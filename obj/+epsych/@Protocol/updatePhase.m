function report = updatePhase(phaseFile, protocolFile, version, options)
    % report = epsych.Protocol.updatePhase(phaseFile, protocolFile)
    % report = epsych.Protocol.updatePhase(phaseFile, protocolFile, version)
    % report = epsych.Protocol.updatePhase(..., DryRun=false)
    %
    % Bring a phase file up to a protocol version: the phase keeps its values
    % and the protocol wins on structure.
    %
    % A phase file is a complete protocol snapshot, frozen at the version it
    % was saved from. Loading it applies every field of every parameter it
    % names (epsych.Runtime.readParameters -> hw.Parameter.fromStruct), so a
    % phase saved under an older protocol quietly reverts whatever the
    % protocol changed since -- a unit, a visibility, an UpdateEveryTrial, an
    % expression. This rewrites the phase so it is the TARGET protocol version
    % carrying the phase's own settings:
    %
    %   - Parameters both name keep the phase's hw.Parameter.PHASE_OWNED_FIELDS
    %     (Value, Values, Min, Max, isRandom); every other field is the
    %     protocol's.
    %   - Where the protocol changed what a value MEANS
    %     (hw.Parameter.PHASE_VALUE_DEFINING_FIELDS: Type, Unit, isArray), the
    %     phase's values cannot be carried and the protocol's are taken; each
    %     is reported in Dropped with the reason.
    %   - A parameter only the protocol has is added with the protocol's
    %     values; one only the phase has is removed.
    %   - Everything that is not a parameter -- interfaces, modules, options,
    %     the trial selector -- is the protocol's, except Info, the phase's
    %     description, which is kept.
    %   - The file takes the target's protocolVersion.
    %
    % Parameters are matched by owning interface Type and Name, preferring the
    % same module, with epsych.Runtime.INTERCHANGEABLE_PARENT_TYPES as the
    % fallback exactly as readParameters loads a phase.
    %
    % Only the stored structs are read; nothing is reconstructed, so a phase
    % naming a backend this installation cannot construct still updates. The
    % target is read from the FILE, never from a live epsych.Protocol: a
    % session's protocol object carries the operator's edits, the subject's
    % parameter defaults, and -- if an old phase was loaded into it -- the very
    % structure this exists to correct.
    %
    % The write overwrites the phase in place through writeProtocolFile, which
    % first archives the content being replaced inside the file, so
    % epsych.Protocol.restoreVersion undoes it. The archived entry is named
    % '<old version>+pre-update.<yyMMddTHHmmss>' rather than by its version
    % alone, because a phase stamped with the target version can still carry
    % stale structure (saved from a session built on an outdated
    % configuration), and one file must not hold one version string twice.
    %
    % This never throws: every caller is a menu that has to say why instead.
    %
    % Parameters:
    %   phaseFile    - the phase (.eprot) to update. Legacy .json phases are
    %                  refused; saving one again from a session converts it.
    %   protocolFile - the session's protocol file (.eprot/.prot)
    %   version      - the protocol version to bring the phase to: the file's
    %                  current one or any in its embedded archive (a pinned
    %                  membership runs an archived one). '' = current.
    %
    % Options:
    %   DryRun       - (default true) report what would change, write nothing
    %   AllowForeign - (default false) write even when fewer than half of the
    %                  phase's parameters exist in the protocol, which says
    %                  the phase most likely belongs to another protocol
    %
    % Returns:
    %   report - struct with fields:
    %     ok              - the update was worked out (and written, if asked)
    %     message         - why not, when ok is false; otherwise a summary
    %     Written         - the file was rewritten
    %     HasChanges      - writing would change the file
    %     PhaseFile, ProtocolFile
    %     PhaseVersion    - the version the phase was stamped with ('' = none)
    %     TargetVersion   - the version it is brought to
    %     Kept            - (1,:) string, parameters whose phase values were kept
    %     Added           - (1,:) string, parameters new to the phase
    %     Removed         - (1,:) string, parameters dropped from the phase
    %     Dropped         - struct(Name, Reason): values replaced because the
    %                       protocol changed what they mean
    %     Restructured    - (1,:) string, parameters whose structure changed
    %     Changes         - epsych.Protocol.diffStructs(old phase, new phase),
    %                       without the Compiled section (the trial table is
    %                       rebuilt from the parameters on use anyway)
    %     MatchedFraction - share of the phase's parameters the protocol has
    %     LooksForeign    - MatchedFraction < 0.5
    %     ArchivedAs      - version label the old content was archived under
    %     Summary         - one line for an operator
    %     Result          - the updated protocol struct
    %
    % Example:
    %   r = epsych.Protocol.updatePhase('Phase_4C.eprot', 'Appetitive.eprot');
    %   disp(r.Summary)
    %   r = epsych.Protocol.updatePhase('Phase_4C.eprot', 'Appetitive.eprot', DryRun=false);
    %   % undo:
    %   epsych.Protocol.restoreVersion('Phase_4C.eprot', r.ArchivedAs, Mode='exact');
    %
    % See also: epsych.Runtime.updatePhase, epsych.Protocol.diffStructs,
    %   epsych.Protocol.restoreVersion, epsych.Runtime.readParameters,
    %   gui.components.PhaseSelector

    arguments
        phaseFile (1,:) char
        protocolFile (1,:) char
        version (1,:) char = ''
        options.DryRun (1,1) logical = true
        options.AllowForeign (1,1) logical = false
    end

    report = localBlankReport(phaseFile, protocolFile);

    try
        report = localUpdate(report, phaseFile, protocolFile, version, options);
    catch ME
        vprintf(0, 1, ME);
        report.ok = false;
        report.Written = false;
        report.message = sprintf('Could not update %s: %s', localName(phaseFile), ME.message);
    end
end


% -----------------------------------------------------------------------
function report = localUpdate(report, phaseFile, protocolFile, version, options)

    [~, ~, ext] = fileparts(phaseFile);
    if strcmpi(ext, '.json')
        report.message = sprintf(['%s is a legacy JSON phase. Load it and save it again ' ...
            'as a phase to convert it to a protocol file first.'], localName(phaseFile));
        return
    end
    if ~isfile(phaseFile)
        report.message = sprintf('Phase file not found: %s', phaseFile);
        return
    end
    if ~isfile(protocolFile)
        report.message = sprintf('Protocol file not found: %s', protocolFile);
        return
    end

    % Archives are read only when needed: a dry run, which a menu runs on
    % every right-click, has no use for the phase's, and the protocol's
    % matters only for a target that is not its current version.
    P = epsych.Protocol.readRaw_(phaseFile, IncludeHistory=false);
    if isempty(P) || ~isfield(P, 'InterfaceData') || ~iscell(P.InterfaceData) || isempty(P.InterfaceData)
        report.message = sprintf('%s is not a phase file this can update (no parameters were found in it).', ...
            localName(phaseFile));
        return
    end

    T = epsych.Protocol.readRaw_(protocolFile, IncludeHistory=false);
    if isempty(T)
        report.message = sprintf('Not a protocol file: %s', protocolFile);
        return
    end
    current = localVersion(T);
    if isempty(version)
        version = current;
    end
    if ~strcmp(version, current)
        [~, H] = epsych.Protocol.readRaw_(protocolFile);
        hit = [];
        if ~isempty(H)
            hit = find(strcmp({H.Version}, version), 1);
        end
        if isempty(hit)
            report.message = sprintf(['%s does not hold version %s, so the phase cannot be ' ...
                'brought to it. Files last saved by an older EPsych keep no archive.'], ...
                localName(protocolFile), version);
            return
        end
        T = H(hit).Protocol;
    end
    if ~isfield(T, 'InterfaceData') || ~iscell(T.InterfaceData)
        report.message = sprintf('Version %s of %s holds no interfaces to update the phase to.', ...
            localOrNone(version), localName(protocolFile));
        return
    end

    phaseVersion = localVersion(P);
    report.PhaseVersion = phaseVersion;
    report.TargetVersion = version;

    nPhase = epsych.Protocol.versionNumber(phaseVersion);
    nTarget = epsych.Protocol.versionNumber(version);
    if nPhase > nTarget
        report.message = sprintf(['%s was saved from %s, newer than the %s this session runs; ' ...
            'updating it would move it backwards.'], localName(phaseFile), phaseVersion, version);
        return
    end

    % ----- merge ------------------------------------------------------------
    E = localPhaseEntries(P);
    out = T;
    owned = hw.Parameter.PHASE_OWNED_FIELDS;
    defining = hw.Parameter.PHASE_VALUE_DEFINING_FIELDS;
    structureSkip = [owned, {'lastUpdated'}];

    for i = 1:numel(out.InterfaceData)
        IF = out.InterfaceData{i};
        if isempty(IF) || ~isstruct(IF) || ~isfield(IF, 'Modules') || ~iscell(IF.Modules)
            continue
        end
        types = localCandidateTypes(string(IF.Type), E.Type);
        for m = 1:numel(IF.Modules)
            M = IF.Modules{m};
            if ~isstruct(M) || ~isfield(M, 'Parameters') || ~iscell(M.Parameters)
                continue
            end
            moduleName = localModuleName(M);
            for k = 1:numel(M.Parameters)
                t = M.Parameters{k};
                if ~isstruct(t) || ~isscalar(t) || ~isfield(t, 'Name'), continue, end
                name = string(t.Name);

                cand = find(ismember(E.Type, types) & E.Name == name & ~E.Used);
                if isempty(cand)
                    report.Added(end+1) = name;
                    continue
                end
                same = cand(E.Module(cand) == moduleName);
                if ~isempty(same), cand = same; end
                j = cand(1);
                E.Used(j) = true;
                s = E.Struct{j};

                changedDefining = defining(cellfun(@(f) isfield(s, f) && isfield(t, f) ...
                    && ~isequaln(s.(f), t.(f)), defining));
                if isempty(changedDefining)
                    for f = owned
                        if isfield(s, f{1})
                            t.(f{1}) = s.(f{1});
                        end
                    end
                    report.Kept(end+1) = name;
                else
                    reason = strjoin(cellfun(@(f) sprintf('%s %s -> %s', f, ...
                        localText(s.(f)), localText(t.(f))), changedDefining, ...
                        'UniformOutput', false), ', ');
                    report.Dropped(end+1) = struct('Name', name, 'Reason', string(reason));
                end

                fields = setdiff(union(fieldnames(s), fieldnames(t)), structureSkip);
                if any(cellfun(@(f) ~isfield(s, f) || ~isfield(t, f) || ~isequaln(s.(f), t.(f)), fields))
                    report.Restructured(end+1) = name;
                end

                M.Parameters{k} = t;
            end
            IF.Modules{m} = M;
        end
        out.InterfaceData{i} = IF;
    end

    report.Removed = E.Name(~E.Used);
    if ~isempty(E.Name)
        report.MatchedFraction = nnz(E.Used) / numel(E.Name);
        report.LooksForeign = report.MatchedFraction < 0.5;
    end

    if isfield(P, 'Info')
        out.Info = P.Info;
    end
    out.protocolVersion = version;
    % lastModified after the compile stamp makes epsych.Protocol.needsCompile
    % rebuild the target's COMPILED table from the merged values on use.
    out.lastModified = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    report.Result = out;

    changes = epsych.Protocol.diffStructs(P, out);
    if ~isempty(changes)
        changes = changes(~strcmp({changes.Section}, 'Compiled'));
    end
    report.Changes = changes;
    report.HasChanges = ~strcmp(phaseVersion, version) || ~isempty(changes);
    report.Summary = localSummary(report);
    report.ok = true;
    report.message = report.Summary;

    if options.DryRun || ~report.HasChanges
        return
    end

    if report.LooksForeign && ~options.AllowForeign
        report.ok = false;
        report.message = sprintf(['Only %d of %d parameters in %s exist in %s, so it most likely ' ...
            'belongs to another protocol. Not updated.'], nnz(E.Used), numel(E.Name), ...
            localName(phaseFile), localName(protocolFile));
        return
    end

    % ----- write ------------------------------------------------------------
    % The history is passed explicitly so the replaced content is archived
    % under a label of its own even when its version equals the target's
    % (see the header), and so no archived entry is left carrying the version
    % the file now holds as current.
    oldLabel = phaseVersion;
    if isempty(oldLabel), oldLabel = 'unversioned'; end
    label = sprintf('%s+pre-update.%s', oldLabel, ...
        char(datetime('now', 'Format', 'yyMMdd''T''HHmmss')));
    [~, phaseHistory] = epsych.Protocol.readRaw_(phaseFile);
    if ~isempty(phaseHistory)
        phaseHistory = phaseHistory(~ismember({phaseHistory.Version}, {version, label}));
    end
    entry = struct();
    entry.Version  = label;
    entry.SavedAt  = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    entry.Origin   = 'update';
    entry.Protocol = P;
    if isempty(phaseHistory)
        phaseHistory = entry;
    else
        phaseHistory = [entry, phaseHistory];
    end

    epsych.Protocol.writeProtocolFile(phaseFile, out, Origin='update', ...
        History=phaseHistory, UseExplicitHistory=true);

    report.Written = true;
    report.ArchivedAs = label;
    report.message = sprintf('%s The previous content is archived in the file as %s.', ...
        report.Summary, label);
    vprintf(1, 'Phase updated: %s', report.message);
    if ~isempty(report.Dropped)
        vprintf(1, 'Phase update of %s took the protocol''s values for: %s', localName(phaseFile), ...
            strjoin(arrayfun(@(d) sprintf('%s (%s)', d.Name, d.Reason), report.Dropped, ...
            'UniformOutput', false), '; '));
    end
end


% -----------------------------------------------------------------------
function E = localPhaseEntries(P)
    % Flatten the phase's parameters for matching.
    E = struct('Type', strings(1,0), 'Module', strings(1,0), 'Name', strings(1,0), ...
        'Struct', {cell(1,0)}, 'Used', false(1,0));
    for i = 1:numel(P.InterfaceData)
        IF = P.InterfaceData{i};
        if isempty(IF) || ~isstruct(IF) || ~isfield(IF, 'Type') || ~isfield(IF, 'Modules') ...
                || ~iscell(IF.Modules)
            continue
        end
        for m = 1:numel(IF.Modules)
            M = IF.Modules{m};
            if ~isstruct(M) || ~isfield(M, 'Parameters') || ~iscell(M.Parameters)
                continue
            end
            moduleName = localModuleName(M);
            for k = 1:numel(M.Parameters)
                s = M.Parameters{k};
                if ~isstruct(s) || ~isscalar(s) || ~isfield(s, 'Name'), continue, end
                E.Type(end+1) = string(IF.Type);
                E.Module(end+1) = moduleName;
                E.Name(end+1) = string(s.Name);
                E.Struct{end+1} = s;
                E.Used(end+1) = false;
            end
        end
    end
end


% -----------------------------------------------------------------------
function types = localCandidateTypes(type, phaseTypes)
    % The phase interface types a target interface's parameters may come
    % from: its own type, or -- only when the phase has none of it -- the
    % types it is interchangeable with, the rule readParameters loads by.
    types = type;
    if any(phaseTypes == type), return, end
    for group = epsych.Runtime.INTERCHANGEABLE_PARENT_TYPES
        if any(group{1} == type)
            types = group{1};
            return
        end
    end
end


% -----------------------------------------------------------------------
function name = localModuleName(M)
    name = "";
    if isfield(M, 'Name') && ~isempty(M.Name)
        name = string(M.Name);
    end
end


% -----------------------------------------------------------------------
function v = localVersion(S)
    v = '';
    if isfield(S, 'protocolVersion') && ~isempty(S.protocolVersion)
        v = char(string(S.protocolVersion));
    end
end


% -----------------------------------------------------------------------
function txt = localSummary(r)
    if ~r.HasChanges
        txt = sprintf('%s already matches %s; nothing to update.', ...
            localName(r.PhaseFile), localOrNone(r.TargetVersion));
        return
    end
    txt = sprintf('%s: %s -> %s. Kept the phase''s values for %d parameter(s); structure updated on %d', ...
        localName(r.PhaseFile), localOrNone(r.PhaseVersion), localOrNone(r.TargetVersion), ...
        numel(r.Kept), numel(r.Restructured));
    if ~isempty(r.Added)
        txt = sprintf('%s; added %d (%s)', txt, numel(r.Added), strjoin(r.Added, ', '));
    end
    if ~isempty(r.Removed)
        txt = sprintf('%s; removed %d (%s)', txt, numel(r.Removed), strjoin(r.Removed, ', '));
    end
    if ~isempty(r.Dropped)
        txt = sprintf('%s; took the protocol''s values for %d whose meaning changed (%s)', ...
            txt, numel(r.Dropped), strjoin([r.Dropped.Name], ', '));
    end
    txt = [txt '.'];
end


% -----------------------------------------------------------------------
function r = localBlankReport(phaseFile, protocolFile)
    r = struct();
    r.ok = false;
    r.message = '';
    r.Written = false;
    r.HasChanges = false;
    r.PhaseFile = phaseFile;
    r.ProtocolFile = protocolFile;
    r.PhaseVersion = '';
    r.TargetVersion = '';
    r.Kept = strings(1,0);
    r.Added = strings(1,0);
    r.Removed = strings(1,0);
    r.Dropped = struct('Name', {}, 'Reason', {});
    r.Restructured = strings(1,0);
    r.Changes = struct('Section', {}, 'Path', {}, 'Item', {}, 'Change', {}, 'Old', {}, 'New', {});
    r.MatchedFraction = NaN;
    r.LooksForeign = false;
    r.ArchivedAs = '';
    r.Summary = '';
    r.Result = struct([]);
end


% -----------------------------------------------------------------------
function s = localText(v)
    if ischar(v) || isstring(v)
        s = sprintf('"%s"', char(string(v)));
        if strlength(string(v)) == 0, s = '""'; end
    elseif (isnumeric(v) || islogical(v)) && numel(v) <= 8
        s = mat2str(v);
    else
        s = sprintf('<%s>', class(v));
    end
end


% -----------------------------------------------------------------------
function n = localName(f)
    [~, n, e] = fileparts(f);
    n = [n e];
end


% -----------------------------------------------------------------------
function s = localOrNone(v)
    if isempty(v)
        s = '(unversioned)';
    else
        s = v;
    end
end
