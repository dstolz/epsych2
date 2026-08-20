function capture_review_screenshot(outDir)
% capture_review_screenshot(outDir)
% Run a short session, review it, and export pictures of the review window and
% its transport. Visual confirmation that a reviewed session looks like a
% finished one; not part of any test.
%
% Run under -batch: exportapp needs a real figure and the MCP server's Live
% Editor figure manager interferes.
%   matlab -batch "run('c:\src\epsych2\tmp\capture_review_screenshot.m')"

arguments
    outDir (1,:) char = ''
end

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(fullfile(here, '..', 'examples', 'detection_task'));

if isempty(outDir)
    outDir = fullfile(tempdir, 'review_shots');
end
if ~isfolder(outDir), mkdir(outDir); end

scratch = fullfile(tempdir, sprintf('review_shot_%d', feature('getpid')));
if isfolder(scratch), rmdir(scratch, 's'); end
mkdir(scratch);

% --- a real session, with the example's simulated observer ---------------
% Not a forced-trial loop: that never produces a response, so every trial
% scores Undefined and the review would show a session with no behaviour in it.
run_detection_session(NumTrials = 150, ShowGUI = false, ...
    DataPath = scratch, Seed = 7);

d = dir(fullfile(scratch, '*.mat'));
[~, newest] = max([d.datenum]);
sessionFile = fullfile(d(newest).folder, d(newest).name);
fprintf('session file: %s\n', sessionFile);

% --- review it -----------------------------------------------------------
V = epsych.ReviewSession(sessionFile, BehaviorGUI = 'DetectionBehaviorGUI');
drawnow; pause(1); drawnow

exportapp(V.GUI.h_figure,   fullfile(outDir, 'review_behaviorgui.png'));
exportapp(V.Transport.h_figure, fullfile(outDir, 'review_transport.png'));

% ...and part-way through, to show the scrubber working
V.seek(20);
drawnow; pause(0.5); drawnow
exportapp(V.GUI.h_figure, fullfile(outDir, 'review_behaviorgui_trial20.png'));

fprintf('wrote screenshots to %s\n', outDir);

delete(V);
try, rmdir(scratch, 's'); catch, end
end
