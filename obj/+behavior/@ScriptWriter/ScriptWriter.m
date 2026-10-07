classdef ScriptWriter
    % behavior.ScriptWriter  A plain MATLAB script that reproduces an analysis exactly.
    %
    % An analysis made in epsych.BehaviorAnalysis is the sum of things that are
    % easy to lose track of: which sessions were in it, the trial window of
    % each, every setting in force, and which parameter was tracked.
    % ScriptWriter writes all of it down as one script that needs nothing but
    % EPsych and the data, so the analysis can be re-run, read, reviewed, or
    % handed to someone without the GUI:
    %
    %   code = behavior.ScriptWriter.session(study, key);      % one session
    %   code = behavior.ScriptWriter.compare(study, keys);     % a comparison
    %   file = behavior.ScriptWriter.write("replicate.m", code);
    %   run(file)
    %
    % EXACT, NOT APPROXIMATE. Every value goes through literal(), whose text
    % evaluates back to a value isequaln to the one written: doubles in the
    % shortest decimal that round-trips (never more than %.17g), NaN/Inf/-Inf/
    % -0, empties at their sizes, text with every character it holds,
    % datetimes to the last digit of their sub-millisecond part and in their
    % zone, structs, cells, tables. A value that cannot be written down
    % (a function handle, a graphics object) throws rather than becoming
    % something else.
    %
    % THE SCRIPT, in order (each part a %% section): a header naming what it
    % reproduces and what wrote it; setup, with EPSYCHROOT, ROOT and OUTFOLDER
    % assigned only when not already defined so a caller can set them and
    % run(file); the settings, every property written as a literal and an
    % assertion that they still hash to the value the results were made with;
    % per session the load by key, behavior.Session.analyze with the
    % session's trial window -- the very call the window makes, so the script
    % cannot compute a result some other way -- and a check against the values
    % recorded when the script was written; the tables (and for a comparison,
    % the columns its facets read that no file carries, and the descriptive
    % statistics); the figures; the export; for a comparison a count of the
    % sessions that replicated; and the local functions. It opens no window
    % unless figures are asked for, reads or writes no MATLAB preference, and
    % touches no project file.
    %
    % See also: behavior.Session, behavior.Settings, behavior.Export,
    %   behavior.Study

    properties (Constant)
        % Characters per line before a long literal is continued with "...".
        LineWidth = 96
    end

    methods (Static)
        txt = literal(v, options)
        lines = checkFunction()
        [code, info] = session(study, key, options)
        [code, info] = compare(study, keys, options)
        file = write(file, code)
    end

    methods (Static, Access = private)
        [code, info] = generate_(study, keys, kind, options)
    end
end
