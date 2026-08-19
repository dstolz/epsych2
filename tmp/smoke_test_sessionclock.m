function smoke_test_sessionclock()
% smoke_test_sessionclock()
% Exercise gui.SessionClock: UI construction (4 labels, no-clip row
% layout), context menu creation and checked-state sync, programmatic
% visibility control, right-click toggle simulation, font-size control
% (programmatic, menu presets, clamping), per-PreferenceTag
% persistence across instances (remembers user choices "per BehaviorGUI"),
% NewTrial/StartTime timing sources, and teardown. Headless-safe: every
% figure is closed and every test preference removed before returning.
%
%   matlab -batch "run('tmp/smoke_test_sessionclock.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

PREF_TAG_A = 'smokeSessionClockTestA';
PREF_TAG_B = 'smokeSessionClockTestB';
cleanupObj = onCleanup(@() cleanupAll({PREF_TAG_A, PREF_TAG_B}));

% 1. Construction: 4 labels, all shown, no-clip row config ----------------
figA = uifigure('Tag', PREF_TAG_A, 'Visible', 'off');
c1 = gui.SessionClock(figA, 'PreferenceTag', PREF_TAG_A);
lineKeys = {'LastTrial','FirstTrial','SessionDuration','ClockTime'};
for i = 1:numel(lineKeys)
    assert(isfield(c1.LabelH, lineKeys{i}) && isvalid(c1.LabelH.(lineKeys{i})), ...
        'label "%s" should exist', lineKeys{i});
    assert(strcmp(c1.LabelH.(lineKeys{i}).WordWrap, 'on'), ...
        'label "%s" should word-wrap instead of clipping', lineKeys{i});
    assert(c1.LabelH.(lineKeys{i}).Visible == "on", 'line "%s" should be shown by default', lineKeys{i});
end
assert(isequal(c1.GridH.RowHeight, repmat({'fit'},1,4)), 'all rows should be fit-height when shown');
fprintf('PASS: construction, 4 word-wrapped labels, fit-height rows\n');

% 2. Context menu: one checked item per line -------------------------------
assert(~isempty(c1.ContextMenuH) && isvalid(c1.ContextMenuH), 'context menu should be created');
allItems = findall(c1.ContextMenuH, 'Type', 'uimenu');
items = allItems(startsWith(string({allItems.Tag}), 'line|'));
assert(numel(items) == 4, 'context menu should have 4 line toggle items (got %d)', numel(items));
assert(all([items.Checked]), 'all lines should start checked');
assert(any(strcmp({allItems.Tag}, 'fontmenu')), 'context menu should offer a Font Size submenu');
assert(isequal(c1.PanelH.ContextMenu, c1.ContextMenuH), 'panel should carry the context menu');
assert(isequal(c1.LabelH.ClockTime.ContextMenu, c1.ContextMenuH), 'labels should carry the context menu too');
fprintf('PASS: context menu built with 4 checked toggle items\n');

% 3. Programmatic control ---------------------------------------------------
c1.ShowClockTime = false;
c1.refresh();
assert(c1.LabelH.ClockTime.Visible == "off", 'ClockTime label should hide after programmatic set + refresh');
assert(isequal(c1.GridH.RowHeight{4}, 0), 'hidden row should collapse to zero height, not clip');
idx = strcmp({items.Tag}, 'line|ClockTime');
assert(~items(idx).Checked, 'menu checkmark should follow programmatic changes');
c1.ShowClockTime = true;
c1.refresh();
fprintf('PASS: programmatic Show* + refresh() control the display\n');

% 4. Right-click toggle simulation + persistence ---------------------------
idx = strcmp({items.Tag}, 'line|SessionDuration');
items(idx).MenuSelectedFcn([], []); % simulate the user right-clicking this item
assert(~c1.ShowSessionDuration, 'menu toggle should flip the property');
assert(c1.LabelH.SessionDuration.Visible == "off", 'menu toggle should hide the row immediately');
assert(~items(idx).Checked, 'menu toggle should update its own checkmark');
assert(ispref(PREF_TAG_A, 'SessionClockVisibleLines'), 'toggle should persist a preference');
s = getpref(PREF_TAG_A, 'SessionClockVisibleLines');
assert(isfield(s,'ShowSessionDuration') && ~s.ShowSessionDuration, 'persisted value should reflect the toggle');
fprintf('PASS: right-click toggle applies immediately and persists\n');

% 5. A fresh instance on the same PreferenceTag remembers the choice ------
figA2 = uifigure('Tag', [PREF_TAG_A '_2'], 'Visible', 'off');
c1b = gui.SessionClock(figA2, 'PreferenceTag', PREF_TAG_A);
assert(~c1b.ShowSessionDuration, 'a new instance on the same PreferenceTag should load the saved choice');
assert(c1b.ShowClockTime, 'lines never toggled should keep their default');
delete(c1b);
close(figA2);
fprintf('PASS: line visibility remembered across instances per PreferenceTag\n');

% 5b. Font size: programmatic, menu, clamping, persistence ----------------
assert(c1.FontSize == 12, 'default font size should be 12 pt (got %g)', c1.FontSize);
c1.FontSize = 22;
assert(c1.FontSize == 22, 'FontSize should take a programmatic set');
for i = 1:numel(lineKeys)
    assert(c1.LabelH.(lineKeys{i}).FontSize == 22, ...
        'label "%s" should follow FontSize immediately, without a refresh', lineKeys{i});
end
c1.FontSize = 1000;
assert(c1.FontSize == 72, 'oversized fonts should clamp to 72 pt (got %g)', c1.FontSize);
c1.setFontSize(14.4);
assert(c1.FontSize == 14, 'a fractional size should round to whole points (got %g)', c1.FontSize);

fontMenu = findall(c1.ContextMenuH, 'Type', 'uimenu', 'Tag', 'fontmenu');
c1.ContextMenuH.ContextMenuOpeningFcn([], []); % simulate the operator right-clicking
presetItems = fontMenu.Children;
checked = presetItems(logical([presetItems.Checked]));
assert(isscalar(checked) && strcmp(checked.Text, '14 pt'), ...
    'the font menu should check the size in effect');
larger = presetItems(strcmp({presetItems.Text}, 'Larger'));
larger.MenuSelectedFcn([], []);
assert(c1.FontSize == 16, 'the Larger entry should step up 2 pt (got %g)', c1.FontSize);

assert(ispref(PREF_TAG_A, 'SessionClockFontSize'), 'a font change should persist a preference');
figA3 = uifigure('Tag', [PREF_TAG_A '_3'], 'Visible', 'off');
c1c = gui.SessionClock(figA3, 'PreferenceTag', PREF_TAG_A, 'FontSize', 9);
assert(c1c.FontSize == 16, ...
    'a saved font size should override the constructor default (got %g)', c1c.FontSize);
assert(c1c.LabelH.ClockTime.FontSize == 16, 'restored size should reach the labels');
delete(c1c);
close(figA3);
c1.setFontSize(12); % back to the default for the remaining sections
fprintf('PASS: font size settable programmatically and from the menu, clamped and remembered\n');

% 6. PreferenceTag defaults to the ancestor figure's Tag -------------------
figB = uifigure('Tag', PREF_TAG_B, 'Visible', 'off');
c2 = gui.SessionClock(figB);
assert(strcmp(c2.PreferenceTag, PREF_TAG_B), ...
    'PreferenceTag should default to the ancestor figure Tag (BehaviorGUI scoping)');
fprintf('PASS: PreferenceTag infers the hosting figure''s Tag\n');

% 7. Runtime timing sources: StartTime, NewTrial ---------------------------
rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;
assert(isnat(rt.StartTime), 'fresh Runtime should have no StartTime yet');

c1.attachRuntime(rt);
c1.refresh();
assert(contains(c1.LabelH.LastTrial.Text, '--'), ...
    'LastTrial should still read "--" before any trial (got "%s")', c1.LabelH.LastTrial.Text);
assert(contains(c1.LabelH.SessionDuration.Text, '00:00:0'), ...
    'session duration should read close to zero right after attach (got "%s")', c1.LabelH.SessionDuration.Text);
fprintf('PASS: attachRuntime falls back to now() for an unset StartTime\n');

rt.EVENTS.notify('NewTrial'); % first trial
c1.refresh();
assert(contains(c1.LabelH.LastTrial.Text, '00:00:0'), ...
    'time since last trial should read close to zero (got "%s")', c1.LabelH.LastTrial.Text);
assert(contains(c1.LabelH.FirstTrial.Text, '00:00:0'), ...
    'time since first trial should read close to zero (got "%s")', c1.LabelH.FirstTrial.Text);

pause(1.5);
rt.EVENTS.notify('NewTrial'); % second trial, ~1.5s later
c1.refresh();
assert(contains(c1.LabelH.LastTrial.Text, '00:00:0'), ...
    'time since last trial should reset to ~0 on every NewTrial (got "%s")', c1.LabelH.LastTrial.Text);
assert(~contains(c1.LabelH.FirstTrial.Text, '00:00:00'), ...
    'time since first trial should not reset on the second NewTrial (got "%s")', c1.LabelH.FirstTrial.Text);
fprintf('PASS: NewTrial resets last-trial every time but stamps first-trial once\n');

% 8. Start/stop the periodic refresh timer ---------------------------------
c1.refresh();
textBefore = c1.LabelH.ClockTime.Text;
c1.start();
pause(1.3);
textDuringRun = c1.LabelH.ClockTime.Text;
assert(~strcmp(textBefore, textDuringRun), 'clock text should advance while the timer is running');
c1.stop();
textAfterStop = c1.LabelH.ClockTime.Text;
pause(1.3);
assert(strcmp(textAfterStop, c1.LabelH.ClockTime.Text), 'clock text should stop advancing after stop()');
fprintf('PASS: start()/stop() control the periodic refresh\n');

% 9. Teardown ---------------------------------------------------------------
delete(c1);
delete(c2);
assert(isempty(timerfindall('Tag', 'EPsychSessionClock')), 'delete should remove the internal timer(s)');
close(figA);
close(figB);
fprintf('PASS: teardown cleans up the timer\n');

fprintf('smoke_test_sessionclock: ALL PASS\n');
end


function cleanupAll(prefTags)
% Remove test preferences and any stray test figures.
for i = 1:numel(prefTags)
    tag = prefTags{i};
    if ispref(tag)
        rmpref(tag);
    end
    delete(findall(groot,'Type','figure','-and','Tag',tag));
end
delete(findall(groot,'Type','figure','-and','Tag',[prefTags{1} '_2']));
delete(findall(groot,'Type','figure','-and','Tag',[prefTags{1} '_3']));
end
