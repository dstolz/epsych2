function smoke_test_nanomotor_component()
% smoke_test_nanomotor_component()
% Exercise gui.components.NanoMotor -- the embeddable panel for the DM320T
% commutator controller -- with NO hardware attached.
%
% What it pins down, in the order the panel would meet it:
%   1. Construction opens no serial port and starts no poll timer. That is
%      the whole reason this component exists beside
%      peripherals.NanoMotorControlGUI, which connected from its constructor
%      and rethrew, so a switched-off commutator took the behavior GUI with it.
%   2. A failed connect reports in the panel instead of throwing out of a
%      button callback.
%   3. Every motion command is inert without a link -- no throw, no jog state.
%   4. Sections collapse their rows and tolerate a name that is not one.
%   5. Swapping the jog labels moves TEXT: each button keeps commanding the
%      motor direction it always did (the tags name that direction).
%   6. A pop-out (and the ButtonOnly form's window) shares the ONE controller
%      and never closes the link behind the panel it came from.
%   7. A reviewed session drives nothing.
%
%   matlab -batch "run('tmp/smoke_test_nanomotor_component.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

TAG = 'smokeNanoMotorComponent';
forgetPrefs(TAG);
nFail = 0;
cleanup = onCleanup(@() forgetPrefs(TAG));

fig = uifigure('Visible','off','Name','NanoMotor smoke','Position',[100 100 340 260]);
figCleanup = onCleanup(@() delete(fig));


% 1. Construction touches nothing ------------------------------------------
m = gui.components.NanoMotor([], fig, PreferenceTag = TAG);
nFail = nFail + check(isa(m.Motor,'peripherals.NanoMotorControl'), ...
    'a driver object is made at construction');
nFail = nFail + check(~m.IsConnected, 'construction does NOT open the serial port');
nFail = nFail + check(strcmp(m.Timer.Running,'off'), ...
    'the readout timer does not run while disconnected');
nFail = nFail + check(contains(m.Status,'Not connected'), ...
    'the panel says it is not connected');

% 2. Motion is inert without a link -----------------------------------------
m.jog('cw');
nFail = nFail + check(~m.IsJogging, 'jog does nothing without a link');
m.move();
m.zeroPosition();
m.stopMotion();
m.stopJog();
nFail = nFail + check(~m.IsConnected, 'none of the motion commands opened a port');

% 3. Settings ---------------------------------------------------------------
m.MoveAmount = 90;
m.MoveUnits  = 'rot';
nFail = nFail + check(abs(m.MoveAmount - 0.25) < 1e-12, ...
    'changing the units converts the amount (90 deg = 0.25 rot)');
m.MoveUnits = 'deg';
nFail = nFail + check(abs(m.MoveAmount - 90) < 1e-9, 'and converts it back');

m.SpeedRPM = 120;
nFail = nFail + check(m.SpeedRPM == 120 && ~m.IsConnected, ...
    'a speed change writes nothing while disconnected');

% 4. Swapped jog labels move text, never what is sent -------------------------
figSwap = uifigure('Visible','off','Name','NanoMotor swap');
swapCleanup = onCleanup(@() delete(figSwap));
sw = gui.components.NanoMotor([], figSwap, PreferenceTag = [TAG 'Swap'], ...
    SwapDirectionLabels = true);
nFail = nFail + check(strcmp(jogText(figSwap,'NanoMotorJogNeg'),'CW'), ...
    'a swap relabels the motor-CCW button CW');
nFail = nFail + check(strcmp(jogText(figSwap,'NanoMotorJogPos'),'CCW'), ...
    'and the motor-CW button CCW');
sw.SwapDirectionLabels = false;
nFail = nFail + check(strcmp(jogText(figSwap,'NanoMotorJogPos'),'CW'), ...
    'unswapped, the motor-CW button reads CW again');
delete(sw);

% 5. Sections ----------------------------------------------------------------
nFail = nFail + check(isequal(m.Sections, gui.components.NanoMotor.SECTIONS), ...
    'every section is shown by default');
m.hide("Move");
nFail = nFail + check(~m.isSectionVisible("Move"), 'hide drops a section');
nFail = nFail + check(rowHeight(fig,'Move') == 0, 'the hidden row collapses to zero height');
m.show("Move");
nFail = nFail + check(rowHeight(fig,'Move') > 0, 'showing it gives the height back');

m.Sections = "Readout";
nFail = nFail + check(isequal(m.Sections, ["Status","Position","Zero"]), ...
    'the Readout alias expands to its members');
nFail = nFail + check(strcmp(m.Timer.Running,'off'), ...
    'a readout section alone still starts no timer while disconnected');

m.Sections = ["Link","Bogus"];
nFail = nFail + check(isequal(m.Sections, "Link"), ...
    'an unknown section name is skipped, not thrown');
m.Sections = "All";

% 6. A failed connect stays inside the panel ---------------------------------
m.Port = 'COM_NOT_A_PORT';
nFail = nFail + check(strcmp(m.Port,'COM_NOT_A_PORT'), 'the port can be staged without connecting');
m.connect();
nFail = nFail + check(~m.IsConnected, 'connecting to a port that is not there fails quietly');
nFail = nFail + check(contains(m.Status,'Connect failed'), ...
    'and the failure is reported in the panel');
nFail = nFail + check(strcmp(m.Timer.Running,'off'), 'no polling after a failed connect');

% 7. Pop-out shares the one controller ---------------------------------------
p = m.popOut();
nFail = nFail + check(~isempty(p) && isvalid(p), 'the panel pops out');
nFail = nFail + check(p.Motor == m.Motor, 'the pop-out drives the SAME controller');
motor = m.Motor;
m.closePopOut();
nFail = nFail + check(isvalid(motor), 'closing the pop-out leaves the controller alone');

% 8. The ButtonOnly form ------------------------------------------------------
fig2 = uifigure('Visible','off','Name','NanoMotor button');
fig2Cleanup = onCleanup(@() delete(fig2));
b = gui.components.NanoMotor([], fig2, ButtonOnly = true, PreferenceTag = [TAG 'Btn']);
nFail = nFail + check(b.IsButtonOnly, 'ButtonOnly builds the button form');
nFail = nFail + check(~b.IsConnected, 'the button form connects nothing either');
bp = b.popOut();
nFail = nFail + check(~isempty(bp) && isvalid(bp) && ~bp.IsButtonOnly, ...
    'its button opens the full panel');
nFail = nFail + check(bp.Motor == b.Motor, 'over the same controller');
b.closePopOut();

% 9. A review drives nothing ---------------------------------------------------
rt = epsych.Runtime();
rt.ReviewMode = true;
fig3 = uifigure('Visible','off','Name','NanoMotor review');
fig3Cleanup = onCleanup(@() delete(fig3));
r = gui.components.NanoMotor(rt, fig3, PreferenceTag = [TAG 'Rev']);
nFail = nFail + check(contains(r.Status,'Review'), 'a reviewed session says so');
r.Port = 'COM_NOT_A_PORT';
r.connect();
nFail = nFail + check(~r.IsConnected, 'connect is refused in a review');
r.jog('ccw');
nFail = nFail + check(~r.IsJogging, 'so is jogging');

% 10. The component declaration and its glyph ------------------------------------
s = gui.ComponentSpec.forClass('gui.components.NanoMotor');
nFail = nFail + check(strcmp(s.className,'gui.components.NanoMotor'), 'the class resolves to a spec');
nFail = nFail + check(isequal(s.shape, ["runtime","parent"]), ...
    'gui.BehaviorGUI.add passes it the runtime and the container');
nFail = nFail + check(any(strcmp({s.options.name},'ButtonOnly')), ...
    'ButtonOnly is a declared option, so the builder offers it');
nFail = nFail + check(isequal(size(gui.toolbarIcon("nanomotor")), [16 16 3]), ...
    'the toolbar/button glyph is drawn');

delete(m);
delete(b);
delete(r);
delete(rt);

% -----------------------------------------------------------------------------
if nFail == 0
    fprintf('\nsmoke_test_nanomotor_component: PASS\n');
else
    error('smoke_test_nanomotor_component: %d check(s) FAILED', nFail);
end
end


function h = rowHeight(fig, rowName)
% Height the panel's root grid currently gives one named row. The row order
% mirrors gui.components.NanoMotor's private ROW_NAMES, which is layout, not
% API -- a test-only accessor on the class would be worse than repeating it.
names = {'Link','Status','Position','Jog','Move'};
i = find(strcmp(names, rowName), 1);
g = findobj(fig.Children, 'flat', 'Type', 'uigridlayout');
h = g(1).RowHeight{i};
end


function t = jogText(fig, tag)
% What one jog button says. The tags name the MOTOR direction each button
% commands, which is the point: a label swap must move the text and nothing else.
b = findobj(fig, 'Tag', tag);
t = b(1).Text;
end


function forgetPrefs(tag)
grp = 'epsych2_gui_NanoMotor';
names = {tag, [tag 'Btn'], [tag 'Rev'], [tag 'Swap'], [tag '_NanoMotor_PopOut'], ...
    [tag 'Btn_NanoMotor_PopOut']};
for k = 1:numel(names)
    try
        if ispref(grp, names{k}), rmpref(grp, names{k}); end
    catch
    end
end
end


function n = check(tf, what)
n = double(~tf);
if tf
    fprintf('  ok   %s\n', what);
else
    fprintf(2, '  FAIL %s\n', what);
end
end
