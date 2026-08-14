function id = fromSubject(self, S, options)
% id = fromSubject(self, S)
% id = fromSubject(self, S, Update=true)
% Find or create the roster record matching a session subject.
%
% The reverse of toSubject: BoxID is dropped, because it belongs to the session
% the subject came from, not to the animal. An existing record is matched by
% name (case-insensitively) and returned as-is unless Update is set, so import
% never silently overwrites a curated record with a one-off session's copy.
%
% Parameters:
%   S - epsych.Subject or struct with at least a Name.
%
% Options:
%   Update       - overwrite Sex/Species/Weight/Notes on an existing match
%                  (default false)
%   ImportedFrom - provenance stamped on newly created records only
%
% Returns:
%   id - SubjectID of the found or created record.
%
% See also: epsych.SubjectRoster.toSubject, epsych.SubjectRoster.importFromConfig
arguments
    self
    S
    options.Update (1,1) logical = false
    options.ImportedFrom (1,:) char = ''
end

if isa(S, 'epsych.Subject')
    S = S.toStruct();
end

name = char(string(S.Name));
rec  = self.findSubject(name);

if ~isempty(rec)
    id = rec.SubjectID;
    if options.Update
        self.updateSubject(id, rmfield_(S, {'Name','BoxID'}));
    end
    return
end

seed = rmfield_(S, {'BoxID'});
seed.ImportedFrom = options.ImportedFrom;
id = self.addSubject(seed);

end

% -----------------------------------------------------------------------
function S = rmfield_(S, names)
% Drop fields without caring whether they were present.
present = names(isfield(S, names));
if ~isempty(present)
    S = rmfield(S, present);
end
end
