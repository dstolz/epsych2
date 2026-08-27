function smoke_test_modifier_buttons()
% smoke_test_modifier_buttons()
% Exercise gui.components.Parameter_Control's ModifierActions: the canonical
% modifier set, arming and repaint, the click that replaces the normal
% trigger or commit, exact-chord matching, the toggle widget restore, and
% the gates that refuse to arm.
%
% Uses invisible uifigures and an hw.Software backend; no hardware.
%
%   matlab -batch "run('tmp/smoke_test_modifier_buttons.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));
addpath(here);                          % ModifierButtonBehaviorGUI lives beside this test


% 1. gui.KeyBindings.normalizeModifiers -----------------------------------
n = @gui.KeyBindings.normalizeModifiers;

assert(isequal(n('ctrl'), {'control'}), 'ctrl is the control modifier');
assert(isequal(n('Ctrl+Shift'), {'control','shift'}), 'case is not part of a modifier set');
assert(isequal(n('shift+ctrl'), n('ctrl+shift')), 'modifier order must not matter');
assert(isequal(n('ctrl+alt+shift'), {'control','alt','shift'}), ...
    'canonical order is ctrl, alt, shift');
assert(isequal(n('command'), n('ctrl')), 'command is the mac spelling of ctrl');
assert(isequal(n('option'), n('alt')), 'option is the mac spelling of alt');
assert(isequal(n({'control','shift'}), {'control','shift'}), 'a cell of names is accepted');
assert(isequal(n(["ctrl" "shift"]), {'control','shift'}), 'a string array is accepted');
assert(isequal(n('ctrl+ctrl'), {'control'}), 'a repeated modifier is still one modifier');

assertThrows(@() n('ctrl+r'), 'epsych:KeyBindings:notModifiers', ...
    'a set naming a key is refused');
assertThrows(@() n(''), 'epsych:KeyBindings:emptyChord', ...
    'an empty set is refused');
assertThrows(@() n(42), 'epsych:KeyBindings:badModifiers', ...
    'a non-text set is refused');

% normalize still refuses what normalizeModifiers requires, and vice versa.
assertThrows(@() gui.KeyBindings.normalize('ctrl+shift'), 'epsych:KeyBindings:modifiersOnly', ...
    'the two canonicalizers still cover disjoint inputs');

fprintf('PASS: a held gesture canonicalizes for comparison\n');


% 2. Arming repaints, releasing restores ----------------------------------
fig = uifigure('Visible','off');
cleanupFig = onCleanup(@() delete(fig));
kb = gui.KeyBindings(fig);

sw = hw.Software;
pTrig = sw.add_parameter('!Reward', false, Type='Boolean', isTrigger=true);
sw.mode = hw.DeviceState.Record;

fired = strings(1,0);
hB = gui.components.Parameter_Control(fig, pTrig, Type='momentary', autoCommit=true, ...
    Text='Reward', KeySource=kb, ModifierActions={ ...
        'ctrl',       @(~,~,~) note('big'),   'Large Reward'; ...
        'ctrl+shift', @(~,~,~) note('purge'), 'Purge Line'});

normalText  = hB.h_uiobj.Text;
normalColor = hB.h_uiobj.BackgroundColor;
assert(strcmp(normalText,'Reward'), 'the button starts on its own label');

press(kb, 'control', {'control'});
assert(strcmp(hB.h_uiobj.Text,'Large Reward'), 'holding the chord advertises the action');
assert(~isequal(hB.h_uiobj.BackgroundColor, normalColor), 'and repaints it');

release(kb, 'control', {});
assert(strcmp(hB.h_uiobj.Text, normalText), 'releasing restores the label');
assert(isequal(hB.h_uiobj.BackgroundColor, normalColor), 'and the colour, verbatim');

% An action with no Text of its own says the chord over the normal label.
hB.addModifierAction('alt', @(~,~,~) note('alt'));
press(kb, 'alt', {'alt'});
assert(contains(hB.h_uiobj.Text, 'Reward') && contains(hB.h_uiobj.Text, 'Alt'), ...
    'an unlabelled action names its chord over the normal label');
release(kb, 'alt', {});

fprintf('PASS: an armed button says what a click will do, and puts itself back\n');


% 3. Arming must not read the device --------------------------------------
% The repaint is restored from a cache precisely so a live backend is not
% asked once per keystroke. hw.Parameter.Value is GetObservable, so PostGet
% counts every read the arming path would make.
reads = 0;
trigs = 0;
lRead = listener(pTrig, 'Value', 'PostGet', @(~,~) countRead());
lTrig = listener(pTrig, 'lastUpdated', 'PostSet', @(~,~) countTrig());
cleanupL = onCleanup(@() delete([lRead lTrig]));

for k = 1:5
    press(kb, 'control', {'control'});
    release(kb, 'control', {});
end
assert(reads == 0, 'arming and disarming must not read the parameter');

fprintf('PASS: arming costs no device reads\n');


% 4. The armed click replaces the normal action ---------------------------
trigs = 0;
press(kb, 'control', {'control'});
hB.value_changed(hB.h_uiobj, struct('EventName','ButtonPushed','Value',true));
assert(isequal(fired, "big"), 'the armed action ran');
assert(trigs == 0, 'and the parameter was NOT triggered');
release(kb, 'control', {});

fired = strings(1,0);
hB.value_changed(hB.h_uiobj, struct('EventName','ButtonPushed','Value',true));
assert(isempty(fired), 'an unarmed click runs no alternate action');
assert(trigs == 1, 'an unarmed click triggers normally');

fprintf('PASS: an armed click replaces the trigger; an unarmed one does not\n');


% 5. A chord matches exactly, not as a subset ------------------------------
fired = strings(1,0);
press(kb, 'shift', {'control','shift'});
assert(strcmp(hB.h_uiobj.Text,'Purge Line'), 'the longer chord arms its own action');
hB.value_changed(hB.h_uiobj, struct('EventName','ButtonPushed','Value',true));
assert(isequal(fired, "purge"), 'ctrl+shift runs ctrl+shift, not ctrl');
release(kb, 'shift', {'control'});

% A held set matching nothing declared arms nothing.
fired = strings(1,0);
press(kb, 'shift', {'shift'});
assert(strcmp(hB.h_uiobj.Text, normalText), 'an undeclared chord arms nothing');
hB.value_changed(hB.h_uiobj, struct('EventName','ButtonPushed','Value',true));
assert(isempty(fired), 'and runs nothing');
release(kb, 'shift', {});

assertThrows(@() hB.addModifierAction('shift+ctrl', @(~,~,~) []), ...
    'gui:Parameter_Control:DuplicateModifierAction', ...
    'the same chord twice on one control is refused');

fprintf('PASS: chords match by exact set, and a duplicate is refused\n');


% 6. A toggle keeps its widget where it was --------------------------------
pTog = sw.add_parameter('~Deliver', false, Type='Boolean');
pTog.Value = false;
hT = gui.components.Parameter_Control(fig, pTog, Type='toggle', autoCommit=true, ...
    KeySource=kb, ModifierActions={'ctrl', @(~,~,~) note('toggleAlt')});

fired = strings(1,0);
press(kb, 'control', {'control'});
hT.h_uiobj.Value = true;                % the state button flips before the callback
hT.value_changed(hT.h_uiobj, struct('EventName','ValueChanged','Value',true,'PreviousValue',false));
assert(isequal(fired, "toggleAlt"), 'the toggle ran its alternate action');
assert(~hT.h_uiobj.Value, 'and the widget was put back where it was');
assert(~pTog.Value, 'nothing was committed to the parameter');
release(kb, 'control', {});

fprintf('PASS: an armed toggle does not leave a state nothing was written for\n');


% 7. A throwing action is logged, not propagated ---------------------------
hB.addModifierAction('ctrl+alt', @(~,~,~) error('smoke:boom','deliberate'));
press(kb, 'alt', {'control','alt'});
hB.value_changed(hB.h_uiobj, struct('EventName','ButtonPushed','Value',true));
release(kb, 'alt', {'control'});
release(kb, 'control', {});
assert(strcmp(hB.h_uiobj.Text, normalText), 'the button recovered its own label');

fired = strings(1,0);
press(kb, 'control', {'control'});
hB.value_changed(hB.h_uiobj, struct('EventName','ButtonPushed','Value',true));
assert(isequal(fired, "big"), 'and still works afterwards');
release(kb, 'control', {});

fprintf('PASS: a throwing action is logged, not propagated\n');


% 8. Gates refuse to arm ---------------------------------------------------
hB.setEnabled(false);
press(kb, 'control', {'control'});
assert(strcmp(hB.h_uiobj.Text, normalText), 'a gated control does not arm');
fired = strings(1,0);
hB.value_changed(hB.h_uiobj, struct('EventName','ButtonPushed','Value',true));
assert(isempty(fired), 'and a scripted click on it fails closed');
release(kb, 'control', {});
hB.setEnabled(true);

% An idle rig is the other half of the same AND.
sw.mode = hw.DeviceState.Idle;
press(kb, 'control', {'control'});
assert(strcmp(hB.h_uiobj.Text, normalText), 'an idle interface does not arm');
release(kb, 'control', {});
sw.mode = hw.DeviceState.Record;

% Disarming happens when the gate closes UNDER a held chord, too.
press(kb, 'control', {'control'});
assert(strcmp(hB.h_uiobj.Text,'Large Reward'), 'armed again');
hB.setEnabled(false);
assert(strcmp(hB.h_uiobj.Text, normalText), ...
    'greying an armed control stops it advertising an unreachable action');
release(kb, 'control', {});
hB.setEnabled(true);

fprintf('PASS: a control the operator cannot click never arms\n');


% 9. Inside a real gui.BehaviorGUI: injection and the session note ---------
PREF_TAG = 'modifierButtonGUITest';
cleanupPref = onCleanup(@() removePref(PREF_TAG));

rtG = makeRuntime();
G = ModifierButtonBehaviorGUI(rtG);
cleanupG = onCleanup(@() delete(G));

assert(~isempty(G.hReward), 'the button built');
assert(isequal(G.hReward.KeySource, G.Keys), ...
    'the spec injects the figure''s one KeyBindings');

press(G.Keys, 'control', {'control'});
assert(strcmp(G.hReward.h_uiobj.Text,'Large Reward'), 'and the chord arms through it');
G.hReward.value_changed(G.hReward.h_uiobj, struct('EventName','ButtonPushed','Value',true));
release(G.Keys, 'control', {});

assert(G.AltCount == 1, 'the alternate action ran inside the GUI');

recs = rtG.NOTES.Records;
assert(~isempty(recs), 'the press was recorded in the session notes');
assert(contains(recs(end).Text, 'Ctrl') && contains(recs(end).Text, 'Large Reward'), ...
    'and the note names the chord and what it did');

fprintf('PASS: the component is injected and its press reaches the session notes\n');


% 10. No host, no runtime, no figure: inert rather than broken -------------
figBare = uifigure('Visible','off');
cleanupBare = onCleanup(@() delete(figBare));
swBare = hw.Software;
pBare = swBare.add_parameter('!Bare', false, Type='Boolean', isTrigger=true);
swBare.mode = hw.DeviceState.Record;

% No KeySource handed in: the component joins the figure's shared instance.
hBare = gui.components.Parameter_Control(figBare, pBare, Type='momentary', ...
    autoCommit=true, ModifierActions={'ctrl', @(~,~,~) note('bare')});
kbBare = gui.KeyBindings.getOrCreate(figBare);
assert(isequal(hBare.KeySource, kbBare), ...
    'a standalone control joins the figure''s KeyBindings rather than claiming the slot');

fired = strings(1,0);
press(kbBare, 'control', {'control'});
hBare.value_changed(hBare.h_uiobj, struct('EventName','ButtonPushed','Value',true));
assert(isequal(fired, "bare"), 'and the action runs with no host at all');
release(kbBare, 'control', {});

fprintf('PASS: with no host the note is skipped and nothing throws\n');


fprintf('smoke_test_modifier_buttons: ALL PASS\n');


    function note(s)
        fired(end+1) = string(s);
    end

    function countRead()
        reads = reads + 1;
    end

    function countTrig()
        trigs = trigs + 1;
    end
end


function press(kb, key, mods)
kb.dispatchKeyPress(struct('Key', key, 'Modifier', {mods}, 'Character', ''));
end

function release(kb, key, mods)
kb.dispatchKeyRelease(struct('Key', key, 'Modifier', {mods}, 'Character', ''));
end

function assertThrows(fcn, id, msg)
try
    fcn();
catch ME
    assert(strcmp(ME.identifier, id), '%s (got %s)', msg, ME.identifier);
    return
end
error('%s (nothing was thrown)', msg);
end

function rt = makeRuntime()
% A software runtime carrying the trigger the fixture GUI puts a button on.
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;

sw = hw.Software;
p = sw.add_parameter('!Reward', false, Type='Boolean', isTrigger=true);
sw.add_parameter('!BigReward', false, Type='Boolean', isTrigger=true);
p.Value = false;
rt.Interfaces = sw;
end

function removePref(tag)
if ispref(tag)
    rmpref(tag);
end
end
