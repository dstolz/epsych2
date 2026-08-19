function id = addProject(self, name, options)
% id = addProject(self, name)
% id = addProject(self, name, DefaultProtocol=..., DefaultDataPath=..., Notes=...)
% id = addProject(self, name, BehaviorGUI=..., Links=..., Archived=...)
% id = addProject(self, name, Investigator=..., IACUCProtocol=...)
% id = addProject(self, name, SavingFcn=..., TimerPeriod=..., VideoRootDir=...)
% Create a project and persist it.
%
% The defaults are what make a project worth having: a new member inherits the
% project's protocol rather than making the operator browse for one, and the
% session settings a paradigm owns -- saving function, timer callbacks and
% period, data and recording roots, behavior GUI -- travel with the study
% instead of being re-entered on every rig it runs on. They are a template:
% assign stamps them onto the membership when a subject joins, and later
% project edits do not reach existing members (see reapplyTemplate).
%
% Parameters:
%   name - project name; must be filename-safe and not already in use.
%
% Options:
%   Notes           - freeform description (default '')
%   Investigator    - who is responsible for the study
%   IACUCProtocol   - animal-use protocol number
%   DefaultProtocol - .eprot applied to members that have no protocol memory
%   DefaultDataPath - where this project's data is saved
%   SavingFcn       - data-saving callback, SaveFcn(RUNTIME)
%   TimerStartFcn   - PsychTimer lifecycle callbacks; '' inherits the
%   TimerRunTimeFcn   ep_TimerFcn_* built-ins. Custom trial loops name
%   TimerStopFcn      theirs here so the paradigm travels with the study
%   TimerErrorFcn
%   TimerPeriod     - PsychTimer period in seconds (0.001-1); NaN inherits
%   VideoRootDir    - webcam recording root
%   IntanRootDir    - Intan RHX recording root (no spaces)
%   IntanSettingsFile - RHX .xml settings file (no spaces); a protocol that
%                     names its own still wins over this
%   BehaviorGUI     - behavior GUI its sessions launch; '' inherits the session
%                     default, BEHAVIORGUI_NONE launches none
%
% Every session-default option is optional and empty stamps "inherit the
% built-in default", so an older roster and a script that names only a
% protocol both keep working. gui.SubjectManager fills them in for a project
% made through the GUI.
%   Links           - (1,:) struct array of Label/URL records pointing at the
%                     study's logs; see makeLink. Unsafe addresses are refused
%   Archived        - hide the project from the manager's list (default false)
%
% Returns:
%   id - the minted ProjectID.
%
% Throws:
%   epsych:SubjectRoster:InvalidName
%   epsych:SubjectRoster:DuplicateName
%   epsych:SubjectRoster:UnsafeLink
%   epsych:SubjectRoster:InvalidTimerPeriod
%
% See also: epsych.SubjectRoster.updateProject, epsych.SubjectRoster.assign,
%   epsych.SubjectRoster.makeLink
arguments
    self
    name (1,:) char
    options.Notes (1,:) char = ''
    options.Investigator (1,:) char = ''
    options.IACUCProtocol (1,:) char = ''
    options.DefaultProtocol (1,:) char = ''
    options.DefaultDataPath (1,:) char = ''
    options.SavingFcn (1,:) char = ''
    options.TimerStartFcn (1,:) char = ''
    options.TimerRunTimeFcn (1,:) char = ''
    options.TimerStopFcn (1,:) char = ''
    options.TimerErrorFcn (1,:) char = ''
    options.TimerPeriod (1,1) double = NaN
    options.VideoRootDir (1,:) char = ''
    options.IntanRootDir (1,:) char = ''
    options.IntanSettingsFile (1,:) char = ''
    options.BehaviorGUI (1,:) char = ''
    options.Links = epsych.SubjectRoster.emptyLink()
    options.Archived (1,1) logical = false
end

[ok, why] = epsych.SubjectRoster.isNameSafe(name);
if ~ok
    error('epsych:SubjectRoster:InvalidName', '%s', why);
end

if ~isempty(self.findProject(name))
    error('epsych:SubjectRoster:DuplicateName', ...
        'A project named "%s" already exists.', name);
end

% NaN is the "inherit" state, so it is the one non-finite value allowed.
if ~isnan(options.TimerPeriod) && ...
        (options.TimerPeriod < 0.001 || options.TimerPeriod > 1)
    error('epsych:SubjectRoster:InvalidTimerPeriod', ...
        'TimerPeriod must be between 0.001 and 1 s, or NaN to inherit the session period.');
end

rec = epsych.SubjectRoster.blankProject_();
rec.ProjectID       = epsych.SubjectRoster.newId('P');
rec.Name            = name;
rec.Notes           = options.Notes;
rec.Investigator    = options.Investigator;
rec.IACUCProtocol   = options.IACUCProtocol;
rec.DefaultProtocol = options.DefaultProtocol;
rec.DefaultDataPath = options.DefaultDataPath;
rec.SavingFcn       = options.SavingFcn;
rec.TimerStartFcn   = options.TimerStartFcn;
rec.TimerRunTimeFcn = options.TimerRunTimeFcn;
rec.TimerStopFcn    = options.TimerStopFcn;
rec.TimerErrorFcn   = options.TimerErrorFcn;
rec.TimerPeriod     = options.TimerPeriod;
rec.VideoRootDir    = options.VideoRootDir;
rec.IntanRootDir    = options.IntanRootDir;
rec.IntanSettingsFile = options.IntanSettingsFile;
rec.BehaviorGUI     = options.BehaviorGUI;
rec.Links           = epsych.SubjectRoster.normalizeLinks_(options.Links, Validate = true);
rec.Archived        = options.Archived;
rec.Created         = datetime('now');
rec.Modified        = rec.Created;

self.mutate_(@applyAdd);

id = rec.ProjectID;
vprintf(1, 'Added project "%s".', name);

    function applyAdd(r)
        if ~isempty(r.findProject(rec.Name))
            error('epsych:SubjectRoster:DuplicateName', ...
                'A project named "%s" was just added by another session.', rec.Name);
        end
        r.Projects = [r.Projects, rec];
    end

end
