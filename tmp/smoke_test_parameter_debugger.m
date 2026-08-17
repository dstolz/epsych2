% smoke_test_parameter_debugger.m
% Offline smoke tests for gui.ParameterDebugger -- no hardware required.
%
% Drives the window against tmp/ParameterDebuggerMock, a real hw.Interface
% with a value store of its own, so every read and write the GUI makes travels
% the ordinary hw.Parameter path and is asserted on the backend's state. That
% is what makes the interesting cases reachable: a read that throws, a write
% that reads back changed, and the difference between a connected and a
% disconnected interface.
%
% Run headless, from the repository root:
%   matlab -batch "run('tmp/smoke_test_parameter_debugger.m')"
%
% See also: gui.ParameterDebugger, documentation/gui/gui_ParameterDebugger.md

% Bootstrap: `matlab -batch` starts with whatever path the user profile leaves
% behind, and this file lives in tmp/, which is only on the path once
% epsych_startup has run.
if exist('gui.ParameterDebugger', 'class') ~= 8
    run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'epsych_startup.m'));
end
addpath(fileparts(mfilename('fullpath')));   % ParameterDebuggerMock lives beside this test

fprintf('\n=== gui.ParameterDebugger Smoke Test ===\n\n');
results = {};

figs = matlab.ui.Figure.empty;
dbg = [];
rig = [];

%% 1. Build a rig and open the window against a bare interface array
try
    rig = ParameterDebuggerMock();

    % add_parameter fills Values (the design-time levels), not Value, so each
    % parameter is given a starting value explicitly -- as a protocol does on
    % its first dispatch.
    p = rig.add_parameter('Freq', 1000, Unit='Hz', Min=100, Max=20000);   p.Value = 1000;
    p = rig.add_parameter('Level', 60, Unit='dB');                        p.Value = 60;
    p = rig.add_parameter('Coarse', 5, Unit='ms');                        p.Value = 5;
    p = rig.add_parameter('Broken', 0);                                   p.Value = 0;
    p = rig.add_parameter('Enabled', true, Type='Boolean');               p.Value = true;
    p = rig.add_parameter('Waveform', [1 2 3], isArray=true);             p.Value = [1 2 3];
    rig.add_parameter('Coeffs', zeros(1,64), Type='Coefficient Buffer');
    rig.add_parameter('Label', 'tone');
    p = rig.add_parameter('Monitor', 0, Access='Read');                   % read-only
    rig.add_parameter('Command', 0, Access='Write');                      % write-only
    rig.add_parameter('Secret', 42, Visible=false);
    rig.add_parameter('Fire', 0, isTrigger=true);

    % Access='Read' has to be set after the value, or the assignment above
    % would be a write-access violation.
    rig.find_parameter('Monitor').Access = 'Any';
    rig.find_parameter('Monitor').Value = 7;
    rig.find_parameter('Monitor').Access = 'Read';

    % Pad past the progress-dialog threshold (20 rows) so the sweep exercises
    % the dialog and the control-disable path too.
    for i = 1:12
        q = rig.add_parameter(sprintf('Spare%02d', i), i);
        q.Value = i;
    end

    rig.connect();

    dbg = gui.ParameterDebugger(rig, Visible = false);
    figs(end+1) = dbg.H.figure;

    results(end+1,:) = check('Window opened', isvalid(dbg) && isgraphics(dbg.H.figure));
    results(end+1,:) = check('Figure carries the singleton tag', ...
        strcmp(dbg.H.figure.Tag, 'EPsychParameterDebugger'));
    results(end+1,:) = check('Every visible parameter is listed', numel(dbg.Rows) == 23);
    results(end+1,:) = check('Table matches the row model', ...
        size(dbg.H.table.Data, 1) == numel(dbg.Rows));
catch ME
    results(end+1,:) = check(['Open: ' ME.message], false);
end

%% 2. Hidden parameters are opt-in
try
    before = numel(dbg.Rows);
    dbg.H.chkHidden.Value = true;
    dbg.refresh();
    withHidden = numel(dbg.Rows);

    hiddenRow = find(strcmp({dbg.Rows.Name}, 'Secret'), 1);
    results(end+1,:) = check('Hidden parameter excluded by default', before == 23);
    results(end+1,:) = check('Show hidden adds it', withHidden == before + 1);
    results(end+1,:) = check('Hidden row is flagged as such', ...
        ~isempty(hiddenRow) && contains(dbg.Rows(hiddenRow).Flags, 'hidden'));

    dbg.H.chkHidden.Value = false;
    dbg.refresh();
    results(end+1,:) = check('Unticking it removes the row again', numel(dbg.Rows) == before);
catch ME
    results(end+1,:) = check(['Hidden toggle: ' ME.message], false);
end

%% 3. Read All: what it reads, and what it deliberately does not
try
    rig.Store('Freq') = 1234;   % the "device" moved on without the host
    dbg.readAll();

    freq = rowNamed(dbg, 'Freq');
    coeffs = rowNamed(dbg, 'Coeffs');
    broken = rowNamed(dbg, 'Broken');
    command = rowNamed(dbg, 'Command');

    results(end+1,:) = check('Read All picked up the device value', ...
        freq.State == gui.ParameterDebugger.STATE_OK && strcmp(freq.ValueText, '1234'));
    results(end+1,:) = check('A successful read is stamped with a time', ...
        ~isempty(regexp(freq.Note, '^\d\d:\d\d:\d\d$', 'once')));
    results(end+1,:) = check('Read All skips coefficient buffers', ...
        coeffs.State == gui.ParameterDebugger.STATE_SKIP);
    results(end+1,:) = check('Read All skips write-only parameters', ...
        command.State == gui.ParameterDebugger.STATE_SKIP);
    results(end+1,:) = check('A failing read is reported, not thrown', ...
        broken.State == gui.ParameterDebugger.STATE_FAIL && ...
        contains(broken.Note, 'did not answer'));
    results(end+1,:) = check('The status line names the first failure', ...
        contains(dbg.H.status.Text, 'Broken'));
catch ME
    results(end+1,:) = check(['Read All: ' ME.message], false);
end

%% 4. Colour follows state
try
    styles = dbg.H.table.StyleConfigurations;
    vcol = find(strcmp(dbg.H.table.ColumnName, 'Value'), 1);
    okRow = rowIndex(dbg, 'Freq');
    failRow = rowIndex(dbg, 'Broken');

    results(end+1,:) = check('A read row is tinted green', ...
        isequal(styleColorAt(styles, okRow, vcol), [0.90 0.97 0.90]));
    results(end+1,:) = check('A failed row is tinted red', ...
        isequal(styleColorAt(styles, failRow, vcol), [1.00 0.88 0.88]));
catch ME
    results(end+1,:) = check(['Colour: ' ME.message], false);
end

%% 5. Double-clicking a name reads that one parameter
try
    row = rowIndex(dbg, 'Level');
    rig.Store('Level') = 77;

    dbg.H.table.DoubleClickedFcn(dbg.H.table, ...
        struct('InteractionInformation', struct('Row', row, 'Column', 2)));

    results(end+1,:) = check('Double-click on the name read the parameter', ...
        strcmp(dbg.Rows(row).ValueText, '77'));

    % ...and a double-click in the Value column must not, or it would replace
    % what the operator is in the middle of typing.
    rig.Store('Level') = 88;
    dbg.H.table.DoubleClickedFcn(dbg.H.table, ...
        struct('InteractionInformation', struct('Row', row, 'Column', vcol)));
    results(end+1,:) = check('Double-click in the Value cell does not read', ...
        strcmp(dbg.Rows(row).ValueText, '77'));
catch ME
    results(end+1,:) = check(['Double-click: ' ME.message], false);
end

%% 6. A buffer is read when it is asked for by name
try
    row = rowIndex(dbg, 'Coeffs');
    rig.Store('Coeffs') = ones(1,64);

    dbg.H.table.DoubleClickedFcn(dbg.H.table, ...
        struct('InteractionInformation', struct('Row', row, 'Column', 2)));

    results(end+1,:) = check('Double-click reads a buffer Read All skipped', ...
        dbg.Rows(row).State == gui.ParameterDebugger.STATE_OK);
    results(end+1,:) = check('A large array is summarised, not spelled out', ...
        contains(dbg.Rows(row).ValueText, '1x64') && ~dbg.Rows(row).Editable);
catch ME
    results(end+1,:) = check(['Buffer read: ' ME.message], false);
end

%% 7. Writing through the Value cell
try
    row = rowIndex(dbg, 'Freq');
    editCell(dbg, row, '2500');

    results(end+1,:) = check('The write reached the backend', ...
        isequal(rig.Store('Freq'), 2500));
    results(end+1,:) = check('The parameter holds the new value', ...
        isequal(rig.find_parameter('Freq').Value, 2500));
    results(end+1,:) = check('A confirmed write is marked as written', ...
        dbg.Rows(row).State == gui.ParameterDebugger.STATE_WROTE);
    results(end+1,:) = check('The written cell is tinted blue', ...
        isequal(styleColorAt(dbg.H.table.StyleConfigurations, row, vcol), [0.92 0.95 1.00]));
catch ME
    results(end+1,:) = check(['Write: ' ME.message], false);
end

%% 8. A write that does not read back as written is reported, not hidden
try
    row = rowIndex(dbg, 'Coarse');
    editCell(dbg, row, '5.4');

    results(end+1,:) = check('The device quantised the write', ...
        isequal(rig.Store('Coarse'), 5));
    results(end+1,:) = check('The difference is flagged amber, not green', ...
        dbg.Rows(row).State == gui.ParameterDebugger.STATE_STALE);
    results(end+1,:) = check('Both values are shown', ...
        contains(dbg.Rows(row).Note, '5.4') && contains(dbg.Rows(row).Note, '5'));
catch ME
    results(end+1,:) = check(['Quantised write: ' ME.message], false);
end

%% 9. Types the grid understands
try
    boolRow = rowIndex(dbg, 'Enabled');
    editCell(dbg, boolRow, 'false');
    results(end+1,:) = check('Boolean text is parsed', ...
        islogical(rig.Store('Enabled')) && ~rig.Store('Enabled'));

    strRow = rowIndex(dbg, 'Label');
    editCell(dbg, strRow, 'noise burst');
    results(end+1,:) = check('String text is written verbatim', ...
        strcmp(rig.Store('Label'), 'noise burst'));

    arrRow = rowIndex(dbg, 'Waveform');
    editCell(dbg, arrRow, '[4 5 6]');
    results(end+1,:) = check('An array literal is parsed', ...
        isequal(rig.Store('Waveform'), [4 5 6]));

    rangeRow = rowIndex(dbg, 'Spare01');
    editCell(dbg, rangeRow, '1:4');
    results(end+1,:) = check('A range expression is parsed', ...
        isequal(rig.Store('Spare01'), [1 2 3 4]));
catch ME
    results(end+1,:) = check(['Value types: ' ME.message], false);
end

%% 10. What the grid refuses
try
    roRow = rowIndex(dbg, 'Monitor');
    before = rig.find_parameter('Monitor').Value;
    editCell(dbg, roRow, '999');
    results(end+1,:) = check('A read-only parameter is not written', ...
        isequal(rig.find_parameter('Monitor').Value, before));
    results(end+1,:) = check('...and the window says why', ...
        contains(dbg.H.status.Text, 'read-only'));

    badRow = rowIndex(dbg, 'Level');
    editCell(dbg, badRow, 'not a number');
    results(end+1,:) = check('Nonsense text is rejected', ...
        dbg.Rows(badRow).State == gui.ParameterDebugger.STATE_FAIL);

    % str2num is eval. A cell that ran arbitrary code while pointed at live
    % hardware would be a trap, so anything that is not a numeric literal is
    % refused before it gets there.
    evilRow = rowIndex(dbg, 'Spare02');
    before = rig.Store('Spare02');
    editCell(dbg, evilRow, 'system(''echo pwned'')');
    results(end+1,:) = check('Code in a value cell is refused', ...
        isequal(rig.Store('Spare02'), before) && ...
        dbg.Rows(evilRow).State == gui.ParameterDebugger.STATE_FAIL);

    trigRow = rowIndex(dbg, 'Fire');
    editCell(dbg, trigRow, '1');
    results(end+1,:) = check('A trigger is not written by typing', isempty(rig.Fired));
catch ME
    results(end+1,:) = check(['Refusals: ' ME.message], false);
end

%% 11. Firing a trigger
try
    dbg.H.table.Selection = rowIndex(dbg, 'Fire');
    dbg.fireTrigger();
    results(end+1,:) = check('Fire Trigger reached the backend', ...
        ~isempty(rig.Fired) && strcmp(rig.Fired{end}, 'Fire'));

    dbg.H.table.Selection = rowIndex(dbg, 'Level');
    dbg.fireTrigger();
    results(end+1,:) = check('Firing a non-trigger row is refused', ...
        isscalar(rig.Fired) && contains(dbg.H.status.Text, 'No trigger'));
catch ME
    results(end+1,:) = check(['Trigger: ' ME.message], false);
end

%% 12. Filtering
try
    dbg.H.filter.Value = 'spare';
    dbg.refresh();
    results(end+1,:) = check('The filter narrows the list', numel(dbg.Rows) == 12);

    dbg.H.filter.Value = 'no such parameter';
    dbg.refresh();
    results(end+1,:) = check('An empty result explains itself', ...
        isempty(dbg.Rows) && dbg.H.emptyState.Visible == "on" && ...
        contains(dbg.H.emptyState.Text, 'Clear the Find box'));

    dbg.H.filter.Value = '';
    dbg.refresh();
    results(end+1,:) = check('Clearing it restores every row', numel(dbg.Rows) == 23);
catch ME
    results(end+1,:) = check(['Filter: ' ME.message], false);
end

%% 13. A disconnected backend is reported as such
try
    rig.disconnect();
    dbg.readAll();
    freq = rowNamed(dbg, 'Freq');

    results(end+1,:) = check('A read from a disconnected rig is marked offline', ...
        contains(freq.Note, 'offline'));
    results(end+1,:) = check('...and reports the value the host holds', ...
        strcmp(freq.ValueText, '2500'));
    results(end+1,:) = check('The count line says how many are live', ...
        contains(dbg.H.countLabel.Text, '0 of 1'));
    rig.connect();
catch ME
    results(end+1,:) = check(['Offline: ' ME.message], false);
end

%% 14. Any source with an Interfaces property works
try
    rt = epsych.Runtime;
    rt.Interfaces = rig;          % the setter connects; the mock is already up

    dbg2 = gui.ParameterDebugger(rt, Visible = false);
    figs(end+1) = dbg2.H.figure;

    results(end+1,:) = check('A Runtime is accepted as a source', numel(dbg2.Rows) == 23);
    results(end+1,:) = check('Opening again replaced the first window', ~isvalid(dbg));
    dbg = dbg2;
catch ME
    results(end+1,:) = check(['Runtime source: ' ME.message], false);
end

%% 15. Assign to the command window
try
    dbg.H.table.Selection = rowIndex(dbg, 'Level');
    dbg.assignToBase();
    assigned = evalin('base', 'P');
    results(end+1,:) = check('The selected parameter reached the base workspace', ...
        isa(assigned, 'hw.Parameter') && strcmp(assigned.Name, 'Level'));
    evalin('base', 'clear P');
catch ME
    results(end+1,:) = check(['Assign: ' ME.message], false);
end

%% 16. Edges: things that go missing or empty under the window
% Each case builds its own rig, because deleting parameters out of the main one
% would change the row counts every section above asserts on.
try
    edgeRig = ParameterDebuggerMock();
    e = edgeRig.add_parameter('Freq', 1000);   e.Value = 1000;
    e = edgeRig.add_parameter('Label', 'tone'); e.Value = 'tone';
    doomed = edgeRig.add_parameter('Doomed', 5); doomed.Value = 5;
    edgeRig.connect();

    dbg = gui.ParameterDebugger(edgeRig, Visible = false);
    figs(end+1) = dbg.H.figure;

    % Read first, so the cells hold text to clear: an edit whose text did not
    % change is dropped before it reaches the write path.
    edgeRig.Store('Freq') = 1000;
    edgeRig.Store('Label') = 'tone';
    dbg.readAll();

    % Clearing a numeric cell is not a write of nothing; clearing a String
    % cell is a legitimate write of an empty string.
    editCell(dbg, rowIndex(dbg,'Freq'), '');
    results(end+1,:) = check('Clearing a numeric cell writes nothing', ...
        isequal(edgeRig.Store('Freq'), 1000));
    editCell(dbg, rowIndex(dbg,'Label'), '');
    results(end+1,:) = check('Clearing a String cell writes an empty string', ...
        isempty(edgeRig.Store('Label')));

    % A parameter deleted under the window -- what a config reload leaves.
    delete(doomed);
    dbg.readAll();
    results(end+1,:) = check('A deleted parameter is reported, not thrown', ...
        dbg.Rows(rowIndex(dbg,'Doomed')).State == gui.ParameterDebugger.STATE_FAIL);
    editCell(dbg, rowIndex(dbg,'Doomed'), '9');
    results(end+1,:) = check('...and writing to it is refused', ...
        contains(dbg.H.status.Text, 'no longer exists'));

    % An edit event carrying a row that no longer exists, which is what a
    % refresh landing between the click and the callback would produce. The
    % event is fired directly: writing into Data at that index first would
    % throw in the test rather than in the code under test.
    dbg.H.filter.Value = 'Freq';
    dbg.refresh();
    stale = numel(dbg.Rows) + 3;
    dbg.H.table.CellEditCallback(dbg.H.table, ...
        struct('Indices', [stale, 5], 'NewData', '123', 'PreviousData', ''));
    results(end+1,:) = check('A stale row index is ignored', isvalid(dbg));

    % An interface deleted out of the source array must not take the rest with it.
    deadRig = ParameterDebuggerMock();
    both = [edgeRig deadRig];
    delete(deadRig);
    dbg = gui.ParameterDebugger(both, Visible = false);
    figs(end+1) = dbg.H.figure;
    dbg.readAll();
    results(end+1,:) = check('A deleted interface is skipped, the rest still listed', ...
        numel(dbg.Rows) == 2);
catch ME
    results(end+1,:) = check(['Edges: ' ME.message], false);
end

%% 17. An empty table says which kind of empty it is
try
    bareRig = ParameterDebuggerMock();
    dbg = gui.ParameterDebugger(bareRig, Visible = false);
    figs(end+1) = dbg.H.figure;

    results(end+1,:) = check('No parameters at all says exactly that', ...
        contains(dbg.H.emptyState.Text, 'no parameters'));
    % Advice that would reveal nothing is worse than no advice.
    results(end+1,:) = check('...without offering Show hidden', ...
        ~contains(dbg.H.emptyState.Text, 'Show hidden'));

    bareRig.add_parameter('Secret', 1, Visible = false);
    dbg.refresh();
    results(end+1,:) = check('A hidden parameter is offered once there is one', ...
        contains(dbg.H.emptyState.Text, 'Show hidden'));
catch ME
    results(end+1,:) = check(['Empty states: ' ME.message], false);
end

%% 18. Regressions found by review, each of which shipped once
try
    regRig = ParameterDebuggerMock();
    r = regRig.add_parameter('Level', 10);   r.Value = 10;
    r = regRig.add_parameter('Gain', 20);    r.Value = 20;
    regRig.add_parameter('Fire', 0, isTrigger = true);
    regRig.add_parameter('Blind', 0, Access = 'Write', Max = 5);
    regRig.connect();

    dbg = gui.ParameterDebugger(regRig, Visible = false);
    figs(end+1) = dbg.H.figure;

    % A uitable with SelectionType='row' returns Selection as a 1-by-N ROW
    % vector, so reading sel(:,1) kept only the first selected row and silently
    % dropped the rest.
    dbg.H.table.Selection = [rowIndex(dbg,'Level'), rowIndex(dbg,'Gain'), rowIndex(dbg,'Fire')];
    dbg.readSelected();
    results(end+1,:) = check('Read Selected reads every selected row, not just the first', ...
        contains(dbg.H.status.Text, '3 read') || contains(dbg.H.status.Text, '2 read'));

    dbg.fireTrigger();
    results(end+1,:) = check('Fire Trigger finds a trigger below the first selected row', ...
        ~isempty(regRig.Fired) && strcmp(regRig.Fired{end}, 'Fire'));

    dbg.copyToClipboard();
    results(end+1,:) = check('Copy takes the whole selection', ...
        contains(dbg.H.status.Text, 'Copied 3 row(s)'));

    % str2double ran before the safety pattern, so text it alone understands
    % reached the write path. "1e999" overflows to Inf; "(-1)^0.5" is complex
    % and passes the pattern outright.
    before = regRig.Store('Level');
    editCell(dbg, rowIndex(dbg,'Level'), '3i');
    results(end+1,:) = check('A complex literal is refused', ...
        isequal(regRig.Store('Level'), before));
    editCell(dbg, rowIndex(dbg,'Level'), '1e999');
    results(end+1,:) = check('An overflowing literal is refused', ...
        isequal(regRig.Store('Level'), before));
    editCell(dbg, rowIndex(dbg,'Level'), '(-1)^0.5');
    results(end+1,:) = check('Arithmetic that evaluates complex is refused', ...
        isequal(regRig.Store('Level'), before));
    editCell(dbg, rowIndex(dbg,'Level'), '42');
    results(end+1,:) = check('...while an ordinary number still writes', ...
        isequal(regRig.Store('Level'), 42));

    % A write whose read-back is too large to be a literal must also flip the
    % row to uneditable, or the summary text is handed back to the parser and
    % reported as malformed rather than as too large to edit.
    editCell(dbg, rowIndex(dbg,'Gain'), '1:100');
    results(end+1,:) = check('A write that returns a big array marks the row uneditable', ...
        ~dbg.Rows(rowIndex(dbg,'Gain')).Editable);

    % A write-only parameter cannot be read back, so what is shown must at
    % least be what set.Value stored -- clamped, not the raw typed number.
    editCell(dbg, rowIndex(dbg,'Blind'), '99');
    blind = dbg.Rows(rowIndex(dbg,'Blind'));
    results(end+1,:) = check('A clamped write-only value is shown clamped', ...
        strcmp(blind.ValueText, '5') && contains(blind.Note, 'clamped'));

    % The sweep holds the re-entrancy guard for its whole duration, so a
    % refresh or a second read landing mid-sweep is dropped rather than
    % rebuilding Rows underneath the loop.
    dbg.H.table.Selection = [];
    dbg.readAll();
    results(end+1,:) = check('The guard is down again once the sweep ends', ~dbg.IsBusy);
    results(end+1,:) = check('Read Selected is left disabled with nothing selected', ...
        dbg.H.btnReadSel.Enable == "off" && ...
        dbg.H.btnReadSel.Enable == dbg.H.mnu_read_selected.Enable);

    % Closing the window mid-sweep must stop the sweep, not throw out of it.
    % The mock's read hook is the only way to make it happen synchronously.
    victim = dbg;
    regRig.ReadCount = 0;
    regRig.OnRead = @(m, ~) closeAfter(m, 2, victim);
    threw = '';
    try
        dbg.readAll();
    catch ME
        threw = ME.message;
    end
    regRig.OnRead = [];
    results(end+1,:) = check('Closing the window mid-sweep does not throw', isempty(threw));
    results(end+1,:) = check('...and the sweep stops there', ~isvalid(victim));

    % Reopening must not throw away where the operator put the window.
    dbg = gui.ParameterDebugger(regRig, Visible = false);
    figs(end+1) = dbg.H.figure;
    dbg.H.figure.Position = [220 180 900 500];
    dbg = gui.ParameterDebugger(regRig, Visible = false);
    figs(end+1) = dbg.H.figure;
    results(end+1,:) = check('Reopening keeps the previous window position', ...
        isequal(dbg.H.figure.Position(3:4), [900 500]));
catch ME
    results(end+1,:) = check(['Regressions: ' ME.message], false);
end

%% 19. The launch path: Help menu of a live RunExpt session
rx = [];
try
    rx = epsych.RunExpt;

    mnu = findall(rx.H.figure1, 'Type','uimenu', 'Tag','mnu_param_debugger');
    results(end+1,:) = check('The session window has the menu item', isscalar(mnu));
    results(end+1,:) = check('...and it is available with no config loaded', mnu.Enable == "on");

    % With nothing loaded the window must still open and say why it is empty,
    % rather than refusing or throwing.
    feval(mnu.MenuSelectedFcn, mnu, []);
    dbg = findall(groot, 'Type','figure', 'Tag','EPsychParameterDebugger');
    results(end+1,:) = check('The menu opened the debugger', isscalar(dbg));

    dbg = dbg.UserData;
    figs(end+1) = dbg.H.figure;
    dbg.H.figure.Visible = 'off';
    results(end+1,:) = check('It bound itself to the session', isequal(dbg.RunExpt, rx));
    results(end+1,:) = check('An empty session explains itself', ...
        isempty(dbg.Rows) && contains(dbg.H.emptyState.Text, 'No protocol is loaded'));

    % A subject's protocol is reachable as soon as it is in CONFIG -- before a
    % run, and whether or not the interfaces are connected.
    proto = epsych.Protocol;
    proto.addInterface(rig);
    rx.CONFIG(1).PROTOCOL = proto;
    rx.CONFIG(1).SUBJECT = epsych.Subject.fromStruct( ...
        struct('BoxID',3, 'Name','M001', 'Sex','M', 'Species','Mouse'));

    dbg.refresh();
    results(end+1,:) = check('A loaded protocol is offered as a source', ...
        strcmp(dbg.H.source.Value, '1: M001 (box 3)'));
    results(end+1,:) = check('...and its parameters are listed', numel(dbg.Rows) == 23);
catch ME
    results(end+1,:) = check(['RunExpt launch: ' ME.message], false);
end

%% 20. Teardown
try
    if ispref('epsych2_gui_ParameterDebugger','FigurePosition')
        rmpref('epsych2_gui_ParameterDebugger','FigurePosition');
    end

    fig = dbg.H.figure;
    close(fig);                       % the way an operator closes it
    figs = matlab.ui.Figure.empty;

    results(end+1,:) = check('Closing the window deletes the object', ~isvalid(dbg));
    results(end+1,:) = check('...and the figure with it', ~isgraphics(fig));
    results(end+1,:) = check('The window position was remembered', ...
        ispref('epsych2_gui_ParameterDebugger','FigurePosition'));
    results(end+1,:) = check('The interface it was pointed at survives', isvalid(rig));
    results(end+1,:) = check('No timers were left behind', ...
        isempty(timerfindall('Name','ParameterDebugger*')));
catch ME
    results(end+1,:) = check(['Teardown: ' ME.message], false);
end

%% Cleanup
delete(figs(isvalid(figs)));
delete(findall(groot, 'Type','figure', 'Tag','RunExpt'));
delete(findall(groot, 'Type','figure', 'Tag','EPsychParameterDebugger'));
if ~isempty(rx) && isvalid(rx), delete(rx); end
try
    if ispref('epsych2_gui_ParameterDebugger','FigurePosition')
        rmpref('epsych2_gui_ParameterDebugger','FigurePosition');
    end
catch ME
    vprintf(2, ME);
end

%% Summary
labels = results(:,1);
passed = cell2mat(results(:,2));
for i = 1:numel(labels)
    if passed(i)
        fprintf('  PASS  %s\n', labels{i});
    else
        fprintf('  FAIL  %s\n', labels{i});
    end
end
fprintf('\n%d passed, %d failed, %d total\n\n', ...
    sum(passed), sum(~passed), numel(passed));

if any(~passed)
    error('smoke_test_parameter_debugger:Failed', '%d smoke test(s) failed.', sum(~passed));
end


function row = check(label, tf)
% row = check(label, tf)
% Record one assertion as a {label, logical} row.
row = {label, logical(tf)};
end


function idx = rowIndex(dbg, name)
% Table row showing the named parameter.
idx = find(strcmp({dbg.Rows.Name}, name), 1);
assert(~isempty(idx), 'no row named "%s"', name);
end


function R = rowNamed(dbg, name)
R = dbg.Rows(rowIndex(dbg, name));
end


function editCell(dbg, row, text)
% Type text into a row's Value cell, exactly as the table callback receives it.
col = find(strcmp(dbg.H.table.ColumnName, 'Value'), 1);
previous = dbg.H.table.Data{row, col};
dbg.H.table.Data{row, col} = text;
dbg.H.table.CellEditCallback(dbg.H.table, ...
    struct('Indices', [row col], 'NewData', text, 'PreviousData', previous));
end


function closeAfter(mock, n, dbg)
% Delete the debugger part-way through a read sweep, as an operator pressing
% Escape on an unresponsive rig would.
if mock.ReadCount == n && isvalid(dbg)
    delete(dbg);
end
end


function c = styleColorAt(styles, row, col)
% BackgroundColor of the last style whose target covers this cell, or [].
c = [];
if isempty(styles), return, end
for i = 1:height(styles)
    if string(styles.Target(i)) ~= "cell", continue, end
    t = styles.TargetIndex{i};
    if any(t(:,1) == row & t(:,2) == col)
        c = styles.Style(i).BackgroundColor;
    end
end
end
