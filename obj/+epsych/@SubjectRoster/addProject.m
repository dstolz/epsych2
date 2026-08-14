function id = addProject(self, name, options)
% id = addProject(self, name)
% id = addProject(self, name, DefaultProtocol=..., DefaultDataPath=..., Notes=...)
% id = addProject(self, name, BoxGUI=...)
% Create a project and persist it.
%
% The defaults are what make a project worth having: a new member inherits the
% project's protocol rather than making the operator browse for one.
%
% Parameters:
%   name - project name; must be filename-safe and not already in use.
%
% Options:
%   Notes           - freeform description (default '')
%   DefaultProtocol - .eprot applied to members that have no protocol memory
%   DefaultDataPath - where this project's data is saved
%   BoxGUI          - behavior GUI its sessions launch; '' inherits the session
%                     default, BOXGUI_NONE launches none
%
% Returns:
%   id - the minted ProjectID.
%
% Throws:
%   epsych:SubjectRoster:InvalidName
%   epsych:SubjectRoster:DuplicateName
%
% See also: epsych.SubjectRoster.updateProject, epsych.SubjectRoster.assign
arguments
    self
    name (1,:) char
    options.Notes (1,:) char = ''
    options.DefaultProtocol (1,:) char = ''
    options.DefaultDataPath (1,:) char = ''
    options.BoxGUI (1,:) char = ''
end

[ok, why] = epsych.SubjectRoster.isNameSafe(name);
if ~ok
    error('epsych:SubjectRoster:InvalidName', '%s', why);
end

if ~isempty(self.findProject(name))
    error('epsych:SubjectRoster:DuplicateName', ...
        'A project named "%s" already exists.', name);
end

rec = epsych.SubjectRoster.blankProject_();
rec.ProjectID       = epsych.SubjectRoster.newId('P');
rec.Name            = name;
rec.Notes           = options.Notes;
rec.DefaultProtocol = options.DefaultProtocol;
rec.DefaultDataPath = options.DefaultDataPath;
rec.BoxGUI          = options.BoxGUI;
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
