function shoot_onlineplot()
% shoot_onlineplot()
% Render a populated gui.components.OnlinePlot and save a PNG, to eyeball the appearance.
% Writes tmp/onlineplot_after.png.

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));
addpath(here);

rt = epsych.Runtime; rt.isTest = true; rt.EVENTS = epsych.EventHub;
iface = BatchProbeInterface();
names = {'SpoutContact','LickDetect','StimOnset','RewardValve','TimeoutFlag', ...
         'HouseLight','TrialReady','ResponseWindow'};
P = hw.Parameter.empty(1,0);
for i = 1:numel(names)
    p = iface.add_parameter(names{i}, 0); p.Value = 0;
    iface.put(p,0); P(end+1) = p; %#ok<AGROW>
end
pTrig = iface.add_parameter('_TrigState~1', 0);
pNum  = iface.add_parameter('_TrialNum~1', 1);
iface.put(pTrig,0); iface.put(pNum,1);
rt.Interfaces = iface;

op = gui.components.OnlinePlot(rt, P);
stop(op.h_timer);
if op.startTic_ == 0
    op.h_timer.Timer.StartFcn(op.h_timer.Timer,[]);
end
op.redrawPeriod = 0;

% Synthesize plausible box activity in REAL time: the plot stamps samples with
% its own clock, so the loop has to take as long as the window it fills.
trial = 1;
t0 = tic;
lastTrial = 0;
while toc(t0) < 14
    ph = toc(t0);
    for i = 1:numel(P)
        on = mod(ph + i*0.37, 1.1 + 0.25*i) < (0.25 + 0.08*i);
        iface.put(P(i), double(on));
    end
    if ph - lastTrial > 2.5
        iface.put(pTrig,1); trial = trial + 1; iface.put(pNum,trial);
        lastTrial = ph;
    else
        iface.put(pTrig,0);
    end
    op.update();
    pause(0.05);
end

drawnow
f = op.figH;
f.Visible = 'on';
drawnow
exportgraphics(f, fullfile(here,'onlineplot_after.png'), Resolution=150);
fprintf('wrote %s\n', fullfile(here,'onlineplot_after.png'));

delete(op); close(f);
end
