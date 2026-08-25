function smoke_test_keybindings()
% smoke_test_keybindings()
% Exercise gui.KeyBindings: chord normalization, dispatch, duplicate and
% review policy, modifier tracking, owner pruning, and the figure-callback
% ownership that is the whole point of the class -- a binding made before
% gui.Parameter_Update is constructed must still fire afterwards.
%
% Uses invisible uifigures; no hardware.
%
%   matlab -batch "run('tmp/smoke_test_keybindings.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

fig = uifigure('Visible','off');
cleanupFig = onCleanup(@() delete(fig));


% 1. Chord normalization --------------------------------------------------
n = @gui.KeyBindings.normalize;

assert(strcmp(n('r'), 'r'), 'a bare key is its own chord');
assert(strcmp(n('Ctrl+R'), 'control+r'), 'case is not part of a chord');
assert(isequal(n('shift+ctrl+r'), n('Ctrl+Shift+R')), 'modifier order must not matter');
assert(strcmp(n('ctrl+alt+shift+t'), 'control+alt+shift+t'), 'canonical order is ctrl, alt, shift');
assert(isequal(n('command+s'), n('ctrl+s')), 'command is the mac spelling of ctrl');
assert(isequal(n('option+s'), n('alt+s')), 'option is the mac spelling of alt');
assert(isequal(n('ctrl+shift+?'), n('ctrl+shift+slash')), '? and slash are the same key');
assert(isequal(n('ctrl+enter'), n('ctrl+return')), 'enter is the return key');
assert(isequal(n('numpad3'), n('3')), 'the numpad digits answer as digits');

assertThrows(@() n('ctrl+shift'), 'epsych:KeyBindings:modifiersOnly', ...
    'a chord of modifiers alone is refused');
assertThrows(@() n('ctrl+a+b'), 'epsych:KeyBindings:badChord', ...
    'a chord naming two keys is refused');
assertThrows(@() n(''), 'epsych:KeyBindings:emptyChord', ...
    'an empty chord is refused');
assertThrows(@() n('  +  '), 'epsych:KeyBindings:emptyChord', ...
    'a chord of separators alone is refused');

assert(strcmp(gui.KeyBindings.displayChord('ctrl+shift+slash'), 'Ctrl+Shift+/'), ...
    'the help list spells a chord the way an operator reads it');
assert(strcmp(gui.KeyBindings.displayChord('leftarrow'), 'Left Arrow'), ...
    'named keys read as words');

fprintf('PASS: chords normalize to one canonical form\n');


% 2. Binding and dispatch -------------------------------------------------
kb = gui.KeyBindings(fig);

hits = strings(1,0);
kb.bind('ctrl+r', @() addHit('ctrl+r'), Description='Refresh');
kb.bind('leftarrow', @() addHit('left'), Description='Respond LEFT');

assert(kb.isBound('Ctrl+R'), 'isBound reads a chord the same way bind does');
assert(~kb.isBound('ctrl+q'), 'an unbound chord is not bound');

press(kb, 'r', {'control'});
assert(isequal(hits, "ctrl+r"), 'a bound chord fires its callback');

press(kb, 'leftarrow', {});
assert(isequal(hits, ["ctrl+r" "left"]), 'an unmodified key is a chord too');

press(kb, 'r', {});                 % the same key without the modifier
press(kb, 'q', {'control'});        % a chord nothing bound
assert(numel(hits) == 2, 'an unbound chord must not fire anything');

% A chord is the WHOLE modifier set, not a subset: Ctrl+Shift+R is a
% different command from Ctrl+R and must not fire it.
press(kb, 'r', {'control','shift'});
assert(numel(hits) == 2, 'extra modifiers make a different chord');

kb.unbind('CTRL+R');
press(kb, 'r', {'control'});
assert(numel(hits) == 2, 'an unbound chord stops firing');

fprintf('PASS: chords dispatch, and only the exact chord dispatches\n');


% 3. A duplicate chord is an error, not a silent loss ----------------------
kb.bind('ctrl+d', @() addHit('first'));
assertThrows(@() kb.bind('ctrl+d', @() addHit('second')), ...
    'epsych:KeyBindings:duplicateChord', 'a duplicate chord is refused');

hits = strings(1,0);
press(kb, 'd', {'control'});
assert(isequal(hits, "first"), 'the refused bind changed nothing');

kb.bind('ctrl+d', @() addHit('second'), Replace=true);
hits = strings(1,0);
press(kb, 'd', {'control'});
assert(isequal(hits, "second"), 'Replace=true overrides deliberately');

fprintf('PASS: a duplicate chord errors unless Replace is asked for\n');


% 4. Modifier state -------------------------------------------------------
% This is what gui.Parameter_Update and gui.RegenerateTrial read instead of
% installing hooks of their own.
changes = 0;
hl = listener(kb, 'ModifiersChanged', @(~,~) countChange());
cleanupL = onCleanup(@() delete(hl));

press(kb, 'shift', {'shift'});
assert(isequal(kb.CurrentModifiers, {'shift'}), 'a held modifier is tracked');
assert(changes == 1, 'the change is announced once');

press(kb, 'control', {'shift','control'});
assert(kb.modifiersDown({'control','shift'}), 'modifiersDown reads the held set');
assert(~kb.modifiersDown({'control','alt'}), 'a modifier that is not held reads false');

n0 = changes;
press(kb, 'control', {'shift','control'});   % same set again
assert(changes == n0, 'an unchanged modifier set announces nothing');

release(kb, 'control', {'shift'});
assert(isequal(kb.CurrentModifiers, {'shift'}), 'a release reports what is still held');
release(kb, 'shift', {});
assert(isempty(kb.CurrentModifiers), 'letting go of everything clears the set');

% A bare modifier press must never be looked up as a chord of its own.
hits = strings(1,0);
kb.bind('ctrl+alt+shift+u', @() addHit('armed'));
press(kb, 'control', {'control','alt','shift'});
assert(isempty(hits), 'a modifier keypress is state, not a chord');
press(kb, 'u', {'control','alt','shift'});
assert(isequal(hits, "armed"), 'the chord itself still fires');

fprintf('PASS: modifier state tracks press and release without firing chords\n');


% 5. Review mode ----------------------------------------------------------
% A review replays a finished session; a binding that would write to the
% hardware must not fire, even if its component forgot to check.
inReview = true;   % read live through a nested function: an anonymous
                   % handle would capture the value at creation.
kb.ReviewModeFcn = @() isReviewing();

hits = strings(1,0);
kb.bind('ctrl+w', @() addHit('write'));
kb.bind('ctrl+e', @() addHit('read'), EnableInReview=true);

press(kb, 'w', {'control'});
assert(isempty(hits), 'a binding is suppressed in a review');
press(kb, 'e', {'control'});
assert(isequal(hits, "read"), 'EnableInReview opts a binding back in');

inReview = false;
press(kb, 'w', {'control'});
assert(isequal(hits, ["read" "write"]), 'outside a review it fires normally');

kb.ReviewModeFcn = [];

fprintf('PASS: bindings are suppressed in a review unless they opt in\n');


% 6. A dead owner takes its binding with it -------------------------------
owner = uibutton(fig);
hits = strings(1,0);
kb.bind('ctrl+k', @() addHit('owned'), Owner=owner, Description='Owned command');

press(kb, 'k', {'control'});
assert(isequal(hits, "owned"), 'an owned binding fires while its owner lives');

delete(owner);
press(kb, 'k', {'control'});
assert(isequal(hits, "owned"), 'a deleted owner does not answer its chord');
assert(~kb.isBound('ctrl+k'), 'the dead binding is dropped rather than kept');

fprintf('PASS: a binding dies with the component that owns it\n');


% 7. A throwing callback does not break the next keystroke ----------------
kb.bind('ctrl+x', @() error('deliberate:failure','boom'));
hits = strings(1,0);
press(kb, 'x', {'control'});            % must not propagate
press(kb, 'd', {'control'});
assert(isequal(hits, "second"), 'a throwing binding leaves the rest working');

fprintf('PASS: a throwing binding is logged, not propagated\n');


% 8. The help list --------------------------------------------------------
L = kb.list();
assert(~isempty(L), 'the help list is not empty');
assert(strcmp(L(1).Chord, 'leftarrow'), 'bindings list in the order they were bound');
assert(any(strcmp({L.Description}, 'Respond LEFT')), 'descriptions come through');
grp = {L.Group};
assert(all(strcmp(grp, 'General')), 'a binding with no owner lands in General');

% A binding whose owner names it groups under the component's name.
b2 = uibutton(fig);
kb.bind('ctrl+shift+b', @() addHit('b'), Owner=b2, Description='Something');
L2 = kb.list();
assert(any(strcmp({L2.Group}, 'Button')), 'an owner groups the binding by its class');
assert(any(strcmp({L2.Display}, 'Ctrl+Shift+B')), 'the list carries the display chord');

% A camelCase owner class is split into words. This is the regression the
% group heading had: the zero-width lookaround spacedClassName_ used to use
% MATCHES but inserts nothing in MATLAB, so a two-word class read as one
% ('SCREENCAPTURE' in the help window). 'Button' above cannot catch it --
% it is a single word either way.
b3 = uibutton(fig, 'state');   % matlab.ui.control.StateButton
kb.bind('ctrl+shift+t', @() addHit('t'), Owner=b3, Description='Toggle something');
L3 = kb.list();
assert(any(strcmp({L3.Group}, 'State Button')), ...
    'a camelCase owner class name is split into words');

fprintf('PASS: the help list is ordered, grouped and readable\n');


% 9. Figure ownership, which is the bug this class exists to fix -----------
% gui.Parameter_Update used to claim WindowKeyPressFcn outright at
% construction; today it joins the figure's shared KeyBindings instead. A
% GUI that binds a key BEFORE the update button is created must still have
% that key working afterwards.
delete(kb);
fig2 = uifigure('Visible','off');
cleanupFig2 = onCleanup(@() delete(fig2));

kb2 = gui.KeyBindings(fig2);
hits = strings(1,0);
kb2.bind('leftarrow', @() addHit('left'), Description='Respond LEFT');

rt = makeRuntime();
g = uigridlayout(fig2, [1 1]);
pu = gui.Parameter_Update(rt, g);       % joins kb2 through the figure
cleanupPU = onCleanup(@() delete(pu));

kb2.claimFigure();                      % what gui.BehaviorGUI does after build

press(kb2, 'leftarrow', {});
assert(isequal(hits, "left"), ...
    'a binding must survive a component that claims the figure callback');

% ...and the clobbering component keeps working, because it is chained.
foreign = 0;
fig2.WindowKeyPressFcn = @(~,~) countForeign();
kb2.claimFigure();
press(kb2, 'z', {});                    % nothing bound: falls through
assert(foreign == 1, 'an unbound key reaches the handler that was found');
press(kb2, 'leftarrow', {});
assert(foreign == 1, 'a bound key is answered here, not passed on');
assert(numel(hits) == 2, 'the binding still fires');

% A foreign handler that throws -- Parameter_Update's does, until its
% watchedHandles are wired at the end of build -- must not take the
% dispatcher down with it.
fig2.WindowKeyPressFcn = @(~,~) error('neighbour:boom','boom');
kb2.claimFigure();
press(kb2, 'q', {});                    % unbound: chains into the thrower
press(kb2, 'leftarrow', {});
assert(numel(hits) == 3, 'a throwing neighbour leaves the bindings working');

fprintf('PASS: bindings and a foreign key handler coexist on one figure\n');


% 10. Teardown ------------------------------------------------------------
fig3 = uifigure('Visible','off');
cleanupFig3 = onCleanup(@() delete(fig3));
marker = @(~,~) disp('original');
fig3.WindowKeyPressFcn = marker;

kb3 = gui.KeyBindings(fig3);
assert(~isequal(fig3.WindowKeyPressFcn, marker), 'the object takes the slot');
delete(kb3);
assert(isequal(fig3.WindowKeyPressFcn, marker), 'teardown puts back what it found');

% Deleting out of order must not step on a neighbour that claimed the slot
% afterwards.
kb4 = gui.KeyBindings(fig3);
later = @(~,~) disp('later');
fig3.WindowKeyPressFcn = later;
delete(kb4);
assert(isequal(fig3.WindowKeyPressFcn, later), ...
    'teardown leaves a slot alone once someone else has claimed it');

fprintf('PASS: teardown restores the figure without stepping on neighbours\n');


% 11. Inside a real gui.BehaviorGUI ---------------------------------------
% The regression this class exists for: a subclass binds a key in build,
% and addUpdateButton runs afterwards. Before gui.KeyBindings the binding
% was silently dead from that point on.
addpath(here);                          % KeyBindingsBehaviorGUI lives beside this test
PREF_TAG = 'keyBindingsGUITest';
cleanupPref = onCleanup(@() removePref(PREF_TAG));

rtG = makeRuntime();
G = KeyBindingsBehaviorGUI(rtG);
cleanupG = onCleanup(@() delete(G));

assert(~isempty(G.Keys) && isvalid(G.Keys), 'the GUI owns a gui.KeyBindings');
assert(~isempty(G.h_figure.WindowKeyPressFcn), ...
    'the key processor holds the figure callback after build');

press(G.Keys, 'leftarrow', {});
assert(G.ArrowCount == 1, ...
    'a key bound before addUpdateButton must still fire after it');

% The helpers' own default chords are bound and described.
bound = {G.Keys.list().Chord};
assert(ismember('control+return', bound), 'addUpdateButton binds Ctrl+Enter');
assert(ismember('control+shift+c', bound), 'addScreenCapture binds Ctrl+Shift+C');
assert(ismember('control+shift+slash', bound), 'the base binds the help chord');
assert(~ismember('control+shift+r', bound), ...
    'addRegenerateTrial deliberately binds no chord');

% Ctrl+Enter with nothing pending must be inert rather than committing.
press(G.Keys, 'return', {'control'});
assert(~any([G.hUpdate.watchedHandles.ValueUpdated]), ...
    'committing with nothing pending changes nothing');

% Modifier state reaches the components that used to install hooks: three
% modifiers held is what arms the regenerate button.
assert(strcmp(G.hRegen.ButtonH.Enable,'off'), 'the button starts disabled');
setMode(rtG, hw.DeviceState.Record);
press(G.Keys, 'control', {'control','alt','shift'});
assert(G.hRegen.Armed, 'the three modifiers arm the button through KeyBindings');
release(G.Keys, 'alt', {'control','shift'});
assert(~G.hRegen.Armed, 'letting one go disarms it');

fprintf('PASS: a behavior GUI keeps every binding whatever order build uses\n');


% 12. Teardown of a whole GUI ---------------------------------------------
figH = G.h_figure;
keysH = G.Keys;
delete(G);
assert(~isvalid(keysH), 'the GUI deletes its key processor');
assert(~isvalid(figH), 'and its figure');

fprintf('PASS: closing the GUI takes its bindings with it\n');


fprintf('smoke_test_keybindings: ALL PASS\n');


    function addHit(s)
        hits(end+1) = string(s);
    end

    function countChange()
        changes = changes + 1;
    end

    function countForeign()
        foreign = foreign + 1;
    end

    function tf = isReviewing()
        tf = inReview;
    end
end


function press(kb, key, mods)
% Drive the installed press callback with a synthesized key event.
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
% A software runtime carrying the one parameter the fixture GUI controls.
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;

sw = hw.Software;
p = sw.add_parameter('SmokeFreq', 1000, Unit='Hz');
p.Value = 1000;
rt.Interfaces = sw;
end

function setMode(rt, mode)
% Broadcast a ModeChange the way epsych.RunExpt.PsychTimerStart does.
rt.EVENTS.notify('ModeChange', epsych.eventModeChange(mode));
end

function removePref(tag)
if ispref(tag)
    rmpref(tag);
end
end
