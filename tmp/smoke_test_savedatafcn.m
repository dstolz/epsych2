function smoke_test_savedatafcn()
% smoke_test_savedatafcn()
% Exercise runtime/savefcns/ep_SaveDataFcn: automatic save to the filename the
% session carries (the field gui.FilenameValidator writes), missing-folder
% creation, missing/extension-less filename fallbacks, empty-DATA and
% Preview-run skips, the failure path's crash-recovery hint, and the
% command-window report -- including running the hyperlink's own command to
% prove it loads the file into a base workspace variable.
%
%   matlab -batch "run('tmp/smoke_test_savedatafcn.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

% The report degrades to a plain path where hyperlinks do not render, so force
% them on to exercise the link itself, and put the session back afterwards.
hotlinks0 = feature('hotlinks');
restoreHotlinks = onCleanup(@() feature('hotlinks',hotlinks0));
feature('hotlinks',1);

root = fullfile(tempdir,sprintf('smoke_savedata_%s',char(datetime('now',Format='yyMMddHHmmssSSS'))));
cleanupObj = onCleanup(@() cleanupAll(root));
mkdir(root)

% 1. Saves to TRIALS.DataFilename, no dialog --------------------------------
target = fullfile(root,'SubA','SubA_session.mat');   % folder does not exist yet
R = makeRuntime('SubA',1,target,12,root);
out = evalc('ep_SaveDataFcn(R)');
assert(isfile(target),'data file should be written to TRIALS.DataFilename');
S = load(target);
assert(isequal(fieldnames(S),{'Data'}),'file should hold exactly one variable, Data');
assert(numel(S.Data) == 12,'all 12 trials should be saved');
assert(contains(out,'Saved 12 trials'),'report should state the trial count: %s',out);
assert(contains(out,target),'report should state the full path');
fprintf('PASS: automatic save to the session filename, folder created\n');

% 2. The reported hyperlink loads the file into the base workspace ----------
cmd = regexp(out,'<a href="matlab: (.*?)">','tokens','once');
assert(~isempty(cmd),'report should carry a matlab: hyperlink: %s',out);
evalin('base',cmd{1});
assert(evalin('base','exist(''Data_SubA'',''var'')') == 1, ...
    'clicking the link should create Data_SubA in the base workspace');
assert(evalin('base','numel(Data_SubA)') == 12, ...
    'the loaded variable should be the trial array itself, not the file struct');
evalin('base','clear Data_SubA')
fprintf('PASS: hyperlink command loads the data into a base workspace variable\n');

% 3. A path with a quote and a percent sign survives the link ---------------
odd = fullfile(root,'SubB',"O'Brien_100%_run");      % no extension either
R = makeRuntime('O''Brien',2,odd,3,root);
out = evalc('ep_SaveDataFcn(R)');
assert(isfile(char(odd)+".mat"),'.mat should be appended when the name lacks it');
cmd = regexp(out,'<a href="matlab: (.*?)">','tokens','once');
evalin('base',cmd{1});
assert(evalin('base','numel(Data_O_Brien)') == 3,'odd path should round trip through the link');
evalin('base','clear Data_O_Brien')
fprintf('PASS: extension appended; quoted/percent path survives the link\n');

% 4. No filename set: timestamped default under DefaultDataPath ------------
R = makeRuntime('SubC',3,'',5,root);
evalc('ep_SaveDataFcn(R)');
d = dir(fullfile(root,'SubC','SubC_*.mat'));
assert(isscalar(d),'a default timestamped file should be created (found %d)',numel(d));
fprintf('PASS: empty DataFilename falls back to the timestamped default\n');

% 5. Nothing to save, and Preview runs ------------------------------------
R = makeRuntime('SubD',4,fullfile(root,'SubD.mat'),0,root);
out = evalc('ep_SaveDataFcn(R)');
assert(~isfile(fullfile(root,'SubD.mat')),'no file for a subject with no trials');
assert(contains(out,'No trials to save'),'the skip should be reported: %s',out);

R = makeRuntime('SubE',5,fullfile(root,'SubE.mat'),7,root);
R.isTest = true;
out = evalc('ep_SaveDataFcn(R)');
assert(~isfile(fullfile(root,'SubE.mat')),'a Preview run must not write a data file');
assert(contains(out,'Preview'),'the Preview skip should be reported: %s',out);
fprintf('PASS: empty DATA and Preview runs are skipped and reported\n');

% 6. Failed save names the crash-recovery file -----------------------------
R = makeRuntime('SubF',6,fullfile(root,'SubF','no:such|name.mat'),4,root);
out = evalc('ep_SaveDataFcn(R)');
assert(contains(out,'FAILED to save'),'a failed save should say so: %s',out);
assert(contains(out,'RUNTIME_DATA_SubF.mat'),'the failure should name the crash-recovery file: %s',out);
fprintf('PASS: failed save reports the crash-recovery file\n');

fprintf('\nALL smoke_test_savedatafcn CHECKS PASSED\n');

end


function R = makeRuntime(name,boxid,filename,nTrials,root)
% Minimal stand-in for a finished session: what ep_SaveDataFcn reads.
% A plain struct, not an epsych.Runtime: the save function reads fields only,
% and a bare Runtime would try to resolve trigger parameters on TRIALS assignment.
R = struct();
R.isTest = false;
R.NSubjects = 1;
R.DefaultDataPath = root;
R.DataFile = string(fullfile(root,sprintf('RUNTIME_DATA_%s.mat',matlab.lang.makeValidName(name))));

data = struct('TrialIndex',{},'TrialID',{});
for i = 1:nTrials
    data(i).TrialIndex = i;
    data(i).TrialID = mod(i,3) + 1;
end

T = struct();
T.Subject = struct('Name',name,'BoxID',boxid);
T.DATA = data;
T.DataFilename = char(filename);
R.TRIALS = T;
end


function cleanupAll(root)
if isfolder(root)
    rmdir(root,'s');
end
end
