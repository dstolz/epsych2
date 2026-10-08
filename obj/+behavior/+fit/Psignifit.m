classdef (Abstract) Psignifit
    % behavior.fit.Psignifit -- the psignifit fitting engine.
    %
    % psignifit (https://github.com/wichmann-lab/psignifit; Schuett,
    % Harmeling, Macke & Wichmann 2016, Vision Research 122:105-123,
    % doi:10.1016/j.visres.2016.02.002) fits a psychometric function by
    % Bayesian inference on a grid over threshold, width, lapse rate (lambda),
    % guess rate (gamma) and overdispersion (eta). It is used when
    % behavior.Settings.Fit.Engine is "psignifit", and hands its result back
    % in the common fit schema (behavior.fit.Builtin), so the session view,
    % the tables, the exports and a generated script never ask which engine
    % made a fit.
    %
    %   L = behavior.fit.Psignifit.locate()       % found? where? which commit?
    %   behavior.fit.Psignifit.available()        % on the path now?
    %   behavior.fit.Psignifit.directions()       % how to install it, in words
    %   behavior.fit.Psignifit.setFolder('C:\src\psignifit')   % and remember it
    %
    % FINDING IT. psignifit is not a toolbox and EPsych does not ship it.
    % locate() takes, in order: psignifit already on the MATLAB path; the
    % folder named by getpref('EPsych','PsignifitPath') (read behind ispref,
    % which never creates it); a folder named psignifit (or psignifit-master/
    % -main, as GitHub's Download ZIP unpacks) BESIDE the EPsych checkout, or
    % one level further up -- the same places epsych_startup looks for
    % granary. A folder counts only if it holds the MATLAB psignifit
    % (psignifit.m and plotPsych.m; the Python package has neither). It is
    % added at the END of the path, so none of its generically named
    % functions (getThreshold, plot2D, ...) can shadow one of EPsych's.
    %
    % THE DATA. [Levels NumYes NumTotal] from
    % psychophysics.Staircase.psychometricCounts is exactly psignifit's data
    % matrix; the options are behavior.Settings.psignifitOptions(). A
    % staircase is ADAPTIVE data, which psignifit's standard priors do not
    % assume: they are set from the range of levels tested, and psignifit's
    % own advice for adaptive data is to state the range the psychometric
    % function could span instead (Settings.Psignifit.StimulusRange). Do not
    % wait for psignifit to say so -- its "probablyAdaptive" warnings test
    % numel(stimulusRange) == 1 after it has filled the range in from the
    % data, so they never fire. Every warning psignifit does raise is
    % captured into the fit's Warnings rather than printed, and a threshold
    % outside the levels tested is noted there as an extrapolation.
    %
    % THE RESULT. fromCounts maps psignifit's result.Fit = [threshold width
    % lambda gamma eta] onto the common schema: Threshold (psignifit's own
    % threshold, at ThresholdPC between the asymptotes; or getThreshold at
    % that proportion on the absolute scale), CI at Psignifit.ConfidenceLevel,
    % Alpha (the threshold parameter), Beta (the slope at the threshold,
    % getSlope), Width, Lambda, Gamma, Eta, Deviance. Log-axis sigmoids
    % (logn, weibull) report every level in stimulus units. A threshold whose
    % marginal posterior reaches the edge of the grid -- psignifit's own
    % border warning, meaning the data cannot rule out a threshold beyond it
    % -- is NOT identifiable, so Threshold is NaN and QC says fit_failed.
    % Raw keeps psignifit's result WITHOUT Posterior and weight (two 5-D
    % grids, ~100 MB each on the standard grid): everything plotPsych and
    % plotMarginal read is there; posterior(F) refits for the 2-D and Bayes
    % plots that need the whole grid.
    %
    % THE CACHE. A standard-grid fit takes seconds, so results are cached on
    % the exact data, options and psignifit commit -- in memory, and as small
    % files under behavior.Catalog.defaultCacheFolder()/psignifit, never under
    % a data root. A hit is checked against the whole input, not the hash.
    %
    % Documentation: documentation/behavior/behavior_Classes.md
    % See also: behavior.fit.Builtin, behavior.fit.PsignifitPlot,
    %   behavior.Session.fit, behavior.Settings.psignifitOptions,
    %   psychophysics.Staircase.psychometricCounts

    properties (Constant)
        URL (1,1) string = "https://github.com/wichmann-lab/psignifit"
        CLONE_URL (1,1) string = "https://github.com/wichmann-lab/psignifit.git"
        PREF_GROUP (1,:) char = 'EPsych'
        PREF_NAME (1,:) char = 'PsignifitPath'
        % psignifit's parameter order, as result.Fit and its plots number them.
        PARAMETERS (1,5) string = ["threshold" "width" "lambda" "gamma" "eta"]
        MAX_MEMORY_ENTRIES (1,1) double = 500
        MAX_CACHE_FILES (1,1) double = 5000
        % Part of every cache key: raise it when what a cache entry holds
        % changes, so an older entry is never read as a newer one.
        CACHE_FORMAT (1,1) double = 1
    end

    methods (Static)
        function L = locate(options)
            % L = behavior.fit.Psignifit.locate()
            % L = behavior.fit.Psignifit.locate(Refresh = true)
            % Where psignifit is, adding it to the path when it was found
            % somewhere other than the path. The answer is remembered; Refresh
            % searches again (after installing it, or changing the preference).
            %
            % Returns:
            %   L - struct Found (logical), Folder, Source ("path" |
            %       "preference" | "beside EPsych" | ""), Version (git commit,
            %       "" when not a git checkout), Searched (folders looked in)
            arguments
                options.Refresh (1,1) logical = false
            end
            % The remembered answer stands while the path agrees with it: a
            % psignifit added by hand is found, one removed is searched for.
            L = behavior.fit.Psignifit.state_();
            if ~options.Refresh && ~isempty(L) && L.Found == (exist('psignifit', 'file') == 2)
                return
            end
            L = behavior.fit.Psignifit.search_();
            behavior.fit.Psignifit.state_(L);
        end

        function tf = available()
            % tf = behavior.fit.Psignifit.available()
            % Whether psignifit can fit now (locate() found it).
            if behavior.fit.Psignifit.override_() == "missing"
                tf = false;
                return
            end
            L = behavior.fit.Psignifit.locate();
            tf = L.Found;
        end

        function why = whyUnavailable()
            % why = behavior.fit.Psignifit.whyUnavailable()
            % Why psignifit cannot fit, in one sentence; "" when it can.
            if behavior.fit.Psignifit.available()
                why = "";
                return
            end
            why = "psignifit is not installed: get it from " + behavior.fit.Psignifit.URL + ...
                " and put it beside the EPsych folder, or name its folder in Analysis > Settings > psignifit" + ...
                " (setpref('EPsych','PsignifitPath',<folder>)).";
        end

        function txt = directions()
            % txt = behavior.fit.Psignifit.directions()
            % How to install psignifit, as lines of text (string column) for a
            % dialog or the command window.
            here = behavior.fit.Psignifit.epsychRoot_();
            beside = fullfile(fileparts(here), 'psignifit');
            txt = [ ...
                "psignifit is a free MATLAB toolbox for Bayesian psychometric function fitting " + ...
                    "(Schuett, Harmeling, Macke & Wichmann 2016). EPsych does not ship it."
                "1. Download it from " + behavior.fit.Psignifit.URL + ...
                    " (Code > Download ZIP, then unzip), or clone it:"
                "     git clone " + behavior.fit.Psignifit.CLONE_URL
                "2. Put the folder beside the EPsych folder, as " + string(beside) + ...
                    ", where it is found automatically -- or anywhere, and choose it with Locate Folder..."
                "   (remembered as setpref('EPsych','PsignifitPath',<folder>))."];
        end

        function L = setFolder(folder, options)
            % L = behavior.fit.Psignifit.setFolder(folder)
            % L = behavior.fit.Psignifit.setFolder(folder, Remember = false)
            % Use the psignifit in this folder: checked, added to the end of
            % the path, and (Remember, the default) recorded as the
            % EPsych/PsignifitPath preference so the next session finds it.
            % Errors, changing nothing, when the folder holds no MATLAB
            % psignifit.
            arguments
                folder (1,1) string
                options.Remember (1,1) logical = true
            end
            folder = string(char(java.io.File(char(folder)).getAbsolutePath()));
            if ~behavior.fit.Psignifit.isInstall_(folder)
                error('behavior:fit:Psignifit:NotAnInstall', ...
                    ['"%s" does not hold the MATLAB psignifit (psignifit.m and plotPsych.m). ' ...
                    'Download it from %s.'], folder, behavior.fit.Psignifit.URL);
            end
            if options.Remember
                setpref(behavior.fit.Psignifit.PREF_GROUP, behavior.fit.Psignifit.PREF_NAME, char(folder));
            end
            behavior.fit.Psignifit.addToPath_(folder);
            L = behavior.fit.Psignifit.locate(Refresh = true);
            vprintf(1, 'behavior.fit.Psignifit: using psignifit in "%s"', L.Folder);
        end

        function v = version(folder)
            % v = behavior.fit.Psignifit.version()
            % v = behavior.fit.Psignifit.version(folder)
            % The git commit (7 characters) of a psignifit checkout, read from
            % its .git folder without running git; "" when it is not one (a
            % ZIP download).
            arguments
                folder (1,1) string = ""
            end
            if folder == ""
                L = behavior.fit.Psignifit.locate();
                folder = L.Folder;
            end
            v = "";
            gitDir = fullfile(folder, ".git");
            head = fullfile(gitDir, "HEAD");
            if ~isfile(head), return, end
            try
                ref = strtrim(string(fileread(head)));
                if ~startsWith(ref, "ref:")
                    v = extractBefore(ref + "       ", 8);
                    return
                end
                ref = strtrim(extractAfter(ref, "ref:"));
                loose = fullfile(gitDir, ref);
                if isfile(loose)
                    v = extractBefore(strtrim(string(fileread(loose))) + "       ", 8);
                    return
                end
                packed = fullfile(gitDir, "packed-refs");
                if isfile(packed)
                    lines = splitlines(string(fileread(packed)));
                    hit = lines(endsWith(strtrim(lines), " " + ref));
                    if ~isempty(hit)
                        v = extractBefore(hit(1) + "       ", 8);
                    end
                end
            catch ME
                vprintf(2, 'behavior.fit.Psignifit: no version for "%s": %s', folder, ME.message);
            end
            v = strtrim(v);
        end

        function F = fromCounts(levels, numYes, numTotal, o, info, options)
            % F = behavior.fit.Psignifit.fromCounts(levels, numYes, numTotal, o, info)
            % F = behavior.fit.Psignifit.fromCounts(..., UseCache = false)
            % Fit psignifit to per-level counts and return the common fit
            % schema. Never throws for data psignifit refuses: the reason goes
            % in Message. Throws behavior:fit:Psignifit:NotAvailable when
            % psignifit cannot be found.
            %
            % Parameters:
            %   levels, numYes, numTotal - per-level counts (psignifit's data
            %                              matrix, column by column)
            %   o, info  - [o, info] = settings.psignifitOptions(...)
            %   UseCache - reuse a fit of the identical input (default true)
            arguments
                levels double
                numYes double
                numTotal double
                o (1,1) struct
                info (1,1) struct
                options.UseCache (1,1) logical = true
            end
            if ~behavior.fit.Psignifit.available()
                error('behavior:fit:Psignifit:NotAvailable', '%s', behavior.fit.Psignifit.whyUnavailable());
            end
            F = behavior.fit.Builtin.empty();
            F.Engine = "psignifit";
            F.Shape = string(info.Sigmoid);
            data = [reshape(double(levels), [], 1), reshape(double(numYes), [], 1), reshape(double(numTotal), [], 1)];
            data = sortrows(data(data(:, 3) > 0, :), 1);
            F.Levels = data(:, 1)';
            F.NumYes = data(:, 2)';
            F.NumTotal = data(:, 3)';
            F.Proportion = F.NumYes ./ F.NumTotal;
            F.CI.Level = o.confP(1);

            if numel(unique(data(:, 1))) < 2
                F.Message = "A psychometric fit needs at least two distinct stimulus levels.";
                return
            end
            if any(strcmp(erase(o.sigmoidName, "neg_"), {'logn', 'weibull'})) && any(data(:, 1) <= 0)
                F.Message = "The " + erase(string(o.sigmoidName), "neg_") + ...
                    " sigmoid is fitted on a log axis and needs positive stimulus levels; choose another sigmoid.";
                return
            end

            try
                [res, warnings] = behavior.fit.Psignifit.run_(data, o, options.UseCache);
            catch ME
                F.Message = "psignifit: " + string(ME.message);
                vprintf(2, 'behavior.fit.Psignifit: %s', F.Message);
                return
            end
            F = behavior.fit.Psignifit.toCommon_(F, res, warnings, o, info);
        end

        function full = posterior(F)
            % full = behavior.fit.Psignifit.posterior(F)
            % psignifit's WHOLE result for a fit in the common schema,
            % Posterior and weight included, for the plots that marginalize
            % the grid (plot2D, plotBayes). The stored fit keeps neither, so
            % this refits from F.Raw.Input -- deterministic, so it is the same
            % fit -- and keeps the last one, since a view asks repeatedly
            % for the session in front.
            arguments
                F (1,1) struct
            end
            if ~isfield(F, 'Raw') || ~isfield(F.Raw, 'Input')
                error('behavior:fit:Psignifit:NoInput', 'This fit was not made by psignifit.');
            end
            persistent lastKey lastFull
            key = behavior.fit.Psignifit.inputText_(F.Raw.Input.data, F.Raw.Input.options);
            if ~isempty(lastKey) && lastKey == key
                full = lastFull;
                return
            end
            if ~behavior.fit.Psignifit.available()
                error('behavior:fit:Psignifit:NotAvailable', '%s', behavior.fit.Psignifit.whyUnavailable());
            end
            full = behavior.fit.Psignifit.call_(F.Raw.Input.data, F.Raw.Input.options);
            lastKey = key;
            lastFull = full;
        end

        function n = clearCache(options)
            % n = behavior.fit.Psignifit.clearCache()
            % n = behavior.fit.Psignifit.clearCache(Disk = true)
            % Forget the remembered fits (in memory; on disk too with Disk).
            % Returns how many disk files were removed.
            arguments
                options.Disk (1,1) logical = false
            end
            behavior.fit.Psignifit.memory_('clear');
            n = 0;
            if options.Disk
                folder = behavior.fit.Psignifit.cacheFolder();
                files = dir(fullfile(folder, 'fit_*.mat'));
                for k = 1:numel(files)
                    delete(fullfile(files(k).folder, files(k).name));
                end
                n = numel(files);
            end
        end

        function f = cacheFolder()
            % f = behavior.fit.Psignifit.cacheFolder()
            % Where fits are cached on disk: behavior.Catalog.defaultCacheFolder()
            % /psignifit -- per machine, never under a data root.
            f = fullfile(behavior.Catalog.defaultCacheFolder(), "psignifit");
        end

        function override(state)
            % behavior.fit.Psignifit.override("missing" | "")
            % FOR TESTS AND DEMONSTRATIONS: "missing" makes available() report
            % psignifit absent wherever it is, so the not-installed path can be
            % exercised on a machine that has it; "" restores the truth.
            arguments
                state (1,1) string {mustBeMember(state, ["" "missing"])}
            end
            behavior.fit.Psignifit.override_(state);
        end
    end

    methods (Static, Access = private)
        function L = search_()
            % The search locate() describes.
            L = struct('Found', false, 'Folder', "", 'Source', "", 'Version', "", 'Searched', strings(1, 0));

            prefFolder = "";
            if ispref(behavior.fit.Psignifit.PREF_GROUP, behavior.fit.Psignifit.PREF_NAME)
                prefFolder = string(getpref(behavior.fit.Psignifit.PREF_GROUP, behavior.fit.Psignifit.PREF_NAME));
            end
            besides = strings(1, 0);
            here = behavior.fit.Psignifit.epsychRoot_();
            if here ~= ""
                names = ["psignifit" "psignifit-master" "psignifit-main"];
                up1 = string(fileparts(here));
                up2 = string(fileparts(up1));
                besides = unique([fullfile(up1, names), fullfile(up2, names)], 'stable');
            end

            % Already on the path: that is the one MATLAB will call. It is
            % named after where it came from when this class put it there.
            w = string(which('psignifit'));
            if w ~= "" && isfile(w)
                folder = string(fileparts(w));
                if behavior.fit.Psignifit.isInstall_(folder)
                    source = "path";
                    if prefFolder ~= "" && behavior.fit.Psignifit.sameFolder_(folder, prefFolder)
                        source = "preference";
                    elseif any(behavior.fit.Psignifit.sameFolder_(folder, besides))
                        source = "beside EPsych";
                    end
                    L = behavior.fit.Psignifit.found_(L, folder, source);
                    return
                end
            end

            if prefFolder ~= ""
                L.Searched(end+1) = prefFolder;
                if behavior.fit.Psignifit.isInstall_(prefFolder)
                    behavior.fit.Psignifit.addToPath_(prefFolder);
                    L = behavior.fit.Psignifit.found_(L, prefFolder, "preference");
                    return
                end
                vprintf(1, ['behavior.fit.Psignifit: EPsych/PsignifitPath names "%s", which does not ' ...
                    'hold the MATLAB psignifit'], prefFolder);
            end

            for folder = besides
                L.Searched(end+1) = folder;
                if behavior.fit.Psignifit.isInstall_(folder)
                    behavior.fit.Psignifit.addToPath_(folder);
                    L = behavior.fit.Psignifit.found_(L, folder, "beside EPsych");
                    return
                end
            end
        end

        function tf = sameFolder_(a, b)
            % Folder names compared as Windows compares them.
            norm = @(f) lower(strip(strrep(string(f), '/', '\'), 'right', '\'));
            tf = norm(a) == norm(b);
            if ~ispc
                tf = strip(string(a), 'right', '/') == strip(string(b), 'right', '/');
            end
        end

        function L = found_(L, folder, source)
            L.Found = true;
            L.Folder = string(folder);
            L.Source = source;
            L.Version = behavior.fit.Psignifit.version(folder);
            vprintf(2, 'behavior.fit.Psignifit: psignifit %s in "%s" (%s)', L.Version, folder, source);
        end

        function tf = isInstall_(folder)
            % The MATLAB psignifit: the main function and its plots.
            tf = strlength(folder) > 0 && isfolder(folder) ...
                && isfile(fullfile(folder, "psignifit.m")) && isfile(fullfile(folder, "plotPsych.m"));
        end

        function addToPath_(folder)
            % At the END, so its generic names cannot shadow EPsych's.
            p = string(strsplit(path, pathsep));
            if ~any(strcmpi(p, folder))
                addpath(char(folder), '-end');
            end
        end

        function r = epsychRoot_()
            w = string(which('epsych_startup'));
            if w == ""
                r = "";
            else
                r = string(fileparts(w));
            end
        end

        function out = state_(L)
            % The remembered locate() answer (set with an argument).
            persistent remembered
            if nargin
                remembered = L;
            end
            out = remembered;
        end

        function out = override_(s)
            persistent state
            if isempty(state), state = ""; end
            if nargin
                state = s;
            end
            out = state;
        end

        function [res, warnings] = run_(data, o, useCache)
            % The slim psignifit result for this input, from a cache or a fit.
            ver = behavior.fit.Psignifit.version();
            inputText = behavior.fit.Psignifit.inputText_(data, o) + "|psignifit " + ver + ...
                "|cache " + behavior.fit.Psignifit.CACHE_FORMAT;
            key = "fit_" + behavior.hex8(char(inputText));
            if useCache
                entry = behavior.fit.Psignifit.memory_('get', key);
                if isempty(entry)
                    entry = behavior.fit.Psignifit.readDisk_(key);
                end
                if ~isempty(entry) && isfield(entry, 'Text') && entry.Text == inputText
                    res = entry.Result;
                    warnings = entry.Warnings;
                    behavior.fit.Psignifit.memory_('put', key, entry);
                    return
                end
            end

            [full, warnings] = behavior.fit.Psignifit.call_(data, o);
            res = rmfield(full, intersect(fieldnames(full), {'Posterior', 'weight'}));
            res.Input = struct('data', data, 'options', o);
            res.Version = ver;
            entry = struct('Text', inputText, 'Result', res, 'Warnings', warnings);
            behavior.fit.Psignifit.memory_('put', key, entry);
            behavior.fit.Psignifit.writeDisk_(key, entry);
        end

        function [res, warnings] = call_(data, o)
            % psignifit itself, its warnings captured (quiet_).
            assert(size(data, 2) == 3 && isstruct(o), 'behavior:fit:Psignifit:Input', ...
                'psignifit takes an n x 3 data matrix and an options struct.');
            [out, warnings] = behavior.fit.Psignifit.quiet_(@() psignifit(data, o), 1);
            res = out{1};
        end

        function [out, warnings] = quiet_(fcn, nout)
            % Call a psignifit function with every warning it raises captured
            % rather than printed: evalc takes the text, since a warning has
            % no other handle a caller can collect.
            assert(isa(fcn, 'function_handle') && nout >= 0, 'behavior:fit:Psignifit:Input', ...
                'quiet_ takes a function handle and an output count.');
            ws = warning('off', 'backtrace');
            restore = onCleanup(@() warning(ws));
            out = cell(1, nout);
            txt = evalc('[out{1:nout}] = fcn();');
            delete(restore);
            % One warning per "Warning: ", without a backtrace a desktop may
            % still print ("> In ...") or the "[\b ... ]\b" MATLAB marks a
            % captured warning with.
            parts = strsplit(erase(string(txt), char(8)), "Warning: ");
            parts = parts(2:end);
            for k = 1:numel(parts)
                p = parts(k);
                if contains(p, "> In ")
                    p = extractBefore(p, "> In ");
                end
                p = regexprep(p, '\s+', ' ');
                parts(k) = regexprep(p, '^[\s\[]+|[\s\]\[]+$', '');
            end
            warnings = unique(parts(strlength(parts) > 0), 'stable');
            warnings = reshape(warnings, 1, []);
        end

        function t = inputText_(data, o)
            % The input, exactly and in a fixed order: numbers at 17
            % significant digits (mat2str writes NaN and Inf), fields sorted.
            names = sort(string(fieldnames(o)));
            parts = strings(1, numel(names) + 1);
            parts(1) = "data=" + mat2str(data, 17);
            for k = 1:numel(names)
                v = o.(names(k));
                if isstring(v), v = char(v); end
                parts(k + 1) = names(k) + "=" + string(mat2str(v, 17));
            end
            t = strjoin(parts, ";");
        end

        function out = memory_(op, key, entry)
            % In-memory LRU of cache entries: 'get', 'put', 'clear'.
            persistent map order
            if isempty(map)
                map = containers.Map('KeyType', 'char', 'ValueType', 'any');
                order = strings(1, 0);
            end
            out = [];
            switch op
                case 'clear'
                    map = containers.Map('KeyType', 'char', 'ValueType', 'any');
                    order = strings(1, 0);
                case 'get'
                    if map.isKey(char(key))
                        out = map(char(key));
                    end
                case 'put'
                    map(char(key)) = entry;
                    order(order == key) = [];
                    order(end+1) = key;
                    while numel(order) > behavior.fit.Psignifit.MAX_MEMORY_ENTRIES
                        map.remove(char(order(1)));
                        order(1) = [];
                    end
            end
        end

        function entry = readDisk_(key)
            entry = [];
            file = fullfile(behavior.fit.Psignifit.cacheFolder(), key + ".mat");
            if ~isfile(file), return, end
            try
                S = load(file, 'entry');
                entry = S.entry;
            catch ME
                vprintf(2, 'behavior.fit.Psignifit: cache file "%s" unreadable: %s', file, ME.message);
            end
        end

        function writeDisk_(key, entry)
            % Best effort: a cache that cannot be written only costs time.
            try
                folder = behavior.fit.Psignifit.cacheFolder();
                if ~isfolder(folder), mkdir(folder); end
                save(fullfile(folder, key + ".mat"), 'entry');
                files = dir(fullfile(folder, 'fit_*.mat'));
                if numel(files) > behavior.fit.Psignifit.MAX_CACHE_FILES
                    [~, idx] = sort([files.datenum]);
                    drop = idx(1:numel(files) - round(0.9 * behavior.fit.Psignifit.MAX_CACHE_FILES));
                    for k = drop
                        delete(fullfile(files(k).folder, files(k).name));
                    end
                end
            catch ME
                vprintf(2, 'behavior.fit.Psignifit: fit not cached: %s', ME.message);
            end
        end

        function F = toCommon_(F, res, warnings, o, info)
            % psignifit's result in the common schema (see the class comment).
            fit = res.Fit(:);
            logspace = logical(res.options.logspace);
            if logspace
                lin = @exp;
            else
                lin = @(x) x;
            end
            ci = res.conf_Intervals(:, :, 1);

            F.Alpha = lin(fit(1));
            F.Width = fit(2);
            F.Lambda = fit(3);
            F.Gamma = fit(4);
            if isnan(F.Gamma)            % equalAsymptote: gamma is lambda
                F.Gamma = fit(3);
            end
            F.Eta = fit(5);
            F.Deviance = res.deviance;
            F.Warnings = warnings;
            F.Converged = true;          % a grid has no optimizer to fail

            % Identifiable unless the threshold's marginal posterior reaches
            % the edge of the grid: psignifit's own border test.
            m = res.marginals{1};
            w = res.marginalsW{1};
            atEdge = numel(m) > 1 && (m(1) * w(1) > .001 || m(end) * w(end) > .001);
            F.Identifiable = ~atEdge;

            msgs = strings(1, 0);
            threshold = NaN;
            lo = NaN;
            hi = NaN;
            if info.CriterionScale == "absolute"
                try
                    [out, w] = behavior.fit.Psignifit.quiet_(@() getThreshold(res, info.Criterion, false), 2);
                    threshold = out{1};
                    lo = out{2}(1, 1);
                    hi = out{2}(1, 2);
                    F.Warnings = [F.Warnings w];
                catch ME
                    msgs(end+1) = sprintf(['The function never reaches %g on the absolute scale ' ...
                        '(between %.3g and %.3g): %s'], info.Criterion, F.Gamma, 1 - F.Lambda, ME.message);
                end
            else
                threshold = lin(fit(1));
                lo = lin(ci(1, 1));
                hi = lin(ci(1, 2));
            end
            F.CI.ThresholdLo = lo;
            F.CI.ThresholdHi = hi;
            if atEdge
                msgs(end+1) = "The threshold's posterior reaches the edge of psignifit's grid: these data " + ...
                    "cannot rule out a threshold beyond the levels tested (state Psignifit.StimulusRange " + ...
                    "if the staircase could not reach it).";
            end
            if F.Identifiable && isfinite(threshold)
                F.Threshold = threshold;
                try
                    F.Beta = getSlope(res, threshold);
                catch ME
                    vprintf(2, 'behavior.fit.Psignifit: no slope: %s', ME.message);
                end
                % As the built-in engine does: kept, but said, since outside
                % the levels tested the prior places it rather than the data.
                if threshold < min(F.Levels) || threshold > max(F.Levels)
                    F.Warnings(end+1) = sprintf(['The threshold %.4g lies outside the levels tested ' ...
                        '[%.4g %.4g]: it is an extrapolation, placed by the prior more than by the data.'], ...
                        threshold, min(F.Levels), max(F.Levels));
                end
            end
            F.Message = strjoin(msgs, " ");

            % The curve, over the levels and a fifth beyond each end, in
            % stimulus units whatever axis the sigmoid lives on.
            lv = res.data(:, 1);
            if logspace
                lv = lv(lv > 0);
                span = log(max(lv)) - log(min(lv));
                x = exp(linspace(log(min(lv)) - 0.2 * span, log(max(lv)) + 0.2 * span, 200));
            else
                span = max(lv) - min(lv);
                x = linspace(min(lv) - 0.2 * span, max(lv) + 0.2 * span, 200);
            end
            F.Curve = struct('x', x, 'P', reshape(res.psiHandle(x), 1, []));

            res.GammaSource = info.GammaSource;
            res.Criterion = info.Criterion;
            res.CriterionScale = info.CriterionScale;
            F.Raw = res;
            if isfield(o, 'expType') && string(o.expType) == "YesNo" && info.GammaSource ~= "estimated" ...
                    && info.GammaSource ~= "fixed" && info.GammaSource ~= "catch"
                F.Warnings(end+1) = "Guess rate: " + info.GammaSource + ".";
            end
        end
    end
end
