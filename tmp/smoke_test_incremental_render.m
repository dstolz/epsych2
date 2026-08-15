function smoke_test_incremental_render()
% smoke_test_incremental_render()
% Equivalence proof for the per-trial render caches in gui.History,
% gui.ParameterScatter, and psychophysics.Staircase.
%
% Each component now builds a trial's row, value, or color once and appends
% it, rather than rebuilding the session on every trial. This test drives
% each component trial by trial and compares what it renders against a fresh
% instance handed the same trials all at once: the two must be identical.
%
% Also covered:
%   - a mid-session parameter-set change (History columns)
%   - an outcome written back into an already-recorded trial (History)
%   - a settings change with no refresh behind it (Staircase dB axis)
%
%   matlab -batch "run('tmp/smoke_test_incremental_render.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));
addpath(here); % +psychophysics/FakeHistoryPsych.m merges into the package

PREF_GROUP = 'epsych2_gui_History';
SCATTER_GROUP = 'epsych2_gui_ParameterScatter';
TAGS = {'smokeIncA','smokeIncB'};
cleanupPrefs(PREF_GROUP,TAGS);
cleanupPrefs(SCATTER_GROUP,TAGS);
restore = onCleanup(@() cleanupBoth(PREF_GROUP,SCATTER_GROUP,TAGS));

nFail = 0;
fprintf('\n=== incremental render equivalence ===\n');
fprintf('MATLAB %s\n\n',version('-release'));

nFail = nFail + historyChecks(TAGS);
nFail = nFail + scatterChecks(TAGS);
nFail = nFail + staircaseChecks();

fprintf('\n%s\n',repmat('-',1,52));
if nFail == 0
    fprintf('smoke_test_incremental_render: PASS\n');
else
    fprintf(2,'smoke_test_incremental_render: %d FAILURE(S)\n',nFail);
end
end


% ---------------------------------------------------------------- History

function nFail = historyChecks(tags)
nFail = 0;
N = 37;
D = makeData(N);
params = {'FreqHz','LevelDB','RespLatency','StimName'};

% Incremental: one trial at a time through the NewData listener.
Pinc = psychophysics.FakeHistoryPsych('FreqHz');
Pinc.setData(D(1));
[figA,Hinc] = makeHistory(Pinc,tags{1},params);
cA = onCleanup(@() close(figA));
for k = 2:N
    Pinc.appendTrials(D(k));
end

nFail = nFail + compareHistory('History: incremental vs fresh',Hinc,D,tags{2},params);

% A column added mid-session must not be extended onto rows built without it.
Hinc.ParametersOfInterest = {'FreqHz','LevelDB'};
Hinc.update();
nFail = nFail + compareHistory('History: parameter set changed mid-session', ...
    Hinc,D,tags{2},{'FreqHz','LevelDB'});

Hinc.ParametersOfInterest = params;
Hinc.update();

% An outcome written back into an earlier trial must retire the cached rows.
D(4).RespCode = uint32(bitset(uint32(0),uint32(epsych.BitMask.Abort)));
Pinc.mutateTrial(4,'RespCode',D(4).RespCode);
nFail = nFail + compareHistory('History: outcome back-filled into trial 4', ...
    Hinc,D,tags{2},params);

delete(Hinc);
clear cA
end

function nFail = compareHistory(label,Hinc,D,freshTag,params)
% Render the same trials into a fresh table and compare what is displayed.
Pfresh = psychophysics.FakeHistoryPsych('FreqHz');
Pfresh.setData(D);
[fig,Hfresh] = makeHistory(Pfresh,freshTag,params);
c = onCleanup(@() close(fig));
Hfresh.update();

nFail = 0;
nFail = nFail + check([label ' | table text'], ...
    isequaln(Hinc.TableH.Data,Hfresh.TableH.Data));
nFail = nFail + check([label ' | row colors'], ...
    isequaln(Hinc.TableH.BackgroundColor,Hfresh.TableH.BackgroundColor));
nFail = nFail + check([label ' | column names'], ...
    isequaln(Hinc.TableH.ColumnName,Hfresh.TableH.ColumnName));
nFail = nFail + check([label ' | trial IDs'], ...
    isequaln(Hinc.Info.TrialID,Hfresh.Info.TrialID));
nFail = nFail + check([label ' | response bits'], ...
    isequaln(Hinc.Info.ResponseBit,Hfresh.Info.ResponseBit));
nFail = nFail + check([label ' | relative time'], ...
    isequaln(Hinc.Info.RelativeTimestamp,Hfresh.Info.RelativeTimestamp));

delete(Hfresh);
clear c
cleanupPrefs('epsych2_gui_History',{freshTag});
end

function [fig,H] = makeHistory(P,tag,params)
fig = uifigure('Visible','off','Position',[100 100 700 500]);
H = gui.History(P,fig,PreferenceTag=tag);
H.ParametersOfInterest = params;
H.update();
end


% -------------------------------------------------------- ParameterScatter

function nFail = scatterChecks(tags)
nFail = 0;
N = 29;
D = makeData(N);

Pinc = psychophysics.FakeHistoryPsych('FreqHz');
Pinc.setData(D(1));
[figA,Sinc] = makeScatter(Pinc,tags{1});
cA = onCleanup(@() close(figA));
for k = 2:N
    Pinc.appendTrials(D(k));
end

% Numeric x/y, then a categorical axis and a categorical color: the codes a
% category was first assigned must survive the trials that followed.
combos = { ...
    {'Trial Number','LevelDB','(none)'}, ...
    {'FreqHz','LevelDB','RespLatency'}, ...
    {'Trial Number','StimName','Response'}, ...
    {'Response','LevelDB','StimName'}};

for k = 1:numel(combos)
    Sinc.XParameter = combos{k}{1};
    Sinc.YParameter = combos{k}{2};
    Sinc.ColorParameter = combos{k}{3};

    Pfresh = psychophysics.FakeHistoryPsych('FreqHz');
    Pfresh.setData(D);
    [fig,Sfresh] = makeScatter(Pfresh,tags{2});
    c = onCleanup(@() close(fig));
    Sfresh.XParameter = combos{k}{1};
    Sfresh.YParameter = combos{k}{2};
    Sfresh.ColorParameter = combos{k}{3};

    label = sprintf('ParameterScatter: %s / %s / %s', ...
        combos{k}{1},combos{k}{2},combos{k}{3});
    nFail = nFail + check([label ' | XData'], ...
        isequaln(Sinc.ScatterH.XData,Sfresh.ScatterH.XData));
    nFail = nFail + check([label ' | YData'], ...
        isequaln(Sinc.ScatterH.YData,Sfresh.ScatterH.YData));
    nFail = nFail + check([label ' | CData'], ...
        isequaln(Sinc.ScatterH.CData,Sfresh.ScatterH.CData));
    nFail = nFail + check([label ' | dropdown items'], ...
        isequal(Sinc.DropdownX.Items,Sfresh.DropdownX.Items));

    delete(Sfresh);
    clear c
    cleanupPrefs('epsych2_gui_ParameterScatter',tags(2));
end

delete(Sinc);
clear cA
end

function [fig,S] = makeScatter(P,tag)
fig = uifigure('Visible','off','Position',[100 100 700 500]);
S = gui.ParameterScatter(P,fig,PreferenceTag=tag);
end


% ------------------------------------------------------------- Staircase

function nFail = staircaseChecks()
nFail = 0;
N = 45;
D = makeStaircaseData(N);
Parameter = struct('validName','Depth');

R = FakeScatterRuntime();
Sinc = psychophysics.Staircase(R,Parameter);
figA = uifigure('Visible','off','Position',[100 100 700 500]);
cA = onCleanup(@() close(figA));
axA = uiaxes(figA);
Sinc.Plot(axA);

for k = 1:N
    R.EVENTS.notify('NewData',epsych.TrialsData( ...
        struct('DATA',{D(1:k)},'Subject','FakeSubject','BoxID',1)));
end

Sfresh = psychophysics.Staircase(D,'Depth');
figB = uifigure('Visible','off','Position',[100 100 700 500]);
cB = onCleanup(@() close(figB));
axB = uiaxes(figB);
Sfresh.Plot(axB);

nFail = nFail + compareStaircase('Staircase: incremental vs fresh',Sinc,axA,Sfresh,axB);

% A setting changed with no refresh behind it must not be served stale
% vectors: refreshPlot alone has to notice the dB conversion.
before = seriesData(axA);
Sinc.ConvertToDecibels = true;
Sinc.refreshPlot();
nFail = nFail + check('Staircase: dB toggle without a refresh reaches the plot', ...
    ~isequaln(before,seriesData(axA)));

Sfresh.ConvertToDecibels = true;
Sfresh.refreshPlot();
nFail = nFail + compareStaircase('Staircase: dB axis',Sinc,axA,Sfresh,axB);

delete(Sinc);
delete(Sfresh);
clear cA cB
end

function nFail = compareStaircase(label,Sinc,axA,Sfresh,axB)
nFail = 0;
nFail = nFail + check([label ' | Results'], ...
    isequaln(Sinc.Results,Sfresh.Results));

a = seriesData(axA);
b = seriesData(axB);
nFail = nFail + check([label ' | plotted series count'],isequal(numel(a),numel(b)));
if numel(a) ~= numel(b), return; end
for k = 1:numel(a)
    nFail = nFail + check(sprintf('%s | series "%s"',label,a(k).name), ...
        isequaln(a(k).x,b(k).x) && isequaln(a(k).y,b(k).y) && isequaln(a(k).c,b(k).c));
end
end

function s = seriesData(ax)
% Plotted series in a stable order, with their data and colors.
h = findobj(ax,'-property','XData');
names = arrayfun(@(o) string(o.DisplayName),h);
[names,idx] = sort(names);
h = h(idx);
s = struct('name',{},'x',{},'y',{},'c',{});
for k = 1:numel(h)
    s(k).name = char(names(k));
    s(k).x = h(k).XData;
    s(k).y = h(k).YData;
    if isprop(h(k),'CData')
        s(k).c = h(k).CData;
    else
        s(k).c = [];
    end
end
end


% ---------------------------------------------------------------- helpers

function nFail = check(label,tf)
if tf
    nFail = 0;
    fprintf('  ok   %s\n',label);
else
    nFail = 1;
    fprintf(2,'  FAIL %s\n',label);
end
end

function D = makeData(n)
% Per-trial DATA shaped like RUNTIME.TRIALS.DATA, with a text field so the
% categorical paths are exercised.
names = {'Tone','Noise','Click'};
t0 = datetime(2026,8,13,9,0,0);
D = struct([]);
for k = 1:n
    D(k).TrialID = mod(k-1,4)+1;
    D(k).RespCode = uint32(2^mod(k,5));
    D(k).computerTimestamp = t0 + seconds(k);
    D(k).FreqHz = 1000*2^mod(k,5);
    D(k).LevelDB = 30 + 5*mod(k,7);
    D(k).RespLatency = 100 + 3*mod(k,11);
    D(k).StimName = names{mod(k,3)+1};
end
end

function D = makeStaircaseData(n)
% Descending staircase with catch trials and the occasional abort.
HIT   = bitset(uint32(0),uint32(epsych.BitMask.Hit));
MISS  = bitset(uint32(0),uint32(epsych.BitMask.Miss));
CR    = bitset(uint32(0),uint32(epsych.BitMask.CorrectReject));
FA    = bitset(uint32(0),uint32(epsych.BitMask.FalseAlarm));
ABORT = bitset(uint32(0),uint32(epsych.BitMask.Abort));

depth = 40;
D = struct('Depth',{},'RespCode',{},'TrialType',{},'TrialID',{},'computerTimestamp',{});
t0 = datetime(2026,8,13,9,0,0);
for k = 1:n
    if mod(k,6) == 0
        rc = CR;
        if mod(k,12) == 0, rc = FA; end
        tt = 1;
    elseif mod(k,17) == 0
        rc = ABORT;
        tt = 0;
    elseif mod(k,3) == 0
        rc = MISS;
        tt = 0;
    else
        rc = HIT;
        tt = 0;
    end
    D(k).Depth = depth;
    D(k).RespCode = rc;
    D(k).TrialType = tt;
    D(k).TrialID = mod(k-1,3)+1;
    D(k).computerTimestamp = t0 + seconds(k);
    if tt == 0
        if rc == HIT
            depth = max(2,depth-4);
        elseif rc == MISS
            depth = min(60,depth+8);
        end
    end
end
end

function cleanupBoth(g1,g2,tags)
cleanupPrefs(g1,tags);
cleanupPrefs(g2,tags);
end

function cleanupPrefs(group,tags)
for k = 1:numel(tags)
    tag = matlab.lang.makeValidName(tags{k});
    if ispref(group,tag)
        rmpref(group,tag);
    end
end
end
