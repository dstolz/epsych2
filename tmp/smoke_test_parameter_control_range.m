function smoke_test_parameter_control_range
% smoke_test_parameter_control_range
% Validates the single-row [min max] control, gui.components.Parameter_Control with
% Type='range':
%   1. Layout: one label plus two entry fields in a single grid row.
%   2. An autoCommit edit of either field writes Parameter.Min/Parameter.Max.
%   3. An inverted pair (min > max) is rejected: the offending field reverts
%      and the parameter is untouched.
%   4. An external Min/Max change (phase load, linked parameter) refreshes
%      both fields.
%   5. Staged edits work with gui.components.Parameter_Update: commit writes the pair,
%      reset restores it.
%   6. Unbounded parameters (-Inf/Inf) display, and a randomized parameter
%      refuses non-finite bounds.
%   7. Binding errors are reported (range with a scalar BoundProperty,
%      MinMax on a type that cannot show a pair).
%
% Run headless: matlab -batch "cd tmp; smoke_test_parameter_control_range"

fig = uifigure('Visible','off');
cleanupFig = onCleanup(@() delete(fig));
gl = uigridlayout(fig,[6 1]);

sw = hw.Software;
pSD = sw.add_parameter('StimDelay',2000,Unit='ms');
pSD.Value = 2000; pSD.Min = 1000; pSD.Max = 3000;

h = gui.components.Parameter_Control(gl,pSD,Type='range',autoCommit=true, ...
    Text='Stimulus Delay (ms):');

% 1. one row, three columns: label + two entries
assert(isequal(h.BoundProperty,'MinMax'),'Type=range must default to the MinMax binding');
assert(numel(h.container.RowHeight) == 1,'range control must occupy a single row');
assert(numel(h.container.ColumnWidth) == 3,'range control is label + two entries');
assert(~isempty(h.h_uiobj2),'range control needs a second entry field');
assert(isequal(h.h_uiobj.Parent,h.h_uiobj2.Parent),'both entries share the row');
assert(isequal(h.Value,[1000 3000]),'control should show [Min Max]');
fprintf('PASS: one row carries label + both entries\n');

% 2. autoCommit edits of either field reach Min and Max
fire(h,h.h_uiobj,1500);
assert(pSD.Min == 1500,'left entry must commit to Parameter.Min');
assert(pSD.Max == 3000,'left entry must not disturb Parameter.Max');
fire(h,h.h_uiobj2,4000);
assert(isequal([pSD.Min pSD.Max],[1500 4000]),'right entry must commit to Parameter.Max');
fprintf('PASS: each entry commits to its own bound\n');

% 3. inverted pair is rejected, offending field reverts, parameter untouched
out = evalc('fire(h,h.h_uiobj,9000)');
assert(contains(out,'Rejected range'),'an inverted pair should be reported:\n%s',out);
assert(isequal([pSD.Min pSD.Max],[1500 4000]),'a rejected pair must not touch the parameter');
assert(isequal(h.Value,[1500 4000]),'the offending entry must revert');
fprintf('PASS: min > max is rejected and reverted\n');

% 4. external change refreshes both entries
pSD.Min = 500; pSD.Max = 2500;
assert(isequal(h.Value,[500 2500]),'external Min/Max change must refresh both entries');
fprintf('PASS: external bound changes refresh both entries\n');

% 5. staged edit + Parameter_Update commit and reset
hs = gui.components.Parameter_Control(gl,pSD,Type='range',Text='Delay range (ms):');
RT.TRIALS.trials = {2000};
RT.TRIALS.writeParamIdx.StimDelay = 1;
pu = gui.components.Parameter_Update(RT,gl);
pu.watchedHandles = hs;

fire(hs,hs.h_uiobj2,3300);
assert(hs.ValueUpdated,'a staged range edit should be pending');
assert(pSD.Max == 2500,'a staged edit must not write the parameter');
pu.commit_changes([],[]);
assert(isequal([pSD.Min pSD.Max],[500 3300]),'Update must commit the pair');
assert(~hs.ValueUpdated,'pending flag should clear after commit');
assert(pSD.Value == 2000,'a MinMax edit must never land in Parameter.Value');

fire(hs,hs.h_uiobj,600);
assert(hs.ValueUpdated,'second staged edit should be pending');
pu.reset_changes([],[]);
assert(isequal(hs.Value,[500 3300]),'reset must restore the entries from the parameter');
assert(~hs.ValueUpdated,'pending flag should clear after reset');
fprintf('PASS: staged edits commit and reset as a pair\n');

% 6. unbounded display and the randomized-parameter finite-bounds rule
pFree = sw.add_parameter('Unbounded',0);
hFree = gui.components.Parameter_Control(gl,pFree,Type='range',autoCommit=true);
assert(isequal(hFree.Value,[-Inf Inf]),'default bounds should display as -Inf/Inf');
fire(hFree,hFree.h_uiobj,-10);
assert(pFree.Min == -10,'an infinite bound should still be editable');

pSD.isRandom = true;
out = evalc('fire(h,h.h_uiobj2,Inf)');
assert(contains(out,'Rejected range'),'a randomized parameter must refuse Inf bounds:\n%s',out);
assert(isfinite(pSD.Max),'the parameter must keep its finite Max');
pSD.isRandom = false;
fprintf('PASS: unbounded display works; randomized bounds stay finite\n');

% 7. binding errors
try
    gui.components.Parameter_Control(gl,pSD,Type='range',BoundProperty='Min');
    error('smoke:NoError','range with a scalar BoundProperty should error');
catch ME
    assert(isequal(ME.identifier,'gui:Parameter_Control:InvalidRangeBinding'),ME.message);
end
try
    gui.components.Parameter_Control(gl,pSD,Type='editfield',BoundProperty='MinMax');
    error('smoke:NoError','MinMax on an editfield should error');
catch ME
    assert(isequal(ME.identifier,'gui:Parameter_Control:InvalidMinMaxType'),ME.message);
end
fprintf('PASS: invalid bindings are rejected at construction\n');

% let timed_color_change timers fire before the figure is deleted
pause(1.2)
fprintf('smoke_test_parameter_control_range: ALL PASS\n');
end


function fire(h,field,newValue)
% Simulate a user edit committed in one entry field of a range control.
ev.Value = newValue;
ev.PreviousValue = field.Value;
field.Value = newValue;
h.value_changed(field,ev);
end
