% shot_notes.m
% Render gui.Notes (panel form beside the button form) to a PNG, to check the
% layout by eye. exportapp needs a real display, so this goes through
% matlab -batch rather than the MCP session.
%
%   matlab -batch "run('tmp/shot_notes.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

R = epsych.Runtime;
R.StartTime = datetime('now') - seconds(1025);

fig = uifigure('Name','Notes','Position',[100 100 640 360]);
g = uigridlayout(fig,[2 2], 'RowHeight',{'1x',30}, 'ColumnWidth',{'1x',110});

N = gui.Notes(R, g);
N.LogH.Parent.Layout.Row = 1;
N.LogH.Parent.Layout.Column = [1 2];

B = gui.Notes(R, g, ButtonOnly = true);
B.OpenH.Layout.Row = 2;
B.OpenH.Layout.Column = 2;

lbl = uilabel(g,'Text','  <- the whole panel; the button form is at the right');
lbl.Layout.Row = 2;
lbl.Layout.Column = 1;

R.NOTES.add('session start; animal alert, weight 24.1 g');
R.NOTES.add('ear plug reseated');
R.NOTES.add('bottle refilled, brief pause');

drawnow
exportapp(fig, fullfile(here,'..','documentation','gui','images','Notes.png'));
fprintf('wrote %s\n', fullfile(here,'..','documentation','gui','images','Notes.png'));
delete(fig)
