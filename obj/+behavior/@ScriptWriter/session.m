function [code, info] = session(study, key, options)
% [code, info] = behavior.ScriptWriter.session(study, key)
% [code, info] = behavior.ScriptWriter.session(study, key, Name = Value)
% A script that reproduces one session's analysis exactly as the study has it:
% the same file, trial window and settings, through the same
% behavior.Session.analyze call, and a check that it gets the same numbers.
%
% Parameters:
%   study      - behavior.Study holding the session
%   key        - the session's key (behavior.Catalog.keyFor)
%   Title      - first line of the header (default "Replicate: <subject>
%                <start> <tags>")
%   Figures    - draw the staircase and the psychometric fit (default true)
%   Export     - write the tables to OUTFOLDER (default true)
%   OutFolder  - the export folder the script assumes when OUTFOLDER is not
%                already defined; "" (default) = a new time-stamped folder
%                under tempdir, named when the script runs
%   EPsychRoot - the EPsych checkout the script puts on the path (default
%                this one), written as a literal so a moved toolbox is one edit
%
% Returns:
%   code - cellstr, one line of MATLAB source each (behavior.ScriptWriter.write)
%   info - struct Kind, Keys, SettingsHash, Expected (the values the script
%          checks, one struct per key), Title, NumLines
%
% See also: behavior.ScriptWriter.compare, behavior.ScriptWriter.write

arguments
    study (1,1) behavior.Study
    key (1,1) string
    options.Title (1,1) string = ""
    options.Figures (1,1) logical = true
    options.Export (1,1) logical = true
    options.OutFolder (1,1) string = ""
    options.EPsychRoot (1,1) string = string(epsych_path())
end

args = namedargs2cell(options);
[code, info] = behavior.ScriptWriter.generate_(study, key, "session", args{:});

end
