function changes = diffStructs(A, B, options)
    % changes = epsych.Protocol.diffStructs(A, B)
    % changes = epsych.Protocol.diffStructs(A, B, IncludeTimestamps = true)
    %
    % What differs between two serialized protocols, as a flat list a person
    % can read.
    %
    % Both arguments are epsych.Protocol.toStruct output — the layout stored in
    % an .eprot and archived by writeProtocolFile — so this compares versions
    % without reconstructing a single hw.Interface, hw.Module, or hw.Parameter.
    % That is what makes it cheap enough for a dialog to run on a selection
    % change, and what lets it compare an archived version naming a backend
    % class this installation cannot construct.
    %
    % Interfaces are matched by type (a second interface of the same type is
    % matched by the order it appears in), modules by Name, and parameters by
    % Name. A renamed parameter therefore reads as one removed and one added,
    % which is the honest answer: nothing in the file records a rename.
    %
    % COMPILED is reported as its trial count alone. Everything else in it is
    % derived from the parameters already listed, and the trial table itself
    % can run to thousands of rows.
    %
    % Parameters:
    %   A - the OLDER protocol struct (what is being compared from)
    %   B - the NEWER protocol struct (what is being compared to)
    %
    % Options:
    %   IncludeTimestamps - also report createdDate/lastModified/lastUpdated/
    %                       compiledAt. Off by default: every save rewrites
    %                       them, so they would appear in every comparison
    %                       without ever saying anything about the protocol.
    %
    % Returns:
    %   changes - (1,:) struct array, empty when the two are equivalent, with
    %             fields:
    %       Section - 'Protocol' | 'Options' | 'Compiled' | 'Interface' |
    %                 'Module' | 'Parameter'
    %       Path    - where it is, as 'Interface > Module > Parameter'
    %       Item    - the field that differs, or '' for a whole object
    %       Change  - 'added' | 'removed' | 'changed'
    %       Old     - display text of the value in A
    %       New     - display text of the value in B
    %
    % Example:
    %   [~, oldS] = epsych.Protocol.loadVersion(f, 'v3.260814');
    %   [~, newS] = epsych.Protocol.loadVersion(f);
    %   c = epsych.Protocol.diffStructs(oldS, newS);
    %
    % See also: epsych.Protocol.compareVersions, epsych.Protocol.listVersions,
    %   gui.compareProtocolVersions

    arguments
        A (1,1) struct
        B (1,1) struct
        options.IncludeTimestamps (1,1) logical = false
    end

    changes = localBlank();

    % protocolVersion is the identity of the two sides being compared, not a
    % difference between them; the timestamps move on every save.
    skip = {'protocolVersion'};
    if ~options.IncludeTimestamps
        skip = [skip, {'createdDate', 'lastModified', 'lastUpdated', 'compiledAt'}];
    end
    containers = {'Options', 'Info', 'COMPILED', 'InterfaceData'};

    % ----- protocol metadata and Info ---------------------------------------
    for f = localFieldUnion(A, B)
        name = f{1};
        if ismember(name, containers) || ismember(name, skip), continue, end
        changes = localCompareField(changes, 'Protocol', 'Protocol', name, ...
            localGet(A, name), localGet(B, name), localHas(A, name), localHas(B, name));
    end

    changes = localCompareField(changes, 'Protocol', 'Protocol', 'Info', ...
        localGet(A, 'Info'), localGet(B, 'Info'), localHas(A, 'Info'), localHas(B, 'Info'));

    % ----- options ----------------------------------------------------------
    oA = localSubStruct(A, 'Options');
    oB = localSubStruct(B, 'Options');
    for f = localFieldUnion(oA, oB)
        name = f{1};
        if ismember(name, skip), continue, end
        changes = localCompareField(changes, 'Options', 'Options', name, ...
            localGet(oA, name), localGet(oB, name), localHas(oA, name), localHas(oB, name));
    end

    % ----- compiled trial count --------------------------------------------
    cA = localSubStruct(A, 'COMPILED');
    cB = localSubStruct(B, 'COMPILED');
    changes = localCompareField(changes, 'Compiled', 'Compiled', 'ntrials', ...
        localGet(cA, 'ntrials'), localGet(cB, 'ntrials'), ...
        localHas(cA, 'ntrials'), localHas(cB, 'ntrials'));

    % ----- interfaces, modules, parameters ----------------------------------
    ifA = localToCell(localGet(A, 'InterfaceData'));
    ifB = localToCell(localGet(B, 'InterfaceData'));
    keyA = localKeys(ifA, @localInterfaceLabel);
    keyB = localKeys(ifB, @localInterfaceLabel);

    for i = 1:numel(ifA)
        j = localMatch(keyB, keyA{i});
        label = localInterfaceLabel(ifA{i});
        if isempty(j)
            changes(end+1) = localRecord('Interface', label, '', 'removed', ...
                localInterfaceSummary(ifA{i}), '');
            continue
        end
        changes = localCompareInterface(changes, label, ifA{i}, ifB{j}, skip);
    end

    for j = 1:numel(ifB)
        if isempty(localMatch(keyA, keyB{j}))
            changes(end+1) = localRecord('Interface', localInterfaceLabel(ifB{j}), '', ...
                'added', '', localInterfaceSummary(ifB{j}));
        end
    end
end

% =======================================================================
function changes = localCompareInterface(changes, label, a, b, skip)
    % Interface metadata first, then the modules it owns. Fields are compared
    % by union so a backend property added by a newer EPsych still shows up.
    for f = localFieldUnion(a, b)
        name = f{1};
        if strcmp(name, 'Modules') || ismember(name, skip), continue, end
        changes = localCompareField(changes, 'Interface', label, name, ...
            localGet(a, name), localGet(b, name), localHas(a, name), localHas(b, name));
    end

    mA = localToCell(localGet(a, 'Modules'));
    mB = localToCell(localGet(b, 'Modules'));
    keyA = localKeys(mA, @localModuleLabel);
    keyB = localKeys(mB, @localModuleLabel);

    for i = 1:numel(mA)
        j = localMatch(keyB, keyA{i});
        path = sprintf('%s > %s', label, localModuleLabel(mA{i}));
        if isempty(j)
            changes(end+1) = localRecord('Module', path, '', 'removed', ...
                localModuleSummary(mA{i}), '');
            continue
        end
        changes = localCompareModule(changes, path, mA{i}, mB{j}, skip);
    end

    for j = 1:numel(mB)
        if isempty(localMatch(keyA, keyB{j}))
            changes(end+1) = localRecord('Module', ...
                sprintf('%s > %s', label, localModuleLabel(mB{j})), '', 'added', ...
                '', localModuleSummary(mB{j}));
        end
    end
end

% =======================================================================
function changes = localCompareModule(changes, path, a, b, skip)
    for f = localFieldUnion(a, b)
        name = f{1};
        if strcmp(name, 'Parameters') || ismember(name, skip), continue, end
        changes = localCompareField(changes, 'Module', path, name, ...
            localGet(a, name), localGet(b, name), localHas(a, name), localHas(b, name));
    end

    pA = localToCell(localGet(a, 'Parameters'));
    pB = localToCell(localGet(b, 'Parameters'));
    keyA = localKeys(pA, @localParameterLabel);
    keyB = localKeys(pB, @localParameterLabel);

    for i = 1:numel(pA)
        j = localMatch(keyB, keyA{i});
        ppath = sprintf('%s > %s', path, localParameterLabel(pA{i}));
        if isempty(j)
            changes(end+1) = localRecord('Parameter', ppath, '', 'removed', ...
                localParameterSummary(pA{i}), '');
            continue
        end
        for f = localFieldUnion(pA{i}, pB{j})
            name = f{1};
            if ismember(name, skip), continue, end
            changes = localCompareField(changes, 'Parameter', ppath, name, ...
                localGet(pA{i}, name), localGet(pB{j}, name), ...
                localHas(pA{i}, name), localHas(pB{j}, name));
        end
    end

    for j = 1:numel(pB)
        if isempty(localMatch(keyA, keyB{j}))
            changes(end+1) = localRecord('Parameter', ...
                sprintf('%s > %s', path, localParameterLabel(pB{j})), '', 'added', ...
                '', localParameterSummary(pB{j}));
        end
    end
end

% =======================================================================
function changes = localCompareField(changes, section, path, name, va, vb, hasA, hasB)
    % One field. A field present on only one side is an add or a remove even
    % when its value is empty: "this protocol has no such setting" and "this
    % protocol sets it to nothing" are different states.
    if ~hasA && ~hasB, return, end

    if ~hasA
        changes(end+1) = localRecord(section, path, name, 'added', '', localFormat(vb));
    elseif ~hasB
        changes(end+1) = localRecord(section, path, name, 'removed', localFormat(va), '');
    elseif ~isequaln(va, vb)
        changes(end+1) = localRecord(section, path, name, 'changed', ...
            localFormat(va), localFormat(vb));
    end
end

% =======================================================================
function r = localRecord(section, path, item, change, old, new)
    r = struct('Section', section, 'Path', path, 'Item', item, ...
        'Change', change, 'Old', old, 'New', new);
end

% -----------------------------------------------------------------------
function c = localBlank()
    c = struct('Section', {}, 'Path', {}, 'Item', {}, 'Change', {}, ...
        'Old', {}, 'New', {});
end

% -----------------------------------------------------------------------
function names = localFieldUnion(A, B)
    % A's fields in their own order, then B's extras. Alphabetical ordering
    % would scatter the fields a person reads together (Min next to Max).
    names = reshape(fieldnames(A), 1, []);
    extra = reshape(fieldnames(B), 1, []);
    names = [names, extra(~ismember(extra, names))];
end

% -----------------------------------------------------------------------
function tf = localHas(S, name)
    tf = isstruct(S) && isfield(S, name);
end

% -----------------------------------------------------------------------
function v = localGet(S, name)
    v = [];
    if localHas(S, name), v = S.(name); end
end

% -----------------------------------------------------------------------
function s = localSubStruct(S, name)
    s = localGet(S, name);
    if ~isstruct(s) || ~isscalar(s), s = struct(); end
end

% -----------------------------------------------------------------------
function c = localToCell(v)
    % InterfaceData/Modules/Parameters are cell arrays in a MAT protocol, but
    % a JSON round trip collapses same-shaped entries into a struct array.
    if isempty(v)
        c = {};
    elseif iscell(v)
        c = reshape(v, 1, []);
    elseif isstruct(v)
        c = num2cell(reshape(v, 1, []));
    else
        c = {v};
    end
end

% -----------------------------------------------------------------------
function keys = localKeys(list, labelFcn)
    % Match key per entry: its label, with an occurrence number appended so a
    % protocol holding two interfaces of the same type still pairs them up.
    keys = cell(1, numel(list));
    seen = cell(1, numel(list));
    for i = 1:numel(list)
        base = labelFcn(list{i});
        n = sum(strcmp(seen(1:i-1), base)) + 1;
        seen{i} = base;
        keys{i} = sprintf('%s#%d', base, n);
    end
end

% -----------------------------------------------------------------------
function j = localMatch(keys, key)
    j = find(strcmp(keys, key), 1);
end

% -----------------------------------------------------------------------
function s = localInterfaceLabel(iface)
    s = localTextField(iface, {'Type', 'ClassName'}, 'Interface');
end

% -----------------------------------------------------------------------
function s = localModuleLabel(m)
    s = localTextField(m, {'Name', 'Label'}, 'Module');
end

% -----------------------------------------------------------------------
function s = localParameterLabel(p)
    s = localTextField(p, {'Name'}, 'Parameter');
end

% -----------------------------------------------------------------------
function s = localTextField(S, candidates, fallback)
    s = fallback;
    for i = 1:numel(candidates)
        v = localGet(S, candidates{i});
        if ~isempty(v) && (ischar(v) || isstring(v))
            s = char(string(v));
            return
        end
    end
end

% -----------------------------------------------------------------------
function s = localInterfaceSummary(iface)
    m = localToCell(localGet(iface, 'Modules'));
    n = 0;
    for i = 1:numel(m)
        n = n + numel(localToCell(localGet(m{i}, 'Parameters')));
    end
    s = sprintf('%s, %d module(s), %d parameter(s)', localInterfaceLabel(iface), numel(m), n);
end

% -----------------------------------------------------------------------
function s = localModuleSummary(m)
    s = sprintf('%d parameter(s)', numel(localToCell(localGet(m, 'Parameters'))));
end

% -----------------------------------------------------------------------
function s = localParameterSummary(p)
    % A whole parameter appearing or disappearing is best read as its trial
    % levels: that is what changes the trials the protocol compiles to.
    s = localFormat(localGet(p, 'Values'));
    t = localGet(p, 'Type');
    if ~isempty(t) && (ischar(t) || isstring(t))
        s = sprintf('%s: %s', char(string(t)), s);
    end
end

% =======================================================================
function s = localFormat(v)
    % One value as a single line of at most MAXLEN characters. Buffers are
    % summarized rather than rendered: a calibration buffer holds 131072
    % samples, and mat2str of that would be megabytes of dialog text.
    MAXLEN  = 160;
    MAXELEM = 12;

    if isempty(v)
        if ischar(v) || isstring(v)
            s = '(empty text)';
        elseif iscell(v)
            s = '{}';
        else
            s = '(empty)';
        end
        return
    end

    if ischar(v)
        s = localOneLine(v);
    elseif isstring(v)
        s = localOneLine(strjoin(cellstr(reshape(v, 1, [])), ', '));
    elseif islogical(v)
        if isscalar(v)
            s = localTF(v);
        else
            s = ['[', strjoin(arrayfun(@localTF, reshape(v, 1, []), 'uni', 0), ' '), ']'];
        end
    elseif isnumeric(v)
        if numel(v) <= MAXELEM
            s = mat2str(v, 6);
        else
            s = sprintf('%s %s [%s ...]', localSizeText(v), class(v), ...
                strjoin(arrayfun(@(x) num2str(x, 6), reshape(v(1:4), 1, []), 'uni', 0), ' '));
        end
    elseif iscell(v)
        n = min(numel(v), MAXELEM);
        parts = cellfun(@localFormat, reshape(v(1:n), 1, []), 'uni', 0);
        s = ['{', strjoin(parts, ', ')];
        if numel(v) > n, s = [s, ', ...']; end
        s = [s, '}'];
    elseif isstruct(v)
        if isscalar(v)
            s = localStructText(v);
        else
            s = sprintf('%s struct', localSizeText(v));
        end
    elseif isa(v, 'function_handle')
        s = func2str(v);
    elseif isdatetime(v) || isduration(v)
        s = char(string(v));
    else
        s = sprintf('%s %s', localSizeText(v), class(v));
    end

    if numel(s) > MAXLEN
        s = [s(1:MAXLEN-3), '...'];
    end
end

% -----------------------------------------------------------------------
function s = localStructText(v)
    % A serialized stimulus is the struct that actually turns up here, so name
    % it by its type when it has one rather than by its field count.
    t = localTextField(v, {'Type', 'ClassName', 'Name'}, '');
    if isempty(t)
        s = sprintf('<struct: %s>', strjoin(reshape(fieldnames(v), 1, []), ', '));
    else
        s = sprintf('<%s>', t);
    end
end

% -----------------------------------------------------------------------
function s = localSizeText(v)
    s = strjoin(arrayfun(@(d) sprintf('%d', d), size(v), 'uni', 0), 'x');
end

% -----------------------------------------------------------------------
function s = localTF(tf)
    if tf, s = 'true'; else, s = 'false'; end
end

% -----------------------------------------------------------------------
function s = localOneLine(s)
    s = char(s);
    s = strtrim(regexprep(s, '\s+', ' '));
end
