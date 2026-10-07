function applyRoster(obj, roster)
% applyRoster(obj)
% applyRoster(obj, roster)
% Enrich the Subjects table from the subject roster: whether each subject is
% known to it (by its current or a former name), its sex, species and
% projects there, the protocol it last ran, and whether it is retired.
%
% The roster only ENRICHES: the folder tree still decides who the subjects
% are, and the roster is never written. With no roster configured, or one
% that cannot be read, the columns are still added -- every subject unknown
% -- so a caller never has to test for them. Later scans keep the columns,
% re-applied from the same roster.
%
% Parameters:
%   roster - An epsych.SubjectRoster, a path to an .esub file, or [] for the
%            one this workstation is configured with
%            (epsych.SubjectRoster.configuredFile). Default [].
%
% See also: epsych.SubjectRoster, behavior.Catalog.scan

arguments
    obj
    roster = []
end

R = [];
if isa(roster, 'epsych.SubjectRoster')
    R = roster;
    file = string(R.FilePath);
else
    if isempty(roster)
        % configuredFile reads the preference behind ispref: a bare
        % getpref(group, pref, default) would create it.
        file = string(epsych.SubjectRoster.configuredFile());
    else
        file = string(roster);
    end
    if file ~= "" && isfile(file)
        R = epsych.SubjectRoster(char(file));
        if R.LoadError ~= ""
            vprintf(1, 'behavior.Catalog: the subject roster "%s" could not be read: %s', file, R.LoadError)
        end
    elseif file ~= ""
        vprintf(1, 'behavior.Catalog: no subject roster at "%s"; subjects are not enriched', file)
    else
        vprintf(2, 'behavior.Catalog: no subject roster is configured; subjects are not enriched')
    end
end

base = obj.Subjects(:, ~startsWith(obj.Subjects.Properties.VariableNames, "Roster"));
obj.Subjects = behavior.Catalog.rosterColumns_(base, R);
obj.Roster = R;
obj.RosterFile = file;
obj.RosterApplied_ = true;

end
