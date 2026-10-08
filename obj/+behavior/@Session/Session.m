classdef Session < handle
    % sess = behavior.Session.load(file)
    % sess = behavior.Session.load(catalogRow)
    % One saved session, loaded, and everything the offline analysis does to it.
    %
    % A Session holds a session's trial records (Data) and normalized
    % snapshot, together with what the data root says about it -- key,
    % project, subject, filename tags -- and turns it into analysis objects
    % configured by a behavior.Settings:
    %
    %   sess = behavior.Session.load(c.session(key));    % from a Catalog row
    %   s = behavior.Settings(Window = "20+");
    %   S = sess.staircase(s);           % a configured psychophysics.Staircase
    %   F = sess.fit(S, s);              % the common fit struct
    %   R = sess.analyze(s);             % everything, as one result struct
    %
    % ONE EXCLUSION RULE. Which trials an analysis uses -- the trial window,
    % test (Preview) trials, excluded trial types -- is decided by
    % exclusionMask alone, and the browser, the analysis and a generated
    % script all call it, so the three cannot drift apart.
    %
    % ONE CANDIDATE RULE. Which fields could be the staircase parameter is
    % decided by candidates alone; behavior.Catalog's scan calls it too.
    %
    % ANALYZE NEVER THROWS for a bad session. A file that could not be read,
    % a parameter the file lacks, a window that selects nothing, or a fit
    % that cannot be identified gives a result whose numbers are NaN and
    % whose Messages say why, plus QC flags: a batch over a thousand files
    % must not stop at the first odd one.
    %
    % Loading goes through epsych.SessionFiles.summarize -- the same single
    % load the catalog's scan makes -- so a saved .mat, a crash-recovery
    % seed (data_NNNN assembled in NUMERIC order) and an .epj journal are all
    % read the same way, warnings held back while loading, and the records
    % are the same filled records the catalog counted.
    %
    % Properties (read-only):
    %   Key           - path relative to Root, "/" separated
    %   File          - absolute file name
    %   Root          - data root ("" when loaded from a path without one)
    %   Project, ProjectPath, Subject, Tags, Collision, Start - as
    %                   behavior.Catalog reports them
    %   Data          - (1,n) trial records
    %   Snapshot      - normalized epsych.SessionSnapshot
    %   Row           - the Catalog row it was loaded from (empty table for
    %                   a bare path)
    %   Fields        - (1,:) string, the records' fields
    %   Candidates    - table Field/Class/NumUnique/IsParameter
    %   ParameterMeta - table Field/Name/Unit/Min/Max/Type/Interface/Module
    %   QCFile        - (1,:) string, file-level QC flags
    %   Error         - why the file could not be read ("" when it could)
    %
    % Documentation: documentation/behavior/behavior_Classes.md
    % See also: behavior.Catalog, behavior.Settings, psychophysics.Staircase,
    %   psychophysics.SessionMetrics, behavior.fit.Builtin

    properties (SetAccess = private)
        Key (1,1) string = ""
        File (1,1) string = ""
        Root (1,1) string = ""
        Project (1,1) string = ""
        ProjectPath (1,1) string = ""
        Subject (1,1) string = ""
        Tags (1,:) string = strings(1, 0)
        Collision (1,1) string = ""
        Start (1,1) datetime = NaT
        Data struct = struct([])
        Snapshot struct = struct([])
        Row table = table()
        Fields (1,:) string = strings(1, 0)
        Candidates table = table()
        ParameterMeta table = table()
        QCFile (1,:) string = strings(1, 0)
        Error (1,1) string = ""
    end

    methods
        m = parameterMeta(sess, field)
        [field, auto] = resolveParameter(sess, settings)
        S = staircase(sess, settings, options)
        [F, job] = fit(sess, S, settings, options)
        [R, job] = analyze(sess, settings, options)
    end

    methods (Static)
        sess = load(fileOrRow, options)
        [excl, info] = exclusionMask(Data, options)
        C = candidates(Data, ParameterMeta)
        P = parameterTable(protocol)
    end

    methods (Access = private)
        flags = qc_(sess, R, settings, noParameter, ranStaircase)
    end

    methods (Static, Access = private)
        function tt = trialTypes_(Data)
            % tt = trialTypes_(Data)
            % Each record's trial type as a (1,n) double: the TrialType field
            % where a record has one, else the lowest TrialType_k bit of its
            % RespCode, NaN when neither says.
            Data = reshape(Data, 1, []);
            n = numel(Data);
            fields = behavior.Session.fieldsOf_(Data);
            rc = behavior.Session.numeric_(Data, "RespCode", fields);
            tt = behavior.Session.numeric_(Data, "TrialType", fields);

            scored = ~isnan(rc);
            fromBits = nan(n, 1);
            if any(scored)
                M = epsych.BitMask.decode(rc(scored));
                idx = find(scored);
                for k = 0:5
                    hit = M.(sprintf('TrialType_%d', k));
                    fromBits(idx(hit & isnan(fromBits(idx)))) = k;
                end
            end
            tt(isnan(tt)) = fromBits(isnan(tt));
            tt = reshape(tt, 1, []);
        end

        function f = fieldsOf_(Data)
            if isstruct(Data)
                f = reshape(string(fieldnames(Data)), 1, []);
            else
                f = strings(1, 0);
            end
        end

        function [v, cls] = numeric_(Data, f, fields)
            % [v, cls] = numeric_(Data, f, fields)
            % A field as a column of doubles, NaN where a record's value is
            % empty or not a numeric/logical scalar. cls is the class of the
            % first usable value, or "" when the field is absent or some
            % record holds something that is not a numeric scalar (a
            % vector, text, a struct): such a field cannot be a staircase
            % level or a response code.
            n = numel(Data);
            v = nan(n, 1);
            cls = "";
            if ~ismember(f, fields), return, end

            usable = true;
            for k = 1:n
                val = Data(k).(f);
                if isempty(val), continue, end
                if (isnumeric(val) || islogical(val)) && isscalar(val)
                    v(k) = double(val);
                    if cls == "", cls = string(class(val)); end
                else
                    usable = false;
                end
            end
            if ~usable, cls = ""; end
        end
    end
end
