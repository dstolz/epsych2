function smoke_test_monitor_restore()
% smoke_test_monitor_restore()
% Exercise gui.fitPositionToMonitor and the saved-position path it sits on:
% a window reopens on the monitor it was last on, a rectangle that already
% fits is restored exactly, and an oversize or off-edge one is brought back
% without changing screens.
%
% The regression it guards is a behavior GUI dragged onto a secondary
% monitor reopening on the primary one. movegui(fig,'onscreen') -- what the
% restore path used to end with -- picks its reference monitor from the
% FIRST corner of the window it finds inside one, so a window left hanging
% off an edge is attributed to a neighbour and clamped onto it.
%
% The arrangement-dependent checks pass synthetic monitor layouts, so this
% passes on a single-screen machine and covers arrangements nobody here has
% plugged in; the checks that need real monitors skip themselves when there
% is only one.
%
% No hardware.
%
%   matlab -batch "run('tmp/smoke_test_monitor_restore.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

mons = monitors();
fprintf('\n=== smoke_test_monitor_restore ===\n');
fprintf('%d monitor(s) attached\n', size(mons,1));


% 1. A rectangle that already fits is returned untouched --------------------
% Without this an unchanged monitor layout would nudge every window a little
% further each session.
for k = 1:size(mons,1)
    p = [mons(k,1)+120, mons(k,2)+90, 800, 600];
    assert(isequal(gui.fitPositionToMonitor(p), p), ...
        'a window already fitting monitor %d was moved', k);
end
fprintf('PASS: 1 a fitting rectangle is restored exactly on every monitor\n');


% 2. A window hanging off its monitor stays on that monitor -----------------
% This is the failure the operator saw, against the real displays. Each
% secondary monitor is tested with a window pushed past its bottom-left
% corner -- what happens when a tall window is dragged down on a screen that
% cannot hold it.
if size(mons,1) < 2
    fprintf('SKIP: 2 needs a second monitor\n');
else
    for k = 2:size(mons,1)
        p = [mons(k,1)-40, mons(k,2)-130, 1400, 1000];
        got = gui.fitPositionToMonitor(p);
        assert(monitorOf(got, mons) == monitorOf(p, mons), ...
            'a window mostly on monitor %d was moved to another screen', k);
        assert(fitsIn(got, mons(monitorOf(got,mons),:)), ...
            'the fitted rectangle still hangs off monitor %d', k);
    end
    fprintf('PASS: 2 an off-edge window is pulled back onto its own monitor\n');
end


% 3. The monitor is chosen by overlap area, at any origin -------------------
% A window 90% on the right-hand screen and 10% on the primary belongs to
% the right-hand screen, however its corners fall.
lay = [1 1 1920 1080; 1921 1 1920 1080];
got = gui.fitPositionToMonitor([1780 -129 1400 1000], lay);
assert(monitorOf(got, lay) == 2, 'overlap area did not pick the right screen');
assert(fitsIn(got, lay(2,:)), 'not brought fully onto the second screen');

% A monitor below or left of the primary has negative coordinates; nothing
% in the arithmetic may assume the origin is a corner of the desktop.
lay = [1 1 1920 1080; -1920 -300 1280 1024];
got = gui.fitPositionToMonitor([-1900 -400 1000 900], lay);
assert(monitorOf(got, lay) == 2, 'a negative-origin monitor was not recognised');
assert(fitsIn(got, lay(2,:)), 'not brought fully onto the negative-origin screen');
fprintf('PASS: 3 the monitor is chosen by overlap area, at any origin\n');


% 4. A window bigger than its monitor is shrunk, not lost -------------------
% Its size is worth less than being reachable.
lay = [1 1 1920 1080];
got = gui.fitPositionToMonitor([1 1 4000 3000], lay);
assert(got(3) <= lay(3) && got(4) <= lay(4), 'an oversize window was not shrunk');
assert(fitsIn(got, lay), 'the shrunk window still does not fit');
fprintf('PASS: 4 an oversize window is shrunk onto its monitor\n');


% 5. The title bar stays grabbable ------------------------------------------
% Clamping a window flush to the top of a screen would put its title bar
% above the screen, where it cannot be dragged back.
lay = [1 1 1920 1080];
got = gui.fitPositionToMonitor([100 900 800 600], lay);   % top would land at 1500
assert(got(2)+got(4) <= lay(2)+lay(4)-30, 'no room left for the title bar');
fprintf('PASS: 5 a clamped window keeps room for its title bar\n');


% 6. A monitor that is gone falls back to the primary -----------------------
lay = [1 1 1920 1080];
got = gui.fitPositionToMonitor([3000 200 800 600], lay);
assert(fitsIn(got, lay), 'a window from a vanished monitor is off-screen');
fprintf('PASS: 6 a window from a vanished monitor lands on the primary\n');


% 7. No monitors at all leaves the rectangle alone --------------------------
% Headless: clamping into a placeholder screen would be worse than nothing.
p = [1780 -129 1400 1000];
assert(isequal(gui.fitPositionToMonitor(p, zeros(0,4)), p), ...
    'an unreadable monitor list should leave the position alone');
fprintf('PASS: 7 an unreadable monitor list is a no-op\n');


% 8. The pref path applies the fit ------------------------------------------
% getSavedFigurePosition is where every restoring window goes through, which
% is why the fit lives there rather than at each caller.
TAG = 'zz_smoke_monitor_restore';
cleanupPref = onCleanup(@() localRmPref(TAG));
localRmPref(TAG);

stored = [mons(end,1)-40, mons(end,2)-130, 1400, 1000];
setpref(TAG, 'FigurePosition', stored);
got = gui.BehaviorGUI.getSavedFigurePosition(TAG, [100 100 800 600]);
assert(isequal(got, gui.fitPositionToMonitor(stored)), ...
    'getSavedFigurePosition did not fit the stored rectangle');
assert(fitsIn(got, mons(monitorOf(got,mons),:)), ...
    'the restored rectangle is not fully on a monitor');

% An unreadable stored value falls back to the default, fitted the same way.
setpref(TAG, 'FigurePosition', 'nonsense');
got = gui.BehaviorGUI.getSavedFigurePosition(TAG, [100 100 800 600]);
assert(isequal(got, gui.fitPositionToMonitor([100 100 800 600])), ...
    'an unreadable pref did not fall back to the fitted default');
fprintf('PASS: 8 the saved-position path fits what it returns\n');


% 9. A behavior GUI records its position however it is torn down ------------
% closeGUI has always saved it; a script that calls delete(obj) used to
% leave whatever was last written, which is another way to reopen on the
% wrong screen. The rig's own ep_GenericGUI preference is put back at the
% end -- this test must not move the operator's window.
cleanupGenericPref = onCleanup(@() localRestorePref('ep_GenericGUI'));
localStashPref('ep_GenericGUI');

g = ep_GenericGUI(epsych.Runtime);
cleanupGui = onCleanup(@() localDelete(g));

moved = gui.fitPositionToMonitor([mons(end,1)+150, mons(end,2)+120, 1100, 680]);
g.h_figure.Position = moved;
drawnow
delete(g);                                   % NOT via CloseRequestFcn
clear cleanupGui

saved = getpref('ep_GenericGUI', 'FigurePosition');
assert(isequal(saved, moved), ...
    'delete(obj) did not record where the window was left');
fprintf('PASS: 9 a programmatic teardown still records the position\n');

fprintf('=== smoke_test_monitor_restore: ALL PASS ===\n\n');
end


% -------------------------------------------------------------------------
function m = monitors()
% The real monitor rectangles, or a single synthetic screen when headless.
old = get(0,'Units');
c = onCleanup(@() set(0,'Units',old));
set(0,'Units','pixels');
m = double(get(0,'MonitorPositions'));
m = m(m(:,3) > 1 & m(:,4) > 1, :);
if isempty(m), m = [1 1 1920 1080]; end
end

function k = monitorOf(p, mons)
% The monitor a rectangle mostly occupies -- the same rule under test, used
% here only to name a screen in an assertion.
a = zeros(size(mons,1),1);
for i = 1:numel(a)
    w = min(p(1)+p(3), mons(i,1)+mons(i,3)) - max(p(1), mons(i,1));
    h = min(p(2)+p(4), mons(i,2)+mons(i,4)) - max(p(2), mons(i,2));
    a(i) = max(w,0) * max(h,0);
end
[~,k] = max(a);
end

function tf = fitsIn(p, mon)
tf = p(1) >= mon(1) && p(1)+p(3) <= mon(1)+mon(3) ...
    && p(2) >= mon(2) && p(2)+p(4) <= mon(2)+mon(4);
end

function localRmPref(tag)
if ispref(tag), rmpref(tag); end
end

function localStashPref(tag)
% Park the operator's real preference group in appdata for the duration.
if ispref(tag)
    setappdata(groot, ['zzStash_' tag], getpref(tag));
    rmpref(tag);
else
    setappdata(groot, ['zzStash_' tag], []);
end
end

function localRestorePref(tag)
key = ['zzStash_' tag];
if ~isappdata(groot, key), return; end
saved = getappdata(groot, key);
rmappdata(groot, key);
localRmPref(tag);
if isstruct(saved)
    fn = fieldnames(saved);
    for i = 1:numel(fn)
        setpref(tag, fn{i}, saved.(fn{i}));
    end
end
end

function localDelete(obj)
if isobject(obj) && isvalid(obj), delete(obj); end
end
