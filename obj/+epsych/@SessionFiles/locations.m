function L = locations(subjectName, options)
% L = epsych.SessionFiles.locations(subjectName)
% L = epsych.SessionFiles.locations(subjectName, Roster = R, RunExpt = X)
% Every place this subject's session files can be, ready for scan().
%
% A session is saved under whichever data path was in force when it ran, and
% that has moved over the toolbox's life: the rig's preference, then a
% project's session defaults, then one membership's. Nothing in a session
% records which, so this collects them all -- the same roots
% epsych.SubjectRoster's rename check searches, plus the session window's
% current one. A root that does not exist is kept; scan() reports it as
% missing, which is how an unmounted share shows up rather than looking like a
% subject with no sessions.
%
% Parameters:
%   subjectName - The subject's current Name.
%   Roster      - epsych.SubjectRoster to take project and membership paths,
%                 and former names, from. [] skips them.
%   RunExpt     - epsych.RunExpt whose data path and recording root to add.
%
% Returns:
%   L - Struct:
%         Names       - subjectName, then its NameHistory
%         Roots       - data roots, each at most once, in the order found
%         VideoRoots  - recording roots
%         RecoveryDir - the crash-recovery folder ep_TimerFcn_Start writes to
%
% See also: epsych.SessionFiles.scan, epsych.SubjectRoster.renameBlocker_

arguments
    subjectName (1,1) string
    options.Roster = []
    options.RunExpt = []
end

names = subjectName;
roots = string.empty(1,0);
video = string.empty(1,0);

% The rig's own defaults, which RunExpt starts every session from. Read behind
% ispref because getpref(group, pref, default) CREATES a missing preference: an
% empty DataPath planted here would replace RunExpt's fallback to cd.
if ispref('RunExpt', 'DataPath')
    roots(end+1) = string(getpref('RunExpt', 'DataPath'));
end
if ispref('ep_RunExpt_Video', 'RecordingRootDir')
    video(end+1) = string(getpref('ep_RunExpt_Video', 'RecordingRootDir'));
end

rx = options.RunExpt;
hasRunExpt = ~isempty(rx) && isa(rx, 'epsych.RunExpt') && isvalid(rx);
if hasRunExpt
    roots(end+1) = string(rx.DefaultDataPath);
    video(end+1) = string(rx.PATHS.VideoRootDir);
end

R = options.Roster;
if ~isempty(R) && isa(R, 'epsych.SubjectRoster') && isvalid(R)
    s = R.findSubject(char(subjectName));
    if ~isempty(s)
        names = [names, reshape(string(s.NameHistory), 1, [])];

        M = R.Memberships;
        if ~isempty(M)
            M = M(strcmp({M.SubjectID}, s.SubjectID));
            roots = [roots, reshape(string({M.DefaultDataPath}), 1, [])];
            video = [video, reshape(string({M.VideoRootDir}), 1, [])];
        end

        P = R.projectsForSubject(s.SubjectID);
        if ~isempty(P)
            roots = [roots, reshape(string({P.DefaultDataPath}), 1, [])];
            video = [video, reshape(string({P.VideoRootDir}), 1, [])];
        end
    end
end

L.Names = epsych.SessionFiles.uniquePaths_(names);
L.Roots = epsych.SessionFiles.uniquePaths_(roots);
L.VideoRoots = epsych.SessionFiles.uniquePaths_(video);

% Where ep_TimerFcn_Start writes the recovery seed: the runtime's TempDataDir
% when a session set one, otherwise the default ExptDispatch gives it.
L.RecoveryDir = string(fullfile(fileparts(EPsychInfo.root), 'DATA'));
if hasRunExpt
    t = string(rx.RUNTIME.TempDataDir);
    if strlength(t) > 0 && isfolder(t)
        L.RecoveryDir = t;
    end
end

end
