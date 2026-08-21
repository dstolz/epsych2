% check_notes_dialog.m
% Drive gui.BehaviorBuilder's Session Notes options dialog headlessly: open
% it on a placed region, set every field from code, and press OK, then assert
% the region's Options came back changed. A modal dialog blocks the MATLAB
% MCP session's transport, so this one goes through matlab -batch.
%
%   matlab -batch "run('tmp/check_notes_dialog.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

outDir = fullfile(tempdir,'epsych_notes_dialog_check');
if ~isfolder(outDir), mkdir(outDir); end
cleanupObj = onCleanup(@() rmdirQuiet(outDir));

spec = gui.BehaviorBuilder.specNew;
spec.ClassName  = 'NotesDialogCheckGUI';
spec.Grid.Rows = 2; spec.Grid.Cols = 1;
spec.Grid.RowHeight = {'1x','40'}; spec.Grid.ColumnWidth = {'1x'};
spec.Regions(end+1) = struct('Id','N1', 'Type','Notes', 'Label','Notes', ...
    'Row',[1 1], 'Col',[1 1], 'PopOut',false, ...
    'Options',gui.BehaviorBuilder.defaultOptions('Notes'));
specFile = fullfile(outDir,'NotesDialogCheckGUI.eblt');
gui.BehaviorBuilder.saveSpecFile(gui.BehaviorBuilder.specValidate(spec), specFile);

b = gui.BehaviorBuilder;
b.openSpec(specFile);

% Fill the dialog in and press OK once it exists. The timer is the only way
% in: configureRegion blocks in uiwait until the dialog resumes.
t = timer('StartDelay',2, 'TimerFcn',@(~,~) driveDialog());
start(t);
ok = b.configureRegion('N1', false);
stop(t); delete(t);

assert(ok, 'the dialog should report OK');
o = b.Spec.Regions(1).Options;
assert(strcmp(o.TimeStamp,'clock'), 'stamp choice should have been taken, got "%s"', o.TimeStamp);
assert(o.Editable, 'the Editable checkbox should have been taken');
assert(o.ButtonOnly, 'the Button only checkbox should have been taken');
assert(strcmp(o.Text,'Log'), 'the button label should have been taken, got "%s"', o.Text);
fprintf('PASS: the Session Notes options dialog opens, edits, and commits\n');

delete(b);


function driveDialog()
dlg = findall(groot, 'Type','figure', '-and', '-regexp', 'Name','^Session Notes');
if isempty(dlg)
    fprintf(2, 'FAIL: no Session Notes dialog appeared\n');
    return
end
dlg = dlg(1);

dd = findall(dlg, 'Type','uidropdown');
dd.Value = 'clock';

cbs = findall(dlg, 'Type','uicheckbox');
for c = cbs(:)'
    c.Value = true;
    % ValueChangedFcn does not fire on a programmatic set, so run the
    % button-only enable sync by hand, the way a click would.
    if ~isempty(c.ValueChangedFcn), c.ValueChangedFcn(c, []); end
end

ef = findall(dlg, 'Type','uieditfield');
ef.Value = 'Log';

okBtn = findall(dlg, 'Type','uibutton', '-and', 'Text','OK');
okBtn.ButtonPushedFcn(okBtn, []);
end


function rmdirQuiet(d)
try
    if isfolder(d), rmdir(d,'s'); end
catch
end
end
