function run_example()
% run_example()
% Launch ExampleBehaviorGUI against a software-only runtime so the GUI can be
% developed and iterated without hardware or a full RunExpt session.
% During a real session RunExpt launches the GUI the same way
% (feval('ExampleBehaviorGUI', RUNTIME)) and its timer drives the NewTrial/
% NewData/ModeChange events the GUI listens to.
%
% Requires the EPsych toolbox on the path (run epsych_startup once).

addpath(fileparts(mfilename('fullpath'))); % make ExampleBehaviorGUI reachable

rt = epsych.Runtime;
rt.isTest = true;
rt.HELPER = epsych.Helper;

% Software stand-ins for the parameters a real protocol would provide.
% add_parameter stores design-time Values; trial dispatch assigns the live
% Value in a real session, so assign it here directly.
sw = hw.Software;
p = sw.add_parameter('DropPellet', 0, isTrigger=true);    p.Value = 0;
p = sw.add_parameter('~TrialDelivery', false, Type='Boolean'); p.Value = false;
p = sw.add_parameter('ITIDur', 5, Unit='s');              p.Value = 5;
p = sw.add_parameter('TimeoutDur', 8, Unit='s');          p.Value = 8;
p = sw.add_parameter('Depth', 50, Unit='%');              p.Value = 50;
p = sw.add_parameter('dBSPL', 60, Unit='dB SPL');         p.Value = 60;
p = sw.add_parameter('InTrial', false, Type='Boolean');   p.Value = false; p.Access = 'Read';
p = sw.add_parameter('RespCode', 0);                      p.Value = 0;     p.Access = 'Read';
p = sw.add_parameter('TrialCount', 0);                    p.Value = 0;     p.Access = 'Read';
rt.Interfaces = sw;

ExampleBehaviorGUI(rt);

vprintf(0, 'ExampleBehaviorGUI launched. Edit a control and press "Update Parameters" to commit.')
