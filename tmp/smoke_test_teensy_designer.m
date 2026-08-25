function smoke_test_teensy_designer()
% smoke_test_teensy_designer()
% Exercise the Teensy trial-program stack end to end with no hardware:
% the Program model and its cascading renames, exact struct round-tripping,
% validation, every paradigm template, the wire compiler, the simulator's
% hit/miss/abort/ratio paths and its determinism, Monte Carlo summaries,
% and the teensy.TrialDesigner GUI built headlessly and torn down cleanly.
%
% Headless-safe: every figure is created invisible and deleted before
% returning, and the designer's preference group is restored.
%
%   matlab -batch "run('tmp/smoke_test_teensy_designer.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

PREF_GROUP = 'epsych2_teensy_TrialDesigner';
cleanupObj = onCleanup(@() cleanupAll(PREF_GROUP));

% 1. Program model: build, look up, resolve ------------------------------
p = teensy.Program(Name = "Smoke", BoxID = 3);
p.Channels = teensy.Channel.defaultSet();
assert(numel(p.Channels) == 6, 'default channel set should have 6 channels');
assert(p.channelIndex("Poke") == 1, 'Poke should be the first default channel');

p.addVariable(teensy.Variable("RespWinDur", Value = 2000, Min = 100, Max = 9000, Units = "ms"));
p.addState(teensy.State("ITI", DurationMs = 500));
p.addState(teensy.State("Wait", DurationMs = "@RespWinDur"));
p.addState(teensy.State("Hit", IsTerminal = true, ...
    RespCodeBits = [epsych.BitMask.Hit, epsych.BitMask.Reward]));
p.addState(teensy.State("Miss", IsTerminal = true, RespCodeBits = epsych.BitMask.Miss));
p.StartState = "ITI";

p.States(1).Transitions(end+1) = teensy.Transition.to("Wait", teensy.Condition.timerElapsed());
p.States(2).Transitions(end+1) = teensy.Transition.to("Hit", ...
    teensy.Condition.digitalEdge("Poke", "Rising"));
p.States(2).Transitions(end+1) = teensy.Transition.to("Miss", teensy.Condition.timerElapsed());
p.States(3).EntryActions(end+1) = teensy.Action.markLatency();
p.States(3).EntryActions(end+1) = teensy.Action.pulse("Reward", 40);

assert(p.resolve("@RespWinDur") == 2000, 'variable reference should resolve to its default');
assert(isnan(p.resolve("@NoSuchVar")), 'an unknown reference should resolve to NaN, not throw');
fprintf('PASS: program construction, lookup and reference resolution\n');

% 2. Reachability and layout ---------------------------------------------
G = p.graph();
assert(all(G.Reachable), 'every state should be reachable from ITI');
assert(numel(G.Edges) == 3, 'expected 3 transitions, got %d', numel(G.Edges));

p.autoLayout();
positions = vertcat(p.States.Position);
assert(all(positions(:) >= 0 & positions(:) <= 1), 'layout must stay in the unit square');
assert(positions(1, 1) < positions(3, 1), 'the start state should be left of a terminal state');
fprintf('PASS: graph reachability and deterministic auto-layout\n');

% 3. Cascading renames ----------------------------------------------------
p.renameState("Wait", "RespWindow");
assert(p.States(1).Transitions(1).Target == "RespWindow", ...
    'renaming a state must rewrite transitions that target it');

p.renameChannel("Poke", "Snout");
assert(p.States(2).Transitions(1).Condition.Channel == "Snout", ...
    'renaming a channel must rewrite conditions that read it');

p.renameVariable("RespWinDur", "WindowMs");
assert(string(p.States(2).DurationMs) == "@WindowMs", ...
    'renaming a variable must rewrite the references to it');
fprintf('PASS: renames cascade through states, conditions and references\n');

% 4. Exact serialization round trip ---------------------------------------
S = p.toStruct();
q = teensy.Program.fromStruct(S);
assert(isequal(S, q.toStruct()), 'toStruct/fromStruct must round-trip exactly');

nested = teensy.Condition.all([ ...
    teensy.Condition.digitalEdge("Snout", "Rising"), ...
    teensy.Condition.negate(teensy.Condition.analogThreshold("Piezo", "Above", 1.5, 10))]);
p.States(2).Transitions(1).Condition = nested;
S2 = p.toStruct();
assert(isequal(S2, teensy.Program.fromStruct(S2).toStruct()), ...
    'a nested And/Not condition tree must round-trip exactly');
fprintf('PASS: exact struct round trip, including nested condition trees\n');

% 5. Save and load --------------------------------------------------------
tmpFile = [tempname '.etsm'];
p.save(tmpFile);
loaded = teensy.Program.load(tmpFile);
assert(isequal(p.toStruct(), loaded.toStruct()), 'a saved program must load back identically');
delete(tmpFile);
fprintf('PASS: .etsm save and load\n');

% 6. Validation catches real mistakes -------------------------------------
bad = teensy.Templates.get("GoNoGoDetection");
bad.States(1).Transitions(1).Target = "Nowhere";
assert(hasIssue(bad.validate(), "error", "There is no state named"), ...
    'a dangling transition target should be an error');

bad = teensy.Templates.get("GoNoGoDetection");
bad.Channels(2).Pin = bad.Channels(1).Pin;
assert(hasIssue(bad.validate(), "error", "is claimed by"), ...
    'two channels on one pin should be an error');

bad = teensy.Templates.get("GoNoGoDetection");
bad.States(2).DurationMs = "@Undefined";
assert(hasIssue(bad.validate(), "error", "undefined variable"), ...
    'a reference to a missing variable should be an error');

bad = teensy.Templates.get("GoNoGoDetection");
for i = 1:numel(bad.States)
    bad.States(i).IsTerminal = false;
end
assert(hasIssue(bad.validate(), "error", "never complete"), ...
    'a program with no terminal state should be an error');

bad = teensy.Templates.get("GoNoGoDetection");
bad.addState(teensy.State("Orphan", DurationMs = 100));
assert(hasIssue(bad.validate(), "warning", "No transition path reaches"), ...
    'an unreachable state should be a warning');
fprintf('PASS: validation catches dangling targets, pin clashes, bad refs, dead ends\n');

% 7. Every template validates and compiles --------------------------------
compiler = teensy.Compiler();
names = teensy.Templates.names();
assert(numel(names) >= 8, 'expected at least 8 templates, got %d', numel(names));

for i = 1:numel(names)
    t = teensy.Templates.get(names(i));
    report = t.validate();
    assert(~teensy.Compiler.hasError(report), ...
        'template %s has validation errors', names(i));

    result = compiler.compile(t);
    assert(result.Ok, 'template %s did not compile', names(i));
    assert(strcmp(result.Lines{1}, 'PROG BEGIN'), 'the wire program must be framed');
    assert(strcmp(result.Lines{end}, 'PROG END'), 'the wire program must be framed');
    assert(all(cellfun(@numel, result.Lines) <= teensy.Compiler.LIMITS.MAX_LINE_CHARS), ...
        'template %s emitted an over-long record', names(i));

    assert(isequal(t.toStruct(), teensy.Program.fromStruct(t.toStruct()).toStruct()), ...
        'template %s does not round-trip', names(i));
end
fprintf('PASS: all %d templates validate, compile and round-trip\n', numel(names));

% 7b. The lab paradigm keeps the names its existing BehaviorGUI binds to ------
% cl_AppetitiveDetection_BehaviorGUI resolves these by name through
% gui.components.Parameter_Monitor and gui.components.Parameter_Control, so a Teensy-backed
% protocol only lights that GUI up if the template emits them exactly.
appetitive = string({teensy.Templates.get("AppetitiveDetection").parameterSpecs().Name});
for required = ["Platform", "Trough", "InTrial", "DelayPeriod", "RespWindow", ...
        "PelletTotal", "StimDelay", "RespWinDelay", "RespLatency", "RespCode", ...
        "ITIDur", "TimeoutDur", "NumPellets"]
    assert(any(appetitive == required), ...
        'AppetitiveDetection must emit %s for the existing BehaviorGUI', required);
end
fprintf('PASS: AppetitiveDetection emits the names cl_AppetitiveDetection_BehaviorGUI binds\n');

% 8. The parameter set the runtime requires -------------------------------
specs = teensy.Templates.get("GoNoGoDetection").parameterSpecs();
specNames = string({specs.Name});

for required = ["x_NewTrial_1", "x_ResetTrig_1", "x_TrialComplete_1", ...
        "RespCode", "RespLatency", "TrialType", "_TrigState~1", "_TrialNum~1"]
    assert(any(specNames == required), 'missing required parameter %s', required);
end

% Triggers must be Access='Any'. hw.Interface.all_parameters excludes 'Write'
% from a 'Read' filter, so a 'Write' trigger would never be found by
% epsych.Runtime.resolveTriggerParameters and the run would abort.
trigger = specs(specNames == "x_NewTrial_1");
assert(strcmp(trigger.Options.Access, 'Any'), 'triggers must use Access=Any, not Write');
assert(trigger.Options.isTrigger, 'triggers must set isTrigger');
assert(~trigger.UpdateEveryTrial, 'a trigger must not be dispatched every trial');

respCode = specs(specNames == "RespCode");
assert(strcmp(respCode.Options.Access, 'Read'), 'RespCode must be readable');
assert(strcmp(respCode.Options.Type, 'Integer'), 'RespCode must be an integer bitmask');
fprintf('PASS: parameterSpecs emits the names and access the runtime requires\n');

% 9. Parameters actually land on a real hw.Module -------------------------
iface = hw.Software();
module = hw.Module(iface, 'TSY', 'Teensy', uint8(1));
created = teensy.Templates.get("FixedRatio").applyToModule(module);
assert(~isempty(created), 'applyToModule should create parameters');
assert(numel(module.Parameters) == numel(created), 'parameters should land on the module');

again = teensy.Templates.get("FixedRatio").applyToModule(module);
assert(isempty(again), 'applying twice should be idempotent in merge mode');
fprintf('PASS: applyToModule creates real hw.Parameter objects and is idempotent\n');

% 10. Simulator: the outcome paths of a real paradigm ---------------------
gonogo = teensy.Templates.get("GoNoGoDetection");
gonogo.Variables(gonogo.variableIndex("P_Catch")).Value = 0;   % force signal trials

% ITI 3000 + PreStim 500 + Stimulus 500 = the window opens at 4000 ms.
sim = teensy.Simulator(gonogo, TimeStepMs = 0.5);
sim.runTrial([4200 1 1; 4300 1 0]);
decoded = epsych.BitMask.decode(sim.RespCode);
assert(sim.Completed && decoded.Hit, 'responding in the window should be a hit');
assert(decoded.Reward, 'a hit should also set the reward bit');
assert(isfinite(sim.RespLatency) && sim.RespLatency > 4000, ...
    'RespLatency should be milliseconds from trial start, got %g', sim.RespLatency);

sim = teensy.Simulator(gonogo, TimeStepMs = 0.5);
sim.runTrial([]);
assert(epsych.BitMask.decode(sim.RespCode).Miss, 'no response should be a miss');

sim = teensy.Simulator(gonogo, TimeStepMs = 0.5);
sim.runTrial([3200 1 1; 3300 1 0]);
assert(epsych.BitMask.decode(sim.RespCode).Abort, ...
    'responding before the window opens should abort');

gonogo.Variables(gonogo.variableIndex("P_Catch")).Value = 1;   % force catch trials
sim = teensy.Simulator(gonogo, TimeStepMs = 0.5);
sim.runTrial([4200 1 1; 4300 1 0]);
assert(epsych.BitMask.decode(sim.RespCode).FalseAlarm, ...
    'responding on a catch trial should be a false alarm');
fprintf('PASS: simulator reproduces hit, miss, abort and false-alarm paths\n');

% 11. Counters and determinism -------------------------------------------
fr = teensy.Templates.get("FixedRatio");
sim = teensy.Simulator(fr, TimeStepMs = 0.5);
script = [];
for k = 1:5
    script = [script; 2100 + k * 200, 1, 1; 2100 + k * 200 + 80, 1, 0];
end
sim.runTrial(script);
assert(sim.Counters.Responses == 5, 'the counter should have tallied 5 responses');
assert(epsych.BitMask.decode(sim.RespCode).Reward, 'completing the ratio should reward');

a = teensy.Simulator(gonogo, Seed = 42, TimeStepMs = 0.5);
Ta = a.runTrial([4200 1 1; 4300 1 0]);
b = teensy.Simulator(gonogo, Seed = 42, TimeStepMs = 0.5);
Tb = b.runTrial([4200 1 1; 4300 1 0]);
assert(isequal(Ta.StateIndex, Tb.StateIndex) && Ta.RespCode == Tb.RespCode, ...
    'the same seed must replay identically');
fprintf('PASS: counters tally correctly and a seeded run replays exactly\n');

% 12. Monte Carlo ---------------------------------------------------------
gonogo.Variables(gonogo.variableIndex("P_Catch")).Value = 0.3;
responder = teensy.Simulator.Responder("guessing", Channel = "Poke", ...
    PRespond = 0.7, LatencyMs = 4300, LatencyJitterMs = 200);
[results, summary] = teensy.Simulator.monteCarlo(gonogo, responder, 60, TimeStepMs = 1);

assert(height(results) == 60, 'monteCarlo should return one row per trial');
assert(all(ismember({'Hit', 'Miss', 'FalseAlarm', 'CorrectReject'}, ...
    results.Properties.VariableNames)), 'outcome columns should be decoded into the table');
assert(summary.NTrials == 60, 'the summary should report the trial count');
assert(sum(results.Hit) + sum(results.Miss) + sum(results.FalseAlarm) + ...
    sum(results.CorrectReject) > 0, 'a guessing subject should produce outcomes');
fprintf('PASS: Monte Carlo returns a decoded table and summary rates\n');

% 12b. Monte Carlo early stop --------------------------------------------
% The designer's Stop button works by way of ShouldStop, so what matters is
% that a stopped run returns whole trials and a summary counting only those.
stopAfter = 7;
tally = containers.Map({'n'}, {0});   % a handle, so the closure can count
[partial, pSummary] = teensy.Simulator.monteCarlo(gonogo, responder, 60, ...
    TimeStepMs = 1, ShouldStop = @() localStopAfter_(tally, stopAfter));
assert(height(partial) == stopAfter, ...
    'a stopped run should return only the trials that ran, got %d', height(partial));
assert(pSummary.NTrials == stopAfter, ...
    'the summary should count only the trials that ran');
assert(all(partial.TrialNum == (1:stopAfter)'), 'the kept trials should be the first ones');

[full, fSummary] = teensy.Simulator.monteCarlo(gonogo, responder, 12, ...
    TimeStepMs = 1, ShouldStop = @() false);
assert(height(full) == 12 && fSummary.NTrials == 12, ...
    'a ShouldStop that never fires must not change the run');
fprintf('PASS: Monte Carlo stops early on request and returns partial results\n');

% 13. The GUI, built headlessly ------------------------------------------
d = teensy.TrialDesigner(teensy.Templates.get("GoNoGoDetection"), Visible = false);
assert(isvalid(d.Figure), 'the designer figure should exist');
assert(numel(d.TabGroup.Children) == 5, 'the designer should have 5 tabs');
assert(size(d.HChannels.Table.Data, 1) == 6, 'the channel table should be populated');
assert(numel(d.HStates.List.Items) == 10, 'the state list should be populated');
assert(numel(d.HStates.NodeMap) == 10, 'the diagram should have one node per state');
assert(size(d.HVariables.Preview.Data, 1) > 0, 'the parameter preview should be populated');

nBefore = numel(d.Program.States);
d.onStates('add');
assert(numel(d.Program.States) == nBefore + 1, 'the GUI should add a state');
d.onUndo();
assert(numel(d.Program.States) == nBefore, 'undo should remove the added state');
d.onRedo();
assert(numel(d.Program.States) == nBefore + 1, 'redo should restore it');

d.SelectedChannel = 1;
d.onChannels('field', 'Name', 'Snout');
assert(d.Program.States(d.Program.stateIndex("PreStim")).Transitions(1).Condition.Channel == "Snout", ...
    'renaming through the GUI should cascade into conditions');
d.onUndo();
assert(d.Program.States(d.Program.stateIndex("PreStim")).Transitions(1).Condition.Channel == "Poke", ...
    'undo should restore a cascaded rename');

d.onCompile('compile');
assert(d.CompileResult.Ok, 'the GUI should compile the template');
assert(size(d.HCompile.Capacity.Data, 1) > 0, 'the capacity table should be populated');

for i = 1:numel(d.TabGroup.Children)
    d.TabGroup.SelectedTab = d.TabGroup.Children(i);
    d.onTabChanged([]);
end

d.onSimulate('start');
pause(0.25);
d.onSimulate('pause');
assert(~isempty(d.Simulator), 'the test bench should have a simulator');
d.onSimulate('reset');
assert(isempty(d.Simulator), 'reset should clear the simulator');

% The Monte Carlo path builds a Stop-capable progress dialog, which is [] on an
% invisible figure -- so this also proves the run survives having no dialog.
d.HSim.NTrials.Value = 8;
d.onSimulate('montecarlo');
assert(size(d.HSim.MCTable.Data, 1) > 0, 'the Monte Carlo summary table should be filled');
assert(any(strcmp(d.HSim.MCTable.Data(:, 1), 'NTrials')), ...
    'the summary table should report the trial count');
fprintf('PASS: designer builds, edits, undoes, compiles and simulates headlessly\n');

% 13b. Live monitor mode against a session -------------------------------
% Opening the designer on a Runtime attaches a mode listener and a poll
% timer. Both have to survive a Runtime whose session has not started yet,
% which is the state RunExpt is in before Run is pressed.
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;
sw = hw.Software;
stateParam = sw.add_parameter('StateIndex', 0);
stateParam.Value = 0;
stateParam.Access = 'Read';
rt.Interfaces = sw;

live = teensy.TrialDesigner(rt, Visible = false);
assert(~isempty(live.RUNTIME), 'the designer should hold the runtime');
assert(~isempty(live.LiveTimer) && strcmp(live.LiveTimer.Running, 'on'), ...
    'live monitor mode should start its poll timer');

% The mode listener walks heterogeneous handle structs to lock editing.
% isgraphics(0) is true, so a class test has to precede isvalid or this
% throws on the plain state those structs also carry.
lastwarn('');
rt.EVENTS.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Record));
pause(0.2);
assert(isempty(lastwarn), 'a ModeChange should not raise a warning: %s', lastwarn);
rt.EVENTS.notify('ModeChange', epsych.eventModeChange(hw.DeviceState.Stop));
pause(0.2);
assert(isempty(lastwarn), 'a ModeChange should not raise a warning: %s', lastwarn);
delete(live);

% A Runtime with no EVENTS yet must open, not throw.
bare = epsych.Runtime;
bare.isTest = true;
noEvents = teensy.TrialDesigner(bare, Visible = false);
assert(isvalid(noEvents.Figure), 'the designer should open on a runtime with no event hub');
delete(noEvents);
fprintf('PASS: live monitor attaches, locks on mode change, and tolerates no helper\n');

% 14. Teardown leaves nothing behind -------------------------------------
delete(d);
assert(isempty(findall(groot, 'Type', 'figure', '-and', 'Tag', PREF_GROUP)), ...
    'the designer figure should be gone after delete');
assert(isempty(timerfindall('Name', 'TeensyDesignerSim')), ...
    'the simulation timer should be stopped and deleted');
assert(isempty(timerfindall('Name', 'TeensyDesignerLive')), ...
    'the live-monitor timer should be stopped and deleted');
fprintf('PASS: teardown deletes the figure and every timer\n');

fprintf('\nsmoke_test_teensy_designer: all checks passed\n');
end


function tf = localStopAfter_(tally, limit)
% tf = localStopAfter_(tally, limit)
% Stand in for the designer's Stop button: true once `limit` trials have run.
tally('n') = tally('n') + 1;
tf = tally('n') >= limit;
end


function tf = hasIssue(report, severity, fragment)
% tf = hasIssue(report, severity, fragment)
% True when the report contains an issue of that severity whose message
% contains the fragment.
tf = false;
for i = 1:numel(report)
    if report(i).Severity == severity && contains(report(i).Message, fragment)
        tf = true;
        return
    end
end
end


function cleanupAll(prefGroup)
% cleanupAll(prefGroup)
% Close any designer left open and drop its preferences.
figs = findall(groot, 'Type', 'figure', '-and', 'Tag', prefGroup);
for i = 1:numel(figs)
    ud = figs(i).UserData;
    figs(i).CloseRequestFcn = '';
    delete(figs(i));
    if isa(ud, 'teensy.TrialDesigner') && isvalid(ud)
        delete(ud);
    end
end

if ispref(prefGroup)
    rmpref(prefGroup);
end
end
