% smoke_test_staircase_plot
% Render psychophysics.Staircase plots from synthetic offline DATA and export
% PNG screenshots so the plot's appearance can be reviewed without hardware.
%
% Two figures are captured: a large standalone window and a small embedded
% axes, because legend/label crowding only shows up at the smaller size used
% by the behavior GUIs.
%
% Set SHOT_TAG in the base workspace to label the exported files:
%   SHOT_TAG = 'before'; run('tmp/smoke_test_staircase_plot.m')

repoRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(repoRoot);
if exist('epsych_startup','file') == 2
    epsych_startup;
end

if ~exist('SHOT_TAG','var') || isempty(SHOT_TAG)
    SHOT_TAG = 'current';
end
outDir = fullfile(repoRoot,'tmp','staircase_shots');
if ~exist(outDir,'dir'), mkdir(outDir); end

% --- Synthetic staircase session -------------------------------------------
rng(7);

HIT   = bitset(uint32(0), uint32(epsych.BitMask.Hit));
MISS  = bitset(uint32(0), uint32(epsych.BitMask.Miss));
CR    = bitset(uint32(0), uint32(epsych.BitMask.CorrectReject));
FA    = bitset(uint32(0), uint32(epsych.BitMask.FalseAlarm));
ABORT = bitset(uint32(0), uint32(epsych.BitMask.Abort));

nTrials  = 70;
depth    = -4;      % dB re 100% depth
trueThr  = -18;
stepDown = 2;
stepUp   = 4;

DATA = struct('Depth',{},'RespCode',{},'TrialType',{});
for k = 1:nTrials
    isCatch = mod(k,6) == 0;

    if isCatch
        rc = CR;
        if rand < 0.2, rc = FA; end
        DATA(end+1) = struct('Depth',depth,'RespCode',rc,'TrialType',1);
        continue
    end

    if rand < 0.04
        DATA(end+1) = struct('Depth',depth,'RespCode',ABORT,'TrialType',0);
        continue
    end

    pHit = 1 ./ (1 + exp(-0.55*(depth - trueThr)));
    if rand < pHit
        DATA(end+1) = struct('Depth',depth,'RespCode',HIT,'TrialType',0);
        depth = max(-30, depth - stepDown);
    else
        DATA(end+1) = struct('Depth',depth,'RespCode',MISS,'TrialType',0);
        depth = min(0, depth + stepUp);
    end
end

% --- Large standalone window ------------------------------------------------
S1 = psychophysics.Staircase(DATA, 'Depth', StaircaseDirection="Down");
figLarge = uifigure('Name','Staircase (large)','Position',[80 80 1100 620]);
gl = uigridlayout(figLarge,[1 1]);
axLarge = uiaxes(gl);
S1.Plot(axLarge);
drawnow

% --- Small embedded axes, as used inside a BehaviorGUI ---------------------------
S2 = psychophysics.Staircase(DATA, 'Depth', StaircaseDirection="Down");
figSmall = uifigure('Name','Staircase (embedded)','Position',[80 80 620 340]);
gl2 = uigridlayout(figSmall,[1 1]);
axSmall = uiaxes(gl2);
S2.Plot(axSmall);
drawnow

pause(1)

fLarge = fullfile(outDir, sprintf('staircase_large_%s.png', SHOT_TAG));
fSmall = fullfile(outDir, sprintf('staircase_small_%s.png', SHOT_TAG));
exportapp(figLarge, fLarge);
exportapp(figSmall, fSmall);

fprintf('SMOKE: wrote %s\n', fLarge);
fprintf('SMOKE: wrote %s\n', fSmall);

% --- Toggles, repeated updates, and degenerate data -------------------------
S3 = psychophysics.Staircase(DATA, 'Depth', StaircaseDirection="Down");
figT = uifigure('Name','Staircase (toggles)','Position',[80 80 900 500]);
axT = uiaxes(uigridlayout(figT,[1 1]));
S3.Plot(axT);

S3.ShowSteps = false;
S3.refreshPlot();
S3.ShowReversals = false;
S3.refreshPlot();
drawnow
exportapp(figT, fullfile(outDir, sprintf('staircase_nosteps_%s.png', SHOT_TAG)));

S3.ShowSteps = true;
S3.ShowReversals = true;

% A live session redraws on every trial; the legend must not accumulate.
for k = 1:20
    S3.refreshPlot();
end
drawnow
nLegends = numel(findobj(figT,'Type','legend'));
fprintf('SMOKE: legends after 20 updates = %d (expect 1)\n', nLegends);

% Single trial: no range to pad, and no reversals or threshold to draw.
S4 = psychophysics.Staircase(DATA(1), 'Depth');
figD = uifigure('Name','Staircase (single trial)','Position',[80 80 500 320]);
axD = uiaxes(uigridlayout(figD,[1 1]));
S4.Plot(axD);
drawnow
fprintf('SMOKE: single-trial xlim = [%g %g], ylim = [%g %g]\n', ...
    axD.XLim, axD.YLim);

delete(figLarge)
delete(figSmall)
delete(figT)
delete(figD)
delete(S1)
delete(S2)
delete(S3)
delete(S4)
