function smoke_test_add_subject_dialog()
% smoke_test_add_subject_dialog()
% Exercise epsych.DefaultSubject: struct construction, sex normalization,
% the modernized entry dialog (driven programmatically via timers), and the
% ReservedNames duplicate check.
% Headless-safe: every GUI is closed before returning.
%
%   matlab -batch "cd('tmp'); smoke_test_add_subject_dialog"

epsych_startup

% Preserve the user's species preferences; the dialog writes to them.
hadPref = ispref('ep_AddSubject');
savedPrefs = struct();
if hadPref
    savedPrefs = getpref('ep_AddSubject');
end
cleanupObj = onCleanup(@() restorePrefs(hadPref, savedPrefs));

% Seed legacy GUIDE-style prefs: column-oriented list with sentinel entry.
% The modern dialog must tolerate and clean up this format.
setpref('ep_AddSubject', 'species', {'Gerbil'; '< ADD SPECIES >'});
setpref('ep_AddSubject', 'user_species', 'Gerbil');

% 1. Programmatic construction and legacy sex-code normalization ----------
s = epsych.DefaultSubject(struct('BoxID',2,'Name','M001','Sex','M','Species','Mouse'));
assert(strcmp(s.Sex,'Male'), 'Legacy sex code M not normalized (got %s)', s.Sex);
assert(s.isValid(), 'Struct-constructed subject should be valid');
r = s.toStruct();
assert(r.BoxID==2 && strcmp(r.Name,'M001') && isnan(r.Weight), 'toStruct roundtrip failed');
fprintf('PASS: construction + sex normalization + toStruct\n');

% 2. Dialog cancel path ---------------------------------------------------
t = driveTimer(@(f) clickButton(f, 'Cancel'));
out = epsych.DefaultSubject.open();
stop(t); delete(t);
assert(isempty(out), 'Cancelled dialog should return []');
assert(isempty(findDialog()), 'Dialog figure should be deleted after cancel');
fprintf('PASS: cancel returns [] and closes figure\n');

% 3. Dialog confirm path with blank weight --------------------------------
%    Only 3:5 are free, but all 16 boxes must still be offered and box 1 must
%    still be the default: an occupied box is marked, never removed.
t = driveTimer(@(f) checkBoxesThenConfirm(f, 'SMOKE1'));
out = epsych.DefaultSubject.open([], 3:5);
stop(t); delete(t);
assert(isa(out,'epsych.DefaultSubject'), 'Confirmed dialog should return a DefaultSubject');
assert(strcmp(out.Name,'SMOKE1'), 'Name not captured (got %s)', out.Name);
assert(out.BoxID==1, 'Box 1 must always be the default (got %d)', out.BoxID);
assert(isnan(out.Weight), 'Blank weight must be NaN, not %g', out.Weight);
assert(strcmp(out.Species,'Gerbil'), ...
    'Last-used species should be preselected (got %s)', out.Species);
assert(out.isValid(), 'Confirmed subject should be valid');
fprintf('PASS: confirm captures fields; blank weight -> NaN; last-used species\n');

% 4. ReservedNames rejects duplicates, accepts a rename -------------------
t = driveTimer(@(f) duplicateThenRename(f, 'SMOKE1', 'SMOKE2'));
out = epsych.DefaultSubject.open([], 1:16, 'ReservedNames', {'smoke1'});
stop(t); delete(t);
assert(~isempty(out) && strcmp(out.Name,'SMOKE2'), ...
    'Dialog should reject reserved name then accept rename (got %s)', resultName(out));
fprintf('PASS: ReservedNames blocks duplicate (case-insensitive), rename accepted\n');

% 5. Edit mode --------------------------------------------------------------
t = driveTimer(@(f) verifyEditThenOK(f));
obj = epsych.DefaultSubject.open(struct('Name','EDITME','Sex','F','Species','Rat'), 1:4);
stop(t); delete(t);
assert(isa(obj,'epsych.DefaultSubject'), 'open must return a subject object');
S = obj.toStruct();
assert(strcmp(S.Name,'EDITME') && strcmp(S.Sex,'Female'), ...
    'Dialog lost seeded fields (Name=%s, Sex=%s)', S.Name, S.Sex);
fprintf('PASS: edit mode title + struct seed contract + F -> Female\n');

% 6. Species list migrated: new entry added, legacy sentinel dropped ------
pl = getpref('ep_AddSubject', 'species');
assert(any(strcmp(pl,'Rat')), 'Seeded species Rat should have been added to the list');
assert(~any(strcmp(pl,'< ADD SPECIES >')), 'Legacy sentinel should be dropped from the list');
fprintf('PASS: species list migrated from legacy format\n');

fprintf('smoke_test_add_subject_dialog: ALL PASS\n');
end

% ==========================================================================
function t = driveTimer(action)
% Poll for the dialog once per second (first uifigure creation can be slow
% in -batch), then run action(fig) exactly once.
t = timer('ExecutionMode','fixedSpacing', 'StartDelay',1, 'Period',1, ...
    'TasksToExecute',120, 'TimerFcn', @(tt,~) runAction(tt, action));
start(t);
end

function runAction(t, action)
f = findDialog();
if isempty(f), return, end  % dialog not up yet; retry on next tick
btns = findall(f(1), 'Type','uibutton');
if isempty(btns) || ~any(strcmp(get(btns,'Text'), 'OK'))
    return  % dialog still under construction; retry on next tick
end
stop(t);
try
    action(f(1));
catch ME
    fprintf(2, 'DRIVER ERROR: %s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
    delete(f(1));  % unblock uiwait so the test fails with a clear assert
end
end

function f = findDialog()
f = [findall(groot, 'Type','figure', 'Name','Add Subject'); ...
     findall(groot, 'Type','figure', 'Name','Edit Subject')];
end

function clickButton(f, label)
btns = findall(f, 'Type','uibutton');
b = btns(strcmp(get(btns,'Text'), label));
b(1).ButtonPushedFcn(b(1), []);
end

function ef = nameField(f)
ef = findall(f, 'Type','uieditfield');  % numeric field has its own type
ef = ef(1);
end

function confirmWithName(f, name)
ef = nameField(f);
ef.Value = name;
clickButton(f, 'OK');
end

function checkBoxesThenConfirm(f, name)
dd = boxDropdown(f);
assert(isequal(dd.ItemsData, 1:16), 'All 16 boxes must be selectable');
assert(isequal(dd.Value, 1), 'Box 1 must be the preselected default (got %d)', dd.Value);
assert(strcmp(dd.Items{1}, '1'), ...
    'An occupied box must be listed unmarked, not hidden (got "%s")', dd.Items{1});
assert(strcmp(dd.Items{3}, '3'), ...
    'A free box must be listed unmarked (got "%s")', dd.Items{3});
confirmWithName(f, name);
end

function dd = boxDropdown(f)
% The box dropdown is the only one carrying numeric ItemsData.
dds = findall(f, 'Type','uidropdown');
isBox = arrayfun(@(d) isnumeric(d.ItemsData) && ~isempty(d.ItemsData), dds);
dd = dds(find(isBox, 1));
assert(~isempty(dd), 'Box dropdown not found');
end

function duplicateThenRename(f, dupName, newName)
ef = nameField(f);
ef.Value = dupName;
clickButton(f, 'OK');
assert(isgraphics(f), 'Dialog should stay open after duplicate rejection');
ef.Value = newName;
clickButton(f, 'OK');
end

function verifyEditThenOK(f)
assert(strcmp(f.Name,'Edit Subject'), 'Seeded dialog should be in edit mode');
dds = findall(f, 'Type','uidropdown');
items = get(dds,'Items');
if ~iscell(items{1}), items = {items}; end
isSex = cellfun(@(c) isequal(sort(c(:)'), sort({'Female','Male','Unknown'})), items);
sexdd = dds(isSex);
assert(strcmp(sexdd(1).Value,'Female'), 'Legacy F seed should preselect Female');
clickButton(f, 'OK');
end

function n = resultName(out)
if isempty(out), n = '<empty>'; else, n = out.Name; end
end

function restorePrefs(hadPref, saved)
if ispref('ep_AddSubject')
    rmpref('ep_AddSubject');
end
if hadPref
    fn = fieldnames(saved);
    for i = 1:numel(fn)
        setpref('ep_AddSubject', fn{i}, saved.(fn{i}));
    end
end
end
