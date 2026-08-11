% smoke_test_phaseselector_nodir
% gui.PhaseSelector must build a usable GUI when its phase directory is
% missing, unset, or empty -- the host GUI should never lose the control just
% because no phase files exist yet.
%
%   matlab -batch "run('tmp/smoke_test_phaseselector_nodir.m')"

run(fullfile(fileparts(mfilename('fullpath')), '..', 'epsych_startup.m'));

failures = {};

R = struct('Interfaces',[]); % PhaseSelector only touches RUNTIME when loading/saving

cases = { ...
    'missing directory', fullfile(tempdir,'no_such_phase_dir_9f3a'); ...
    'unset directory',   ""; ...
    'empty directory',   ''};

emptyDir = fullfile(tempdir,'phaseselector_empty_dir');
if ~isfolder(emptyDir), mkdir(emptyDir); end
cases{3,2} = emptyDir;

for c = 1:size(cases,1)
    label = cases{c,1};
    pth   = cases{c,2};
    try
        ps = gui.PhaseSelector(R, pth);
        assert(numel(ps.Names) == 1, 'expected only the null entry, got %d', numel(ps.Names));
        assert(isempty(ps.FullFilenames), 'expected no phase files');

        fig = uifigure('Visible','off');
        cleanupFig = onCleanup(@() delete(fig));
        h = ps.createGUI(uipanel(fig));

        assert(isvalid(h.PhaseSelect) && isvalid(h.LoadPhase) && isvalid(h.SavePhase) ...
            && isvalid(h.Description), 'all four controls should exist');
        assert(h.LoadPhase.Enable == "off", 'Load should be disabled with no phase selected');
        assert(h.SavePhase.Enable == "on", 'Save must stay available to create the first phase');
        descText = string(h.Description.Text);
        assert(any(contains(descText,"Save")), ...
            'description should tell the operator how to create a phase; got "%s"', strjoin(descText,' | '));

        nItems = numel(h.PhaseSelect.Items);
        clear cleanupFig
        fprintf('PASS: %s -> component built, %d dropdown item(s)\n', label, nItems);
    catch ME
        failures{end+1} = sprintf('%s: %s', label, ME.message); %#ok
    end
end

% A populated directory must still list its phases.
popDir = fullfile(tempdir,'phaseselector_pop_dir');
if ~isfolder(popDir), mkdir(popDir); end
touch = fullfile(popDir,'zz_late.eprot'); fclose(fopen(touch,'w'));
touch2 = fullfile(popDir,'aa_early.json'); fclose(fopen(touch2,'w'));
try
    ps = gui.PhaseSelector(R, popDir);
    assert(isequal(ps.Names, ["< Select Phase >","aa_early","zz_late"]), ...
        'expected alphabetical phases, got %s', strjoin(ps.Names,', '));
    fprintf('PASS: populated directory -> %s\n', strjoin(ps.Names,', '));
catch ME
    failures{end+1} = sprintf('populated directory: %s', ME.message); %#ok
end
delete(touch); delete(touch2); rmdir(popDir); rmdir(emptyDir);

fprintf('\n');
if isempty(failures)
    fprintf('ALL PASS\n');
else
    fprintf('FAILURES:\n');
    fprintf('  %s\n', failures{:});
end
