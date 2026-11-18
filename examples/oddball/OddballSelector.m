classdef OddballSelector < epsych.TrialSelector
    % OddballSelector  Trial selector for the auditory oddball example.
    %
    % Builds the stream as RUNS: each run is RunLength standards followed by
    % one deviant. Three epsych.BlockSequence objects drive it, so every
    % choice is block-randomized -- balanced within each block rather than
    % merely on average:
    %
    %   RunSequence      - run lengths, drawn from MinStandards:MaxStandards
    %   StandardSequence - which standard .wav, drawn from StandardFiles
    %   DeviantSequence  - which deviant .wav, drawn from DeviantFiles
    %
    % A block of the run-length sequence is one shuffle of every allowed
    % length, so with the defaults (1..6) every six deviants arrive after
    % exactly one run of each length; a block of a bank is one shuffle of its
    % files, so every sound is played once before any is played twice.
    %
    % EVERY DECISION IS A FUNCTION OF THE TRIAL INDEX. The caller owns the
    % index (see epsych.BlockSequence): trial k falls in run r where the
    % cumulative run ends first reach k, is the deviant iff it is the last
    % trial of that run, and is standard number k-(r-1) or deviant number r.
    % Nothing is advanced by a call, so a second selection for the same trial
    % -- gui.components.RegenerateTrial with Reselect -- returns the same
    % sound rather than skipping one, and the sequence can be rewound.
    %
    % The choice is RECORDED, not just made. Before each trial is dispatched
    % the selector writes four read-back parameters, which ep_TimerFcn_RunTime
    % then collects into the trial's DATA record: StimFile (the .wav played),
    % StimID (its position in its bank), RunLength and RunPosition. The
    % behavior GUI plays StimFile.
    %
    % LIVE EDITS. MinStandards and MaxStandards are read from the trial table
    % at every selection, the banks from the StandardFiles/DeviantFiles
    % parameters. A change reaches the matching sequence, and BlockSequence's
    % edit rules apply: what was already delivered is frozen, a same-length
    % bank replacement keeps the shuffled order, and anything else takes
    % effect from the NEXT WHOLE BLOCK -- a half-old, half-new block would
    % break the balance guarantee silently. The run in progress always
    % finishes at the length it started with.
    %
    % The sequences' seeds are written into the session notes, so they are
    % in every saved data file; sequenceRecord returns the whole sequences
    % for a saving function that wants them.
    %
    % A protocol opts in with P.setOption('trialFunc', 'OddballSelector'),
    % and must declare a TrialType parameter with at least one row of 0
    % (deviant) and one of 1 (standard).
    %
    % See also epsych.TrialSelector, epsych.BlockSequence,
    %   create_oddball_protocol, OddballBehaviorGUI

    properties
        % Seed for all three sequences, for a reproducible stream. Negative
        % (the default) draws fresh seeds -- one fixed seed would give every
        % session the same stream. Takes effect when the sequences are built.
        Seed (1,1) double = -1
    end

    properties (SetAccess = private)
        RunSequence      = []   % epsych.BlockSequence over MinStandards:MaxStandards
        StandardSequence = []   % epsych.BlockSequence over the standard bank
        DeviantSequence  = []   % epsych.BlockSequence over the deviant bank

        % What the most recent selection decided: TrialIndex, IsDeviant,
        % Run, RunLength, RunPosition, Ordinal (standard or deviant number),
        % StimFile, StimID.
        LastPlan = struct([])
    end

    properties (Access = private)
        deviantRows_  (1,:) double = []
        standardRows_ (1,:) double = []
        minCol_ (1,1) double = 0
        maxCol_ (1,1) double = 0

        % Last trial index of each run handed out so far. Those runs are
        % committed in RunSequence, hence frozen, so the cache stays valid
        % across an edit of the range.
        runEnds_ (1,:) double = []

        % Index used when TRIALS carries no TrialIndex (epsych.SelfTest's
        % dry run hands the same snapshot over and over).
        drawCount_ (1,1) double = 0

        params_ = struct()            % resolved hw.Parameter handles
        paramsResolved_ (1,1) logical = false
        seedsNoted_ (1,1) logical = false
        warnedNoBank_ (1,1) logical = false
    end

    properties (Constant, Access = private)
        PARAM_NAMES = {'StandardFiles', 'DeviantFiles', ...
            'StimFile', 'StimID', 'RunLength', 'RunPosition'}
    end

    methods
        function initialize(obj, TRIALS)
            % initialize(obj, TRIALS)
            % Index the compiled condition list. The banks are not read here:
            % they are invisible parameters, absent from TRIALS, and the
            % runtime handle that can find them arrives with setRuntime.
            obj.indexTable_(TRIALS);
            obj.runEnds_   = [];
            obj.drawCount_ = 0;
            obj.LastPlan   = struct([]);
            obj.RunSequence = epsych.BlockSequence(obj.runLengthValues_(TRIALS), ...
                Seed = obj.Seed, Label = "RunLength");
            obj.RunSequence.validate(); % fail at run start, not at trial 1
            obj.StandardSequence = [];
            obj.DeviantSequence  = [];
            obj.paramsResolved_ = false;
            obj.seedsNoted_     = false;
        end

        function nextTrialID = selectNext(obj, TRIALS)
            % nextTrialID = selectNext(obj, TRIALS)
            % Decide trial TRIALS.TrialIndex, record the decision in the
            % read-back parameters, and return the matching condition row.
            k = obj.trialIndex_(TRIALS);

            obj.syncRunLengths_(TRIALS);
            obj.syncBanks_();

            plan = obj.plan_(k);
            if plan.IsDeviant
                rows = obj.deviantRows_;
            else
                rows = obj.standardRows_;
            end
            % Normally one row of each kind. A protocol that crosses
            % TrialType with something else gets those rows in rotation --
            % by ordinal, so a repeated selection still lands on the same one.
            nextTrialID = rows(mod(plan.Ordinal - 1, numel(rows)) + 1);

            obj.publish_(plan);
            obj.LastPlan = plan;
            obj.noteSeeds_();

            vprintf(3, 'Oddball trial %d: %s %d of run %d (length %d), %s', ...
                k, ternary_(plan.IsDeviant, 'deviant', 'standard'), plan.RunPosition, ...
                plan.Run, plan.RunLength, plan.StimFile)
        end

        function onRecompile(obj, TRIALS)
            % onRecompile(obj, TRIALS)
            % A recompile may move or add rows and columns; the sequences and
            % the trial-index bookkeeping carry on untouched.
            obj.indexTable_(TRIALS);
        end

        function S = sequenceRecord(obj)
            % S = sequenceRecord(obj)
            % The three sequences -- configuration, seed, and everything
            % generated -- for a saving function that wants the run to be
            % reconstructible from the file alone. Empty fields for a
            % sequence never built (a bank the session never read).
            S = struct('RunLength', [], 'Standards', [], 'Deviants', []);
            if ~isempty(obj.RunSequence),      S.RunLength = obj.RunSequence.toStruct();      end
            if ~isempty(obj.StandardSequence), S.Standards = obj.StandardSequence.toStruct(); end
            if ~isempty(obj.DeviantSequence),  S.Deviants  = obj.DeviantSequence.toStruct();  end
        end

        function plan = preview(obj, k)
            % plan = preview(obj, k)
            % What trial k is or will be -- the same struct as LastPlan --
            % without writing any parameter. Looking ahead commits the run
            % lengths up to trial k, so a later edit of the range then takes
            % effect after those runs.
            arguments
                obj
                k (1,1) double {mustBeInteger, mustBePositive}
            end
            plan = obj.plan_(k);
        end
    end

    methods (Access = private)
        function indexTable_(obj, TRIALS)
            assert(isfield(TRIALS.writeParamIdx, 'TrialType'), ...
                '%s requires a TrialType parameter in the protocol.', class(obj))
            types = cell2mat(TRIALS.trials(:, TRIALS.writeParamIdx.TrialType));
            obj.deviantRows_  = find(types == 0).';
            obj.standardRows_ = find(types == 1).';
            assert(~isempty(obj.deviantRows_) && ~isempty(obj.standardRows_), ...
                ['%s needs at least one deviant (TrialType 0) and one standard ' ...
                '(TrialType 1) condition.'], class(obj))

            obj.minCol_ = 0;
            obj.maxCol_ = 0;
            if isfield(TRIALS.writeParamIdx, 'MinStandards')
                obj.minCol_ = TRIALS.writeParamIdx.MinStandards;
            end
            if isfield(TRIALS.writeParamIdx, 'MaxStandards')
                obj.maxCol_ = TRIALS.writeParamIdx.MaxStandards;
            end
        end

        function k = trialIndex_(obj, TRIALS)
            k = [];
            if isfield(TRIALS, 'TrialIndex'), k = TRIALS.TrialIndex; end
            if isscalar(k) && isfinite(k) && k >= 1 && mod(k, 1) == 0
                obj.drawCount_ = k;
            else
                obj.drawCount_ = obj.drawCount_ + 1;
                k = obj.drawCount_;
            end
        end

        function v = runLengthValues_(obj, TRIALS)
            % MinStandards:MaxStandards as the trial table holds them now --
            % the table, not the parameter, because the table is what the
            % next dispatch writes and what an Update commit changes. A
            % protocol without the two columns gets the example's 1..6.
            lo = 1; hi = 6;
            if obj.minCol_ > 0, lo = double(TRIALS.trials{1, obj.minCol_}); end
            if obj.maxCol_ > 0, hi = double(TRIALS.trials{1, obj.maxCol_}); end
            lo = max(round(lo), 0);
            hi = max(round(hi), 0);
            if lo > hi
                vprintf(1, '%s: MinStandards %d exceeds MaxStandards %d; using %d..%d', ...
                    class(obj), lo, hi, hi, lo)
                [lo, hi] = deal(hi, lo);
            end
            v = lo:hi;
        end

        function syncRunLengths_(obj, TRIALS)
            v = obj.runLengthValues_(TRIALS);
            if ~isequal(v, obj.RunSequence.Values)
                vprintf(1, '%s: standards before a deviant now %d..%d (from the next block of runs)', ...
                    class(obj), v(1), v(end))
                obj.RunSequence.Values = v;
            end
        end

        function syncBanks_(obj)
            obj.resolveParams_();
            obj.StandardSequence = obj.syncBank_(obj.StandardSequence, 'StandardFiles', "Standards");
            obj.DeviantSequence  = obj.syncBank_(obj.DeviantSequence,  'DeviantFiles',  "Deviants");
        end

        function seq = syncBank_(obj, seq, name, label)
            if ~isfield(obj.params_, name), return; end
            files = OddballSelector.bankFiles(obj.params_.(name));
            if isempty(files)
                if ~obj.warnedNoBank_
                    vprintf(0, 1, '%s: %s is empty; those trials will play nothing', class(obj), name)
                    obj.warnedNoBank_ = true;
                end
                return
            end
            if isempty(seq)
                seq = epsych.BlockSequence(files, Seed = obj.seedFor_(label), Label = label);
                seq.validate();
            elseif ~isequal(files, seq.Values)
                vprintf(1, '%s: %s bank now %d file(s)', class(obj), label, numel(files))
                seq.Values = files;
            end
        end

        function s = seedFor_(obj, label)
            % One stated seed, three distinct but reproducible streams.
            s = obj.Seed;
            if s < 0, return; end
            switch label
                case "Standards", s = s + 1;
                case "Deviants",  s = s + 2;
            end
        end

        function resolveParams_(obj)
            % Lazily, because the runtime handle arrives after initialize, and
            % only once: the handles do not change during a session.
            if obj.paramsResolved_ || isempty(obj.runtime_), return; end
            try
                for k = 1:numel(obj.PARAM_NAMES)
                    n = obj.PARAM_NAMES{k};
                    p = obj.runtime_.find_parameter(n, includeInvisible = true, ...
                        silenceParameterNotFound = true);
                    if ~isempty(p), obj.params_.(n) = p(1); end
                end
            catch ME
                vprintf(2, '%s: could not resolve parameters (%s)', class(obj), ME.message)
                return
            end
            obj.paramsResolved_ = true;
        end

        function plan = plan_(obj, k)
            % Locate trial k among the runs, generating (and committing) run
            % lengths only as far as the run that contains it.
            ends = obj.runEnds_;
            r = find(ends >= k, 1);
            if isempty(r)
                r = numel(ends);
                S = 0;
                if r > 0, S = ends(r); end
                while true
                    r = r + 1;
                    L = obj.RunSequence.valueAt(r);
                    ends(r) = S + L + 1;
                    if k <= ends(r), break; end
                    S = ends(r);
                end
                obj.runEnds_ = ends;
            end
            first = 1;
            if r > 1, first = ends(r-1) + 1; end

            plan = struct();
            plan.TrialIndex  = k;
            plan.Run         = r;
            plan.RunLength   = ends(r) - first;   % standards in this run
            plan.RunPosition = k - first + 1;     % 1..RunLength+1
            plan.IsDeviant   = plan.RunPosition == plan.RunLength + 1;
            if plan.IsDeviant
                plan.Ordinal = r;                 % deviant number r
                seq = obj.DeviantSequence;
            else
                plan.Ordinal = k - (r - 1);       % standards so far, this one included
                seq = obj.StandardSequence;
            end

            plan.StimFile = '';
            plan.StimID   = 0;
            if ~isempty(seq)
                [f, info] = seq.valueAt(plan.Ordinal); % a 1x1 cell for a cellstr pool
                plan.StimFile = char(string(f));
                plan.StimID   = info.ValueIndex;
            end
        end

        function publish_(obj, plan)
            % Write the decision into the read-back parameters, which become
            % this trial's DATA fields when it completes.
            if ~obj.paramsResolved_, return; end
            OddballSelector.setReadParameter_(obj.params_, 'StimFile',    plan.StimFile);
            OddballSelector.setReadParameter_(obj.params_, 'StimID',      plan.StimID);
            OddballSelector.setReadParameter_(obj.params_, 'RunLength',   plan.RunLength);
            OddballSelector.setReadParameter_(obj.params_, 'RunPosition', plan.RunPosition);
        end

        function noteSeeds_(obj)
            % Once per session, and only once both banks are in hand: the
            % seeds are what make the stream replayable, so they go where
            % every saving function already writes -- the session notes.
            if obj.seedsNoted_ || isempty(obj.runtime_) ...
                    || isempty(obj.StandardSequence) || isempty(obj.DeviantSequence)
                return
            end
            obj.seedsNoted_ = true;
            epsych.SessionNotes.log(obj.runtime_, ...
                'Oddball sequence seeds: run length %d, standards %d, deviants %d', ...
                obj.RunSequence.Seed, obj.StandardSequence.Seed, obj.DeviantSequence.Seed);
        end
    end

    methods (Static)
        function files = bankFiles(p)
            % files = OddballSelector.bankFiles(p)
            % A bank parameter's file list as a cellstr row, whatever shape
            % it was stored in: the current Value, else the design-time level
            % (an invisible parameter is never dispatched, so a protocol
            % loaded by hand may carry only Values).
            v = p.Value;
            if isempty(v) && ~isempty(p.Values), v = p.Values{1}; end
            if iscell(v) && isscalar(v) && iscell(v{1}), v = v{1}; end
            if isempty(v)
                files = {};
                return
            end
            files = cellstr(string(v));
            files = files(~cellfun(@isempty, files));
            files = reshape(files, 1, []);
        end
    end

    methods (Static, Access = private)
        function setReadParameter_(params, name, val)
            % A Read parameter refuses set.Value, which is what keeps the
            % runtime from dispatching it. The rig (here, this selector and
            % the behavior GUI) is the one writer it has, so widen access for
            % the write and restore it.
            if ~isfield(params, name), return; end
            p = params.(name);
            ac = p.Access;
            p.Access = 'Any';
            try
                p.Value = val;
            catch ME
                vprintf(0, 1, 'OddballSelector: could not record %s (%s)', name, ME.message)
            end
            p.Access = ac;
        end
    end
end


function out = ternary_(cond, a, b)
if cond, out = a; else, out = b; end
end
