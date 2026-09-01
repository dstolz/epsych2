function smoke_test_phaseselector_version_label()
% smoke_test_phaseselector_version_label()
% gui.components.PhaseSelector shows each phase's protocol version after its
% name in the dropdown, without changing what selecting a phase resolves to.
%
% The dropdown label and the dropdown Value are deliberately different things:
% Items carry the version suffix, ItemsData the bare name. Everything that
% resolves a selection (selectedPhaseFile, and any caller that sets Value by
% name) sees only the bare name, so decorating the list cannot break loading.
%
%   matlab -batch "run('tmp/smoke_test_phaseselector_version_label.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

failures = {};

tmpDir = fullfile(tempdir, 'epsych_smoke_phaseselector_version');
if isfolder(tmpDir), rmdir(tmpDir, 's'); end
mkdir(tmpDir);
cleanupDir = onCleanup(@() rmdir(tmpDir, 's'));

% The remembered directory (setpref) outranks the constructor argument, so an
% operator's real phase directory would hijack this test.
prefGroup = 'epsych2_gui_PhaseSelector';
prefKey   = 'LastPhasePath';
if ispref(prefGroup, prefKey)
    savedPhasePref = getpref(prefGroup, prefKey);
    cleanupPref = onCleanup(@() setpref(prefGroup, prefKey, savedPhasePref));
else
    cleanupPref = onCleanup(@() rmprefIfSet(prefGroup, prefKey));
end
rmprefIfSet(prefGroup, prefKey);

% ===== Setup =============================================================
% The version a phase carries is the version of the PROTOCOL it was captured
% from: writeParametersProtocol deliberately never mints one of its own, so an
% unsaved protocol yields a phase with no version at all. Save the protocol
% first, exactly as an operator's protocol would have been.
P = epsych.Protocol(Name='VersionLabelTest', Info='Phase version labels');
P.addParameter('Software', 'StimDelay', 5, Type='Float');
% Kept out of the phase directory so it is not itself listed as a phase.
srcDir = fullfile(tmpDir, 'src');
mkdir(srcDir);
protocolFile = fullfile(srcDir, 'source_protocol.eprot');
evalc('P.save(protocolFile);');

R = epsych.Runtime;
R.Interfaces = P.Interfaces;
R.Protocol = P;

% A real phase file, written the way the Save button writes one.
phaseFile = fullfile(tmpDir, 'withVersion.eprot');
R.find_parameter('StimDelay').Value = 99;
evalc('R.writeParametersProtocol(phaseFile, "Versioned phase");');
R.find_parameter('StimDelay').Value = 5;

expectedVersion = epsych.Protocol.versionOnDisk(phaseFile);

% A phase file with no readable version: an .eprot saved before versions were
% stamped, or a foreign file, both read as ''.
noVersionFile = fullfile(tmpDir, 'noVersion.eprot');
fclose(fopen(noVersionFile, 'w'));

% uiprogressdlg (Load) refuses a hidden figure.
fig = uifigure('Visible', 'on');
cleanupFig = onCleanup(@() delete(fig));
ps = gui.components.PhaseSelector(R, tmpDir);
h  = ps.createGUI(uipanel(fig));

% ===== A. Setup check: the phase really does carry a version =============
try
    assert(~isempty(expectedVersion), ...
        'setup: writeParametersProtocol should stamp a protocolVersion, got none');
    fprintf('PASS: A. saved phase carries a version (%s)\n', expectedVersion);
catch ME
    failures{end+1} = sprintf('A. setup: %s', ME.message);
    fprintf('FAIL: A. %s\n', ME.message);
end

% ===== B. The dropdown label carries the version ==========================
try
    items = string(h.PhaseSelect.Items);
    wanted = sprintf('withVersion (%s)', expectedVersion);
    assert(any(items == wanted), ...
        'expected an item "%s", got: %s', wanted, strjoin(items, ', '));
    fprintf('PASS: B. dropdown labels the phase "%s"\n', wanted);
catch ME
    failures{end+1} = sprintf('B. version label: %s', ME.message);
    fprintf('FAIL: B. %s\n', ME.message);
end

% ===== C. A file with no version is listed undecorated ====================
% An absent version is not "version 0", and the dropdown must still name every
% file it found.
try
    items = string(h.PhaseSelect.Items);
    assert(any(items == "noVersion"), ...
        'a versionless phase should be listed undecorated, got: %s', strjoin(items, ', '));
    assert(~any(startsWith(items, "noVersion (")), ...
        'a versionless phase should carry no parenthesised version');
    fprintf('PASS: C. versionless phase listed undecorated\n');
catch ME
    failures{end+1} = sprintf('C. undecorated fallback: %s', ME.message);
    fprintf('FAIL: C. %s\n', ME.message);
end

% ===== D. Value stays the bare name, and still resolves to the file ======
% This is the regression the change could plausibly cause: labelling the list
% must not change what a selection means.
try
    assert(isequal(string(h.PhaseSelect.ItemsData(:))', ps.Names), ...
        'ItemsData should be the undecorated Names');

    % Setting Value by the BARE name is what the dropdown's callers do; it
    % would error outright if ItemsData carried the decorated labels.
    h.PhaseSelect.Value = 'withVersion';
    evalc('ps.onPhaseSelectionChanged(h.PhaseSelect);');

    % selectedPhaseFile is private, so its result is read through the public
    % behaviour it drives: Load enables only for a selection that resolved to
    % a file, and the description names the phase by its bare name.
    assert(h.LoadPhase.Enable == "on", 'Load should be enabled for a resolved phase');
    assert(contains(h.Description.Text, 'Phase "withVersion" selected'), ...
        'description should name the bare phase, got "%s"', h.Description.Text);

    fprintf('PASS: D. Value stays bare and resolves to the phase file\n');
catch ME
    failures{end+1} = sprintf('D. selection resolution: %s', ME.message);
    fprintf('FAIL: D. %s\n', ME.message);
end

% ===== E. Loading a decorated phase still applies its parameters =========
try
    evalc('ps.loadPhaseParameters([]);');
    assert(isequal(R.find_parameter('StimDelay').Value, 99), ...
        'Load should have applied the phase (StimDelay 5 -> 99)');
    fprintf('PASS: E. Load applies a version-labelled phase\n');
catch ME
    failures{end+1} = sprintf('E. load: %s', ME.message);
    fprintf('FAIL: E. %s\n', ME.message);
end

% ===== F. A rescan relabels, and the two lists stay in step ==============
% The label is read off the file rather than cached from when the phase was
% first seen, so a phase recaptured from a newer protocol shows the newer
% version. Note the version tracks the SOURCE PROTOCOL: writeParametersProtocol
% never mints one, so the protocol has to be saved again to move it -- which is
% the whole point of showing it, since a phase captured from an older protocol
% is exactly what an operator wants to notice.
try
    evalc('P.save(protocolFile);');  % mints the next protocol version
    R.find_parameter('StimDelay').Value = 7;
    evalc('R.writeParametersProtocol(phaseFile, "Versioned phase, again");');
    newVersion = epsych.Protocol.versionOnDisk(phaseFile);
    assert(~isequal(newVersion, expectedVersion), ...
        'setup: recapturing from a re-saved protocol should move the version (%s -> %s)', ...
        expectedVersion, newVersion);

    ps.PhasePath = string(tmpDir);  % set.PhasePath rescans
    wanted = sprintf('withVersion (%s)', newVersion);
    assert(any(ps.DisplayNames == wanted), ...
        'after re-saving, expected "%s", got: %s', wanted, strjoin(ps.DisplayNames, ', '));
    assert(numel(ps.DisplayNames) == numel(ps.Names), ...
        'DisplayNames (%d) and Names (%d) must stay the same length', ...
        numel(ps.DisplayNames), numel(ps.Names));

    % A component built fresh over the same directory labels it the same way.
    ps2 = gui.components.PhaseSelector(R, tmpDir);
    h2  = ps2.createGUI(uipanel(fig));
    items = string(h2.PhaseSelect.Items);
    assert(numel(items) == numel(h2.PhaseSelect.ItemsData), ...
        'Items (%d) and ItemsData (%d) must stay the same length', ...
        numel(items), numel(h2.PhaseSelect.ItemsData));
    assert(any(items == wanted), ...
        'a fresh component should also label "%s", got: %s', wanted, strjoin(items, ', '));

    fprintf('PASS: F. rescan relabels to the new version (%s)\n', newVersion);
catch ME
    failures{end+1} = sprintf('F. rescan: %s', ME.message);
    fprintf('FAIL: F. %s\n', ME.message);
end

fprintf('\n');
if isempty(failures)
    fprintf('smoke_test_phaseselector_version_label: ALL PASS\n');
else
    fprintf('smoke_test_phaseselector_version_label: FAILURES:\n');
    fprintf('  %s\n', failures{:});
end

end


function rmprefIfSet(group, key)
% Remove a preference only if it exists; rmpref errors on a missing key.
if ispref(group, key)
    rmpref(group, key);
end
end
