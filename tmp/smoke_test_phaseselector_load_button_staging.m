function smoke_test_phaseselector_load_button_staging()
% smoke_test_phaseselector_load_button_staging()
% gui.PhaseSelector's Load button must visually distinguish "a phase is
% selected but not yet applied" (staged) from its default/loaded look, and
% must drop the staged look once Load actually runs.
%
%   matlab -batch "run('tmp/smoke_test_phaseselector_load_button_staging.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

failures = {};

tmpDir = fullfile(tempdir, 'epsych_smoke_phaseselector_staging');
if isfolder(tmpDir), rmdir(tmpDir, 's'); end
mkdir(tmpDir);
cleanupDir = onCleanup(@() rmdir(tmpDir, 's'));

% gui.PhaseSelector prefers its remembered directory (setpref) over the
% constructor argument, so an operator's real phase directory would hijack this.
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
P = epsych.Protocol(Name='StageBtnTest', Info='Load button staging');
P.addParameter('Software', 'StimDelay', 5, Type='Float');

R = epsych.Runtime;
R.Interfaces = P.Interfaces;
R.Protocol = P;

phaseFile = fullfile(tmpDir, 'stageBtn.eprot');
R.find_parameter('StimDelay').Value = 99; % differ from default so Load has something to apply
R.writeParametersProtocol(phaseFile, "Stage button phase");
R.find_parameter('StimDelay').Value = 5;  % restore before Load runs

fig = uifigure('Visible', 'on');   % uiprogressdlg refuses a hidden figure
cleanupFig = onCleanup(@() delete(fig));
ps = gui.PhaseSelector(R, tmpDir);
h  = ps.createGUI(uipanel(fig));

defaultText  = h.LoadPhase.Text;
defaultColor = h.LoadPhase.BackgroundColor;

% ===== A. Fresh build: default/un-staged appearance, Load disabled =======
try
    assert(h.LoadPhase.Enable == "off", 'Load should start disabled with no phase selected');
    fprintf('PASS: A. fresh build starts un-staged (text="%s")\n', defaultText);
catch ME
    failures{end+1} = sprintf('A. fresh state: %s', ME.message); %#ok<AGROW>
    fprintf('FAIL: A. %s\n', ME.message);
end

% ===== B. Selecting a phase stages the Load button ========================
try
    h.PhaseSelect.Value = 'stageBtn';
    evalc('ps.onPhaseSelectionChanged(h.PhaseSelect);');

    assert(h.LoadPhase.Enable == "on", 'Load should be enabled once a phase is selected');
    assert(~strcmp(h.LoadPhase.Text, defaultText), ...
        'staged Text should differ from the default ("%s")', defaultText);
    assert(~isequal(h.LoadPhase.BackgroundColor, defaultColor), ...
        'staged BackgroundColor should differ from the default');

    fprintf('PASS: B. selecting a phase stages the button (text="%s")\n', h.LoadPhase.Text);
catch ME
    failures{end+1} = sprintf('B. staged appearance: %s', ME.message); %#ok<AGROW>
    fprintf('FAIL: B. %s\n', ME.message);
end

% ===== C. Loading resets the button to its default appearance ============
try
    evalc('ps.loadPhaseParameters([]);');

    assert(isequal(h.LoadPhase.Text, defaultText), ...
        'Text should reset to "%s" after Load, got "%s"', defaultText, h.LoadPhase.Text);
    assert(isequal(h.LoadPhase.BackgroundColor, defaultColor), ...
        'BackgroundColor should reset to the default after Load');
    assert(isequal(R.find_parameter('StimDelay').Value, 99), ...
        'setup check: Load should have actually applied the phase');

    fprintf('PASS: C. Load resets the button to its default appearance\n');
catch ME
    failures{end+1} = sprintf('C. reset on load: %s', ME.message); %#ok<AGROW>
    fprintf('FAIL: C. %s\n', ME.message);
end

% ===== D. Returning to the null entry also un-stages the button ==========
try
    h.PhaseSelect.Value = '< Select Phase >';
    evalc('ps.onPhaseSelectionChanged(h.PhaseSelect);');

    h.PhaseSelect.Value = 'stageBtn';
    evalc('ps.onPhaseSelectionChanged(h.PhaseSelect);');
    assert(~strcmp(h.LoadPhase.Text, defaultText), 'setup: re-selecting should re-stage');

    h.PhaseSelect.Value = '< Select Phase >';
    evalc('ps.onPhaseSelectionChanged(h.PhaseSelect);');

    assert(isequal(h.LoadPhase.Text, defaultText), ...
        'deselecting should drop the staged Text');
    assert(isequal(h.LoadPhase.BackgroundColor, defaultColor), ...
        'deselecting should drop the staged BackgroundColor');
    assert(h.LoadPhase.Enable == "off", 'Load should disable again on the null entry');

    fprintf('PASS: D. deselecting un-stages the button\n');
catch ME
    failures{end+1} = sprintf('D. deselect resets: %s', ME.message); %#ok<AGROW>
    fprintf('FAIL: D. %s\n', ME.message);
end

% ===== Summary ============================================================
if isempty(failures)
    fprintf('\nsmoke_test_phaseselector_load_button_staging: ALL PASS\n');
else
    fprintf('\nsmoke_test_phaseselector_load_button_staging: %d FAILURE(S)\n', numel(failures));
    fprintf('  - %s\n', failures{:});
    error('smoke_test_phaseselector_load_button_staging:failed', '%d failure(s)', numel(failures));
end

end


function rmprefIfSet(group, key)
% Remove a preference only if it exists; rmpref errors on a missing key.
if ispref(group, key)
    rmpref(group, key);
end
end
