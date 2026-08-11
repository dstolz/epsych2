function smoke_test_parameter_control_bounds
% smoke_test_parameter_control_bounds
% Validates bound-property editing through gui.Parameter_Control and
% gui.Parameter_Update:
%   1. Raising a Max-bound control above the current Max commits and does NOT
%      log a spurious "outside bounds" warning.
%   2. A Value-bound edit field's widget Limits track Parameter.Min/Max
%      changes instead of freezing at creation time.
%   3. Narrowing the bounds clamps the displayed value so the Limits update
%      cannot error.
%   4. The Update button (gui.Parameter_Update) commits a Min-bound control to
%      Parameter.Min, not Parameter.Value (staircase floor regression).
%
% Run headless: matlab -batch "cd tmp; smoke_test_parameter_control_bounds"

fig = uifigure('Visible','off');
cleanupFig = onCleanup(@() delete(fig));
gl = uigridlayout(fig,[6 1]);

sw = hw.Software;
pSD = sw.add_parameter('StimDelay',2000,Unit='ms');
pSD.Value = 2000; pSD.Min = 1000; pSD.Max = 3000;
pDepth = sw.add_parameter('Depth',0.94,Unit='%');
pDepth.Value = 0.94; pDepth.Min = 1e-7; pDepth.Max = 1;

hVal = gui.Parameter_Control(gl,pSD,autoCommit=true,Text='Stimulus Delay (ms):');
hMax = gui.Parameter_Control(gl,pSD,autoCommit=true,BoundProperty='Max',Text='Stimulus Delay Max (ms):');
hMin = gui.Parameter_Control(gl,pSD,autoCommit=true,BoundProperty='Min',Text='Stimulus Delay Min (ms):');

% 1. Max control is not capped by the current Max and commits without warning
assert(isequal(hMax.h_uiobj.Limits,[1000 Inf]), ...
    'Max-bound control must not be limited by the current Max');
out = evalc('fire(hMax,4000)');
assert(~contains(out,'outside bounds'), ...
    'raising the Max control must not log an out-of-bounds warning:\n%s',out);
assert(pSD.Max == 4000, 'Max edit should commit to Parameter.Max');
fprintf('PASS: Max-bound control raises Max silently\n');

% 2. Value control's widget Limits follow the parameter bounds
assert(isequal(hVal.h_uiobj.Limits,[1000 4000]), ...
    'Value control Limits should refresh after Max changed');
fire(hVal,3500); % valid under the new bounds
assert(pSD.Value == 3500, 'Value edit inside the new bounds should commit');
fprintf('PASS: widget Limits track bounds; widened range usable\n');

% 3. Narrowing bounds clamps the displayed value before Limits update
fire(hMax,1500);
assert(pSD.Max == 1500, 'Max edit should commit when lowering');
assert(isequal(hVal.h_uiobj.Limits,[1000 1500]), 'Limits should narrow');
assert(hVal.h_uiobj.Value <= 1500, 'displayed value should be clamped');
assert(isequal(hMin.h_uiobj.Limits,[-Inf 1500]), 'Min control tracks Max');
fprintf('PASS: narrowed bounds clamp the display\n');

% 4. Update button commits Min-bound edits to Parameter.Min, not Value
hDepthMin = gui.Parameter_Control(gl,pDepth,BoundProperty='Min',Text='Minimum Depth (%):');
RT.TRIALS.trials = {0.94};
RT.TRIALS.writeParamIdx.Depth = 1;
pu = gui.Parameter_Update(RT,gl);
pu.watchedHandles = hDepthMin;

fire(hDepthMin,1); % pending edit (non-autoCommit)
assert(hDepthMin.ValueUpdated, 'Min edit should be pending before Update');
assert(pDepth.Min == 1e-7, 'Min must not change before Update is pressed');
pu.commit_changes([],[]);
assert(pDepth.Min == 1, 'Update must commit the edit to Parameter.Min');
assert(pDepth.Value == 0.94, 'Update must not write the Min edit into Parameter.Value');
assert(~hDepthMin.ValueUpdated, 'pending flag should clear after commit');
fprintf('PASS: Update button commits Min-bound edit to Parameter.Min\n');

% let timed_color_change timers fire before the figure is deleted
pause(1.2)
fprintf('smoke_test_parameter_control_bounds: ALL PASS\n');
end


function fire(h,newValue)
% Simulate a user edit committed in the control's edit field.
ev.Value = newValue;
ev.PreviousValue = h.h_uiobj.Value;
h.h_uiobj.Value = min(max(newValue,h.h_uiobj.Limits(1)),h.h_uiobj.Limits(2));
h.value_changed(h.h_uiobj,ev);
end
