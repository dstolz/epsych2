function [code, info] = compare(study, keys, options)
% [code, info] = behavior.ScriptWriter.compare(study, keys)
% [code, info] = behavior.ScriptWriter.compare(study, keys, Name = Value)
% A script that reproduces a comparison across sessions: every session's
% analysis through behavior.Session.analyze, each checked against the values
% the study has, the thresholds table, the descriptive statistics by a facet,
% the comparison figures, and the export.
%
% The facets default to the study's (Project.Facets), so the script compares
% what the Compare tab shows. A facet that reads a column no session file
% carries -- a manual grouping, or a roster or catalog fact such as sex or
% box -- has that column written into the script as a literal, so it works
% without the project file or the roster.
%
% Parameters:
%   study      - behavior.Study holding the sessions
%   keys       - the sessions' keys, in the order the script analyses them
%   Value      - the thresholds column compared ("" = Project.Facets.Value)
%   GroupBy    - facet text for the groups ("" = Project.Facets.GroupBy)
%   ColorBy    - facet text for the colours ("" = Project.Facets.ColorBy)
%   XAxis      - facet text for the x axis of "lines" ("" = Project.Facets.XAxis)
%   Kind       - "box" | "bar" | "strip" | "lines" | "overlay" ("" =
%                Project.Facets.Kind); "lines" draws behavior.Plot.subjectLines
%                over XAxis, as the Compare tab does; every other kind
%                behavior.Plot.groupComparison
%                ("overlay" as a box, since the overlay is drawn beside it anyway)
%   ColorMap   - how the overlay colours ColorBy, a behavior.Plot.COLOR_MAPS
%                name ("" = Project.Facets.ColorMap)
%   Title, Figures, Export, OutFolder, EPsychRoot - as behavior.ScriptWriter.session
%
% Returns:
%   code, info - as behavior.ScriptWriter.session
%
% See also: behavior.ScriptWriter.session, behavior.ScriptWriter.write,
%   behavior.Facet, behavior.Stats.describe, behavior.Plot

arguments
    study (1,1) behavior.Study
    keys (1,:) string {mustBeNonempty}
    options.Value (1,1) string = ""
    options.GroupBy (1,1) string = ""
    options.ColorBy (1,1) string = ""
    options.XAxis (1,1) string = ""
    options.Kind (1,1) string = ""
    options.ColorMap (1,1) string = ""
    options.Title (1,1) string = ""
    options.Figures (1,1) logical = true
    options.Export (1,1) logical = true
    options.OutFolder (1,1) string = ""
    options.EPsychRoot (1,1) string = string(epsych_path())
end

args = namedargs2cell(options);
[code, info] = behavior.ScriptWriter.generate_(study, keys, "compare", args{:});

end
