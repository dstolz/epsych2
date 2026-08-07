function smoke_test_parameter_find_replace()
% smoke_test_parameter_find_replace()
% Exercise the Protocol Designer's Find (name filter) and Find and Replace
% (parameter rename) features headlessly: table filtering, the rename plan,
% conflict and invalid-name detection, scope restriction, and the expression
% rewriting that keeps calculations pointing at the renamed parameters.
%
%   matlab -batch "run('tmp/smoke_test_parameter_find_replace.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

failures = {};

% ===== A. Find box filters the parameter table ===========================
designer = [];
try
    designer = localBuildDesigner_();

    designer.onFindParameterChanged('');
    totalCount = numel(designer.ParameterHandles);
    assert(totalCount == 5, 'expected 5 parameters, got %d', totalCount);

    % Partial, case-insensitive substring match
    designer.onFindParameterChanged('tone');
    names = localVisibleNames_(designer);
    assert(isequal(sort(names), {'ToneDur', 'ToneLevel'}), ...
        'substring find returned %s', strjoin(names, ','));

    % Wildcards match the whole name
    designer.onFindParameterChanged('Tone*');
    assert(numel(designer.ParameterHandles) == 2, 'wildcard prefix should match 2');

    designer.onFindParameterChanged('*Level');
    names = localVisibleNames_(designer);
    assert(isequal(sort(names), {'DerivedLevel', 'MaskLevel', 'ToneLevel'}), ...
        'wildcard suffix returned %s', strjoin(names, ','));

    designer.onFindParameterChanged('ToneDu?');
    assert(numel(designer.ParameterHandles) == 1, 'single-character wildcard should match 1');

    % A dot searches the qualified Module.Param form
    moduleName = designer.Protocol.Interfaces(1).Module(1).Name;
    designer.onFindParameterChanged(sprintf('%s.ToneLevel', moduleName));
    assert(numel(designer.ParameterHandles) == 1, 'qualified find should match 1');

    designer.onFindParameterChanged('NoSuchThing');
    assert(isempty(designer.ParameterHandles), 'unmatched find should empty the table');

    designer.onFindParameterChanged('');
    assert(numel(designer.ParameterHandles) == totalCount, 'clearing find should restore all rows');

    fprintf('PASS: A. Find box filtering\n');
catch ME
    failures{end + 1} = sprintf('A. Find box filtering: %s', ME.message);
    fprintf('FAIL: A. %s\n', ME.message);
end
localCleanup_(designer);

% ===== B. Partial replace rewrites names and expressions =================
designer = [];
try
    designer = localBuildDesigner_();
    moduleName = designer.Protocol.Interfaces(1).Module(1).Name;

    changes = designer.planParameterNameReplacement('Tone', 'Target');
    assert(numel(changes) == 2, 'expected 2 planned renames, got %d', numel(changes));
    assert(all(strcmp({changes.Status}, 'rename')), 'both renames should be applicable');
    assert(isequal(sort({changes.NewName}), {'TargetDur', 'TargetLevel'}), ...
        'planned names were %s', strjoin({changes.NewName}, ','));

    % Planning must not touch the protocol
    assert(~isempty(localFindParameter_(designer, 'ToneLevel')), 'planning renamed a parameter');

    appliedCount = designer.applyParameterNameReplacement(changes);
    assert(appliedCount == 2, 'expected 2 applied renames, got %d', appliedCount);
    assert(isempty(localFindParameter_(designer, 'ToneLevel')), 'old name still present');
    assert(~isempty(localFindParameter_(designer, 'TargetLevel')), 'new name missing');

    % Bare sibling reference follows the rename
    derived = localFindParameter_(designer, 'DerivedLevel');
    assert(strcmp(char(derived.Expression), 'TargetLevel + 5'), ...
        'sibling expression became "%s"', char(derived.Expression));

    % Qualified cross-module reference and its property form follow too
    crossParam = localFindParameter_(designer, 'CrossRef');
    expected = sprintf('%s.TargetLevel * 2 + %s.TargetDur.Max', moduleName, moduleName);
    assert(strcmp(char(crossParam.Expression), expected), ...
        'qualified expression became "%s", expected "%s"', char(crossParam.Expression), expected);

    fprintf('PASS: B. Partial replace with expression rewrite\n');
catch ME
    failures{end + 1} = sprintf('B. Partial replace: %s', ME.message);
    fprintf('FAIL: B. %s\n', ME.message);
end
localCleanup_(designer);

% ===== C. Whole-name, case, conflict, and invalid handling ===============
designer = [];
try
    designer = localBuildDesigner_();

    % Whole-name mode ignores partial matches
    changes = designer.planParameterNameReplacement('Tone', 'Target', WholeName = true);
    assert(isempty(changes), 'whole-name mode should not match a partial name');

    changes = designer.planParameterNameReplacement('ToneLevel', 'Target', WholeName = true);
    assert(numel(changes) == 1 && strcmp(changes.NewName, 'Target'), ...
        'whole-name mode should rename exactly one parameter');

    % Case sensitivity
    assert(isempty(designer.planParameterNameReplacement('tone', 'Target', MatchCase = true)), ...
        'case-sensitive find should not match "tone"');
    assert(numel(designer.planParameterNameReplacement('tone', 'Target')) == 2, ...
        'case-insensitive find should match both Tone parameters');

    % Renaming onto an existing name in the same module is reported, not applied
    changes = designer.planParameterNameReplacement('ToneLevel', 'MaskLevel', WholeName = true);
    assert(numel(changes) == 1 && strcmp(changes.Status, 'conflict'), ...
        'expected a conflict, got status "%s"', changes(1).Status);
    assert(designer.applyParameterNameReplacement(changes) == 0, 'conflicts must not be applied');
    assert(~isempty(localFindParameter_(designer, 'ToneLevel')), 'conflicting rename was applied');

    % Emptying a name is reported as invalid
    changes = designer.planParameterNameReplacement('ToneLevel', '', WholeName = true);
    assert(numel(changes) == 1 && strcmp(changes.Status, 'invalid'), ...
        'empty replacement should be invalid, got "%s"', changes(1).Status);
    assert(designer.applyParameterNameReplacement(changes) == 0, 'invalid names must not be applied');

    fprintf('PASS: C. Whole-name, case, conflict, and invalid handling\n');
catch ME
    failures{end + 1} = sprintf('C. Options and guards: %s', ME.message);
    fprintf('FAIL: C. %s\n', ME.message);
end
localCleanup_(designer);

% ===== D. Scope follows the visible table ================================
designer = [];
try
    designer = localBuildDesigner_();

    designer.onFindParameterChanged('ToneLevel');
    changes = designer.planParameterNameReplacement('Level', 'Amp', Scope = 'shown');
    assert(numel(changes) == 1 && strcmp(changes.OldName, 'ToneLevel'), ...
        'shown scope should only consider the filtered row');

    changes = designer.planParameterNameReplacement('Level', 'Amp', Scope = 'all');
    assert(numel(changes) == 3, 'all scope should consider every *Level* name, got %d', numel(changes));

    designer.onFindParameterChanged('');
    fprintf('PASS: D. Scope restriction\n');
catch ME
    failures{end + 1} = sprintf('D. Scope restriction: %s', ME.message);
    fprintf('FAIL: D. %s\n', ME.message);
end
localCleanup_(designer);

% ===== E. Renamed protocol still compiles ================================
designer = [];
try
    designer = localBuildDesigner_();
    designer.applyParameterNameReplacement( ...
        designer.planParameterNameReplacement('Tone', 'Target'));

    report = designer.Protocol.validate();
    assert(isempty(report) || ~any([report.severity] == 2), ...
        'renamed protocol reported a fatal validation issue');

    designer.Protocol.compile();
    assert(designer.Protocol.COMPILED.ntrials > 0, ...
        'protocol should still compile after renaming');

    fprintf('PASS: E. Compile after rename\n');
catch ME
    failures{end + 1} = sprintf('E. Compile after rename: %s', ME.message);
    fprintf('FAIL: E. %s\n', ME.message);
end
localCleanup_(designer);

% ===== Summary ===========================================================
if isempty(failures)
    fprintf('\nsmoke_test_parameter_find_replace: ALL SECTIONS PASS\n');
else
    fprintf('\nsmoke_test_parameter_find_replace: %d FAILURE(S)\n', numel(failures));
    error('smoke_test_parameter_find_replace failed:\n  %s', strjoin(failures, sprintf('\n  ')));
end
end

function designer = localBuildDesigner_()
% Build a designer over a small protocol with sibling and cross-module expressions.
    protocol = epsych.Protocol();
    protocol.addParameter('Software', 'ToneLevel', 60, Min = 0, Max = 100);
    protocol.addParameter('Software', 'ToneDur', 25, Min = 0, Max = 500);
    protocol.addParameter('Software', 'MaskLevel', 40, Min = 0, Max = 100);

    derived = protocol.addParameter('Software', 'DerivedLevel', 1);
    derived.Expression = "ToneLevel + 5";

    moduleName = protocol.Interfaces(1).Module(1).Name;
    crossParam = protocol.addParameter('Software', 'CrossRef', 1);
    crossParam.Expression = string(sprintf('%s.ToneLevel * 2 + %s.ToneDur.Max', moduleName, moduleName));

    designer = epsych.ProtocolDesigner(protocol);
end

function names = localVisibleNames_(designer)
    names = cellfun(@(p) p.Name, designer.ParameterHandles, 'UniformOutput', false);
    names = reshape(names, 1, []);
end

function parameter = localFindParameter_(designer, name)
    parameter = [];
    for ifaceIdx = 1:numel(designer.Protocol.Interfaces)
        iface = designer.Protocol.Interfaces(ifaceIdx);
        for moduleIdx = 1:numel(iface.Module)
            module = iface.Module(moduleIdx);
            match = module.Parameters(strcmp({module.Parameters.Name}, name));
            if ~isempty(match)
                parameter = match(1);
                return
            end
        end
    end
end

function localCleanup_(designer)
    if isempty(designer) || ~isvalid(designer)
        return
    end
    if ~isempty(designer.Figure) && isvalid(designer.Figure)
        delete(designer.Figure);
    end
end
