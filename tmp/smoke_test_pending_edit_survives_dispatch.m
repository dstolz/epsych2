function smoke_test_pending_edit_survives_dispatch()
% smoke_test_pending_edit_survives_dispatch()
% An operator's uncommitted gui.components.Parameter_Control edit must survive
% a write to its parameter from outside -- above all the one
% epsych.Runtime.dispatchNextTrial makes to every parameter at every trial
% boundary. Before the fix that write replaced the edit with the old value
% while ValueUpdated stayed true, so the (still green) Update button then
% committed the OLD value: "the value reverts on the next trial".
%
% Also checks that gui.components.Parameter_Update still shows, and stores in
% the trial table, the value the parameter actually took, and that a failed
% commit leaves the edit pending.
%
% Uses an invisible uifigure and a software-only runtime; no hardware.
%
%   matlab -batch "run('tmp/smoke_test_pending_edit_survives_dispatch.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

tmpDir = tempname; mkdir(tmpDir);
cleanupTmp = onCleanup(@() rmdir(tmpDir,'s'));

fig = uifigure('Visible','off');
cleanupFig = onCleanup(@() delete(fig));

rt = makeRuntime(tmpDir);
pITI   = rt.find_parameter('ITIDur');
pLevel = rt.find_parameter('Level');
pDelay = rt.find_parameter('Delay');


% 1. A pending edit survives the trial-boundary re-dispatch ------------------
hITI = gui.components.Parameter_Control(fig, pITI, Type='editfield');
assert(hITI.Value == 1000, 'the control should seat at the parameter value');

typeInto(hITI, 2500);
assert(hITI.ValueUpdated, 'an edit should be pending');

rt.dispatchNextTrial(1);
assert(pITI.Value == 1000, 'the dispatch should have re-applied the table value');
assert(hITI.Value == 2500, ...
    'the re-dispatch replaced the pending edit (widget shows %g)', hITI.Value);
assert(hITI.ValueUpdated, 'the edit should still be pending after the dispatch');
fprintf('PASS: a pending edit survives the trial-boundary re-dispatch\n');


% 2. An outside write that arrives AT the pending value clears it ------------
pITI.Value = 2500;
assert(~hITI.ValueUpdated, 'the parameter reached the pending value; nothing is pending');

% ...and with nothing pending, outside writes are followed as before.
pITI.Value = 1000;
assert(hITI.Value == 1000, 'with no pending edit the widget should follow the parameter');

% An autoCommit control writes its edit as it is made, so it never holds a
% pending one -- even though value_changed leaves ValueUpdated set after the
% write. A later outside write (a phase load) must still reach it.
hAuto = gui.components.Parameter_Control(fig, pLevel, Type='editfield', autoCommit=true);
typeInto(hAuto, 70);
assert(pLevel.Value == 70, 'the autoCommit edit should have been written');
pLevel.Value = 40;
assert(hAuto.Value == 40, ...
    'an autoCommit control stopped following outside writes (shows %g)', hAuto.Value);
delete(hAuto);
fprintf('PASS: outside writes still sync a control with nothing pending\n');


% 2b. A write that CHANGES the parameter supersedes the pending edit --------
% A phase load (or a linked parameter) is newer than the edit. Kept, the
% stale edit would hide the phase's value, and the next Update click would
% quietly write it back over the phase the operator just chose.
typeInto(hITI, 2500);
pITI.Value = 1500;                   % e.g. a phase load
assert(hITI.Value == 1500, 'a real change should replace the pending edit (shows %g)', hITI.Value);
assert(~hITI.ValueUpdated, 'a superseded edit should no longer be pending');
pITI.Value = 1000;                   % back to the trial-table value for what follows
fprintf('PASS: a real outside change supersedes a pending edit\n');


% 3. Range and Min-bound controls follow the same rule ----------------------
hRange = gui.components.Parameter_Control(fig, pDelay, Type='range');
hRange.h_uiobj.Value  = 1200;
hRange.h_uiobj2.Value = 2800;
hRange.value_changed(hRange.h_uiobj, struct('Value',1200,'PreviousValue',1000, ...
    'EventName','ValueChanged'));
assert(hRange.ValueUpdated, 'a range edit should be pending');

pDelay.Min = 1000;   % re-asserting the bound the edit was made against
assert(isequal(hRange.Value, [1200 2800]), 'a re-asserted Min replaced the pending range');
assert(hRange.ValueUpdated, 'the range edit should still be pending');

pDelay.Min = 1100;   % a real change, e.g. a phase load
assert(isequal(hRange.Value, [1100 3000]), 'a changed Min should replace the pending range');
assert(~hRange.ValueUpdated, 'the superseded range edit should no longer be pending');

hMin = gui.components.Parameter_Control(fig, pLevel, Type='editfield', BoundProperty='Min');
typeInto(hMin, 10);
pLevel.Min = 0;      % re-assert
assert(hMin.Value == 10 && hMin.ValueUpdated, 'a re-asserted Min replaced the pending Min edit');
pLevel.Min = 5;      % real change
assert(hMin.Value == 5 && ~hMin.ValueUpdated, 'a changed Min should replace the pending Min edit');

typeInto(hMin, 10);
hMin.reset_value;
assert(hMin.Value == 5 && ~hMin.ValueUpdated, 'reset should restore the current Min');
fprintf('PASS: range and Min-bound edits: kept on re-assert, replaced on change\n');


% 4. End to end: edit -> boundary -> Update -> next boundary ----------------
U = gui.components.Parameter_Update(rt, fig);
U.watchedHandles = [hITI hRange hMin];

typeInto(hITI, 2500);
rt.dispatchNextTrial(1);                          % boundary before the click
U.modifiers_changed({'shift','control','alt'});   % "update immediately"
U.button_pushed([], []);

col = rt.TRIALS(1).writeParamIdx.ITIDur;
assert(pITI.Value == 2500, 'the commit should write the edit, not the old value (%g)', pITI.Value);
assert(all(cellfun(@(v) isequal(v,2500), rt.TRIALS(1).trials(:,col))), ...
    'the trial table should hold the committed value');
assert(~hITI.ValueUpdated, 'nothing should be pending after the commit');

rt.dispatchNextTrial(1);
assert(pITI.Value == 2500, 'the next trial reverted the committed value (%g)', pITI.Value);
fprintf('PASS: a value committed after a boundary holds on the next trial\n');


% 5. The commit shows and stores the value the parameter actually took -------
pITI.EvaluatorFcn = @(~,v) round(v/100)*100;
typeInto(hITI, 3456);
U.modifiers_changed({'shift','control','alt'});
U.button_pushed([], []);
assert(pITI.Value == 3500, 'the evaluator should have rounded the write');
assert(hITI.Value == 3500, 'the widget should show the value taken (%g)', hITI.Value);
assert(isequal(rt.TRIALS(1).trials{1,col}, 3500), 'the table should hold the value taken');
assert(~hITI.ValueUpdated, 'nothing should be pending after the commit');
fprintf('PASS: the commit shows and stores the read-back value\n');


% 6. A failed commit leaves the edit pending ---------------------------------
pITI.EvaluatorFcn = @refuseWrite;
typeInto(hITI, 4000);
U.modifiers_changed({'shift','control','alt'});
threw = false;
try
    U.button_pushed([], []);
catch ME
    threw = strcmp(ME.identifier,'smoke:refused');
end
pITI.EvaluatorFcn = [];
assert(threw, 'the evaluator error should propagate out of the commit');
assert(hITI.ValueUpdated && hITI.Value == 4000, ...
    'a failed commit should leave the edit pending (widget %g, pending %d)', ...
    hITI.Value, hITI.ValueUpdated);
assert(pITI.Value == 3500, 'the refused write should have left the parameter alone');
fprintf('PASS: a failed commit leaves the edit pending\n');


% 7. A commit survives the recompile a phase load schedules -----------------
% The rig log that reported this: a phase load set NumPellets = 1 and
% scheduled a recompile; an immediate commit of 2 then reached the hardware
% and the table, and the recompile at the next boundary rebuilt the table
% from Values -- still {1} -- so the next trial ran 1 again.
rt.TRIALS(1).RECOMPILE_REQUESTED = true;    % what readParameters does
typeInto(hITI, 5000);
U.modifiers_changed({'shift','control','alt'});
U.button_pushed([], []);
assert(isequal(pITI.Values, {5000}), 'the commit should carry the value into Values');

boundary(rt);
assert(~rt.TRIALS(1).RECOMPILE_REQUESTED, 'the boundary should have run the recompile');
col = rt.TRIALS(1).writeParamIdx.ITIDur;
assert(all(cellfun(@(v) isequal(v,5000), rt.TRIALS(1).trials(:,col))), ...
    'the recompiled trial table lost the committed value');
assert(pITI.Value == 5000, 'the recompile reverted the committed value (%g)', pITI.Value);

% The autoCommit path writes the table the same way and needs the same hold.
hAutoL = gui.components.Parameter_Control(fig, pLevel, Type='editfield', ...
    autoCommit=true, Runtime=rt);
rt.TRIALS(1).RECOMPILE_REQUESTED = true;
typeInto(hAutoL, 55);
boundary(rt);
assert(pLevel.Value == 55, 'the recompile reverted an autoCommit edit (%g)', pLevel.Value);
delete(hAutoL);
fprintf('PASS: commits survive a recompile scheduled before them\n');


% 8. With no recompile pending, Values is left as the protocol designed it ---
typeInto(hITI, 6000);
U.modifiers_changed({'shift','control','alt'});
U.button_pushed([], []);
assert(pITI.Value == 6000, 'the commit should still land');
assert(isequal(pITI.Values, {5000}), ...
    'with nothing pending, a commit must not rewrite the design Values');
fprintf('PASS: design Values are touched only while a recompile is pending\n');

delete(U); delete(hITI); delete(hRange); delete(hMin);
fprintf('\nAll pending-edit checks passed.\n');
end


function typeInto(h, v)
% typeInto(h, v)
% What the widget does when the operator types v and presses Enter.
field = h.h_uiobj;
ev = struct('Value', v, 'PreviousValue', field.Value, 'EventName', 'ValueChanged');
field.Value = v;
h.value_changed(field, ev);
end


function boundary(rt)
% boundary(rt)
% One trial boundary through the real trial loop; FORCE_TRIAL skips waiting
% on the (software) TrialComplete trigger.
rt.TRIALS(1).FORCE_TRIAL = true;
ep_TimerFcn_RunTime(rt);
end


function v = refuseWrite(~, ~)
% v = refuseWrite(~, ~)
% An EvaluatorFcn that refuses every write. A named function because an
% anonymous one wrapping error() fails with MATLAB:maxlhs instead.
v = [];
error('smoke:refused','refused');
end


function rt = makeRuntime(tmpDir)
% rt = makeRuntime(tmpDir)
% Software-only session built the way a real run is: a compiled
% epsych.Protocol handed to ep_TimerFcn_Start.
P = epsych.Protocol(Name='PendingEdit', Info='pending-edit smoke test');

P.addParameter('Software','TrialType',[0 1],Type='Integer');
P.addParameter('Software','ITIDur',1000,Type='Float');
P.addParameter('Software','Level',60,Type='Float');
P.addParameter('Software','Delay',2000,Type='Float');

sw = P.findInterface('Software');
sw.add_parameter('x_NewTrial_1',      0, isTrigger=true);
sw.add_parameter('x_ResetTrig_1',     0, isTrigger=true);
sw.add_parameter('x_TrialComplete_1', 0, isTrigger=true);

p = sw.find_parameter('ITIDur'); p.Min = 0;    p.Max = 10000;
p = sw.find_parameter('Level');  p.Min = 0;    p.Max = 100;
p = sw.find_parameter('Delay');  p.Min = 1000; p.Max = 3000;

P.compile();

rt = epsych.Runtime;
rt.isTest       = true;
rt.EVENTS       = epsych.EventHub;
rt.Interfaces   = P.Interfaces;
rt.Protocol     = P;
rt.DefaultDataPath = tmpDir;
rt.TempDataDir  = tmpDir;

subject = epsych.DefaultSubject(struct('Name','PendingSubject', ...
    'Species','Mouse', 'Sex','Unknown', 'BoxID',1));

rt = ep_TimerFcn_Start(rt, struct('PROTOCOL',P,'SUBJECT',subject));
end
