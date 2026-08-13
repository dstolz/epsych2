function smoke_test_incremental_perf()
% smoke_test_incremental_perf()
% Median cost of one appended trial for the three components that used to
% rebuild whole-session state per trial. Measurement harness, not a
% pass/fail test: it fails only if the harness itself breaks.
%
% Figures are invisible and there is no drawnow: this isolates the
% computation the per-trial caches target, not graphics marshalling.
%
% Measured in matlab -batch, R2024b, before and after the caches (ms):
%          History          ParameterScatter   Staircase
%   N=200   9.09 -> 3.73     31.69 -> 28.83    17.20 -> 15.81
%   N=1000 29.85 -> 8.39     39.10 -> 33.17    51.63 -> 29.67
% The scatter's remaining cost is graphics, not value extraction.
%
%   matlab -batch "run('tmp/smoke_test_incremental_perf.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));
addpath(here);

NREP = 15;
fprintf('\n=== per-appended-trial cost (ms, median of %d) ===\n',NREP);
fprintf('%-8s %-12s %-16s %-12s\n','N','History','ParameterScatter','Staircase');
fprintf('%s\n',repmat('-',1,52));
for N = [200 1000]
    fprintf('%-8d %-12.3f %-16.3f %-12.3f\n', N, ...
        timeHistory(N,NREP), timeScatter(N,NREP), timeStaircase(N,NREP));
end
fprintf('\n');
end


function ms = timeHistory(N,nrep)
P = psychophysics.FakeHistoryPsych('FreqHz');
P.setData(makeData(N));
f = uifigure('Visible','off','Position',[100 100 700 500]);
c = onCleanup(@() close(f));
H = gui.History(P,f,PreferenceTag='perfSection34');
H.ParametersOfInterest = {'FreqHz','LevelDB','RespLatency','StimName'};
H.update();

t = nan(1,nrep);
for k = 1:nrep
    trial = makeData(1);
    trial.computerTimestamp = datetime('now') + seconds(N+k);
    tic
    P.appendTrials(trial);
    t(k) = toc;
end
ms = median(t)*1e3;
delete(H);
if ispref('epsych2_gui_History','perfSection34')
    rmpref('epsych2_gui_History','perfSection34');
end
clear c
end


function ms = timeScatter(N,nrep)
P = psychophysics.FakeHistoryPsych('FreqHz');
P.setData(makeData(N));
f = uifigure('Visible','off','Position',[100 100 700 500]);
c = onCleanup(@() close(f));
S = gui.ParameterScatter(P,f,PreferenceTag='perfSection34');
S.XParameter = 'FreqHz';
S.YParameter = 'LevelDB';
S.ColorParameter = 'Response';

t = nan(1,nrep);
for k = 1:nrep
    trial = makeData(1);
    trial.computerTimestamp = datetime('now') + seconds(N+k);
    tic
    P.appendTrials(trial);
    t(k) = toc;
end
ms = median(t)*1e3;
delete(S);
if ispref('epsych2_gui_ParameterScatter','perfSection34')
    rmpref('epsych2_gui_ParameterScatter','perfSection34');
end
clear c
end


function ms = timeStaircase(N,nrep)
D = makeStaircaseData(N+nrep);
R = FakeScatterRuntime();
S = psychophysics.Staircase(R,struct('validName','Depth'));
f = uifigure('Visible','off','Position',[100 100 700 500]);
c = onCleanup(@() close(f));
S.Plot(uiaxes(f));

notifyTrials(R,D(1:N));
t = nan(1,nrep);
for k = 1:nrep
    d = D(1:N+k);
    tic
    notifyTrials(R,d);
    t(k) = toc;
end
ms = median(t)*1e3;
delete(S);
clear c
end

function notifyTrials(R,D)
R.HELPER.notify('NewData',epsych.TrialsData( ...
    struct('DATA',{D},'Subject','FakeSubject','BoxID',1)));
end


function D = makeData(n)
names = {'Tone','Noise','Click'};
D = struct([]);
for k = 1:n
    D(k).TrialID = mod(k-1,4)+1;
    D(k).RespCode = uint32(2^mod(k,5));
    D(k).computerTimestamp = datetime('now') + seconds(k);
    D(k).FreqHz = 1000*2^mod(k,5);
    D(k).LevelDB = 30 + 5*mod(k,7);
    D(k).RespLatency = 100 + 3*mod(k,11);
    D(k).StimName = names{mod(k,3)+1};
end
end

function D = makeStaircaseData(n)
HIT   = bitset(uint32(0),uint32(epsych.BitMask.Hit));
MISS  = bitset(uint32(0),uint32(epsych.BitMask.Miss));
CR    = bitset(uint32(0),uint32(epsych.BitMask.CorrectReject));
depth = 40;
D = struct('Depth',{},'RespCode',{},'TrialType',{},'TrialID',{});
for k = 1:n
    if mod(k,6) == 0
        D(k).RespCode = CR; D(k).TrialType = 1;
    elseif mod(k,3) == 0
        D(k).RespCode = MISS; D(k).TrialType = 0;
        depth = min(60,depth+8);
    else
        D(k).RespCode = HIT; D(k).TrialType = 0;
        depth = max(2,depth-4);
    end
    D(k).Depth = depth;
    D(k).TrialID = mod(k-1,3)+1;
end
end
