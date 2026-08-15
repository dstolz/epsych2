function smoke_test_parameter_reset()
% smoke_test_parameter_reset()
% Exercise the Ctrl-to-reset path added to gui.Parameter_Update: modifier
% key handling (Ctrl arms reset, Ctrl+Shift+Alt still arms immediate
% commit, release restores the default state), the button-pushed dispatch,
% and gui.Parameter_Control.reset_value restoring the pre-edit value
% without touching hw.Parameter. Also covers checkbox controls, which have
% no BackgroundColor and must indicate state through FontColor. Headless-
% safe: the figure is closed before returning.
%
%   matlab -batch "run('tmp/smoke_test_parameter_reset.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

fig = uifigure('Visible','off','Tag','smokeParamReset');
cleanupObj = onCleanup(@() delete(findall(groot,'Type','figure','-and','Tag','smokeParamReset')));

sw = hw.Software;
pFreq = sw.add_parameter('SmokeFreq', 1000, Unit='Hz'); pFreq.Value = 1000;
pLevel = sw.add_parameter('SmokeLevel', 60);            pLevel.Value = 60;
pDur = sw.add_parameter('SmokeDur', 50, Unit='ms'); pDur.Value = 50;
pRand = sw.add_parameter('SmokeRandom', false, Type='Boolean'); pRand.Value = false;

rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;
rt.Interfaces = sw;

g = uigridlayout(fig,[5 1]);
c(1) = gui.Parameter_Control(g, pFreq);
c(2) = gui.Parameter_Control(g, pLevel);
c(3) = gui.Parameter_Control(g, pDur);
c(4) = gui.Parameter_Control(g, pRand, Type='checkbox'); % no BackgroundColor

postCount = 0;
c(3).PostUpdateFcn = @(varargin) incr();

u = gui.Parameter_Update(rt, g);
u.watchedHandles = c;

assert(strcmp(u.Button.Enable,'off'), 'button should start disabled');
assert(u.Button.Text == "Nothing to Update", 'idle label wrong: %s', u.Button.Text);

% 1. Ctrl with nothing pending must not arm reset --------------------------
u.key_press([], modEvent({'control'}));
assert(u.Button.Text == "Nothing to Update", ...
    'Ctrl must not relabel a disabled button (got "%s")', u.Button.Text);
u.key_release([], modEvent({}));
fprintf('PASS: Ctrl is inert while nothing is pending\n');

% 2. Pending edits enable the button --------------------------------------
c(1).Value = 2000;
c(3).Value = 25;
c(4).Value = true; % checkbox: state must show up as FontColor, not a crash
assert(all([c([1 3 4]).ValueUpdated]), 'edits should mark controls pending');
assert(~c(2).ValueUpdated, 'untouched control should stay clean');
assert(strcmp(u.Button.Enable,'on') && u.Button.Text == "Update Parameters", ...
    'pending edits should enable the button (got "%s")', u.Button.Text);
assert(pFreq.Value == 1000 && pDur.Value == 50 && pRand.Value == false, ...
    'pending edits must not reach hw.Parameter before commit');
assert(isequal(c(4).h_uiobj.FontColor, validatecolor(c(4).colorOnUpdate)), ...
    'checkbox should indicate a pending edit through FontColor');
fprintf('PASS: pending edits enable the update button\n');

% 3. Ctrl relabels/recolors, release restores ------------------------------
defaultColor = u.Button.BackgroundColor;
u.key_press([], modEvent({'control'}));
assert(u.Button.Text == "Reset Parameters", ...
    'Ctrl should relabel to Reset Parameters (got "%s")', u.Button.Text);
assert(~isequal(u.Button.BackgroundColor, defaultColor), ...
    'Ctrl should change the button background color');

u.key_release([], modEvent({}));
assert(u.Button.Text == "Update Parameters", ...
    'releasing Ctrl should restore the default label (got "%s")', u.Button.Text);
assert(isequal(u.Button.BackgroundColor, defaultColor), ...
    'releasing Ctrl should restore the default background color');
fprintf('PASS: Ctrl press/release toggles the reset affordance\n');

% 4. Ctrl+Shift+Alt still wins over plain Ctrl -----------------------------
u.key_press([], modEvent({'control','shift','alt'}));
assert(u.Button.Text == "Update Parameters Immediately", ...
    'full chord should still arm immediate commit (got "%s")', u.Button.Text);
u.key_release([], modEvent({'control'}));
assert(u.Button.Text == "Reset Parameters", ...
    'dropping to Ctrl alone should arm reset (got "%s")', u.Button.Text);
fprintf('PASS: Ctrl+Shift+Alt takes priority over plain Ctrl\n');

% 5. Clicking while armed resets to the previous values --------------------
postBefore = postCount;
u.button_pushed([],[]);
assert(c(1).Value == 1000, 'edit field should revert to the parameter value (got %g)', c(1).Value);
assert(c(3).Value == 50, 'second edit field should revert too (got %g)', c(3).Value);
assert(c(4).Value == false, 'checkbox should revert to the parameter value');
assert(~any([c.ValueUpdated]), 'no control should remain pending after reset');
assert(pFreq.Value == 1000 && pDur.Value == 50 && pRand.Value == false, ...
    'reset must not write hw.Parameter');
assert(isequal(c(4).h_uiobj.FontColor, validatecolor(c(4).colorNormal)), ...
    'checkbox FontColor should return to normal after reset');
assert(strcmp(u.Button.Enable,'off') && u.Button.Text == "Nothing to Update", ...
    'button should return to the idle state after reset (got "%s")', u.Button.Text);
assert(~isequal(c(1).h_uiobj.BackgroundColor, validatecolor(c(1).colorOnUpdate)), ...
    'reset should clear the pending-edit highlight');
assert(postCount > postBefore, 'PostUpdateFcn should run for the restored value');
fprintf('PASS: reset restores previous values and clears pending state\n');

% 6. Without Ctrl the click still routes to commit_changes -----------------
% This runtime has no TRIALS (that needs a full session start), so the
% commit path is expected to fail on RUNTIME.TRIALS.trials. What matters
% here is which branch button_pushed took: the edit must survive.
c(2).Value = 75;
assert(strcmp(u.Button.Enable,'on'), 'button should re-enable after a new edit');
committed = false;
try
    u.button_pushed([],[]);
    committed = true;
catch
end
assert(c(2).Value == 75 && (committed || c(2).ValueUpdated), ...
    'an unmodified click must commit, not reset');
fprintf('PASS: unmodified click still routes to commit_changes\n');

close(fig);
fprintf('smoke_test_parameter_reset: ALL PASS\n');

    function n = incr()
        postCount = postCount + 1;
        n = postCount;
    end
end


function e = modEvent(mods)
% Stand-in for a WindowKeyPress/Release event carrying only Modifier.
e = struct('Modifier', {mods});
end
