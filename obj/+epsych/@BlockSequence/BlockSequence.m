classdef BlockSequence < handle
    % s = epsych.BlockSequence(values)
    % s = epsych.BlockSequence(values, Name=Value, ...)
    % Pregenerated, block-randomized sequence of values, indexed by the caller.
    %
    % A BlockSequence draws from a fixed list the way an experiment wants it
    % drawn: in blocks, so that every value appears exactly its share within
    % each block rather than merely on average over an infinite session. The
    % sequence is generated ahead of time and the CALLER supplies the index --
    % usually TRIALS.TrialIndex -- so the value for a trial can be re-read,
    % rewound, or fast-forwarded and will always be the same value.
    %
    % This is the alternative to hw.Parameter's isRandom, which redraws
    % randi([Min Max]) inside set.Value on every dispatch: memoryless,
    % integer-only, and unbalanced over any finite session. A parameter driven
    % from a BlockSequence must have isRandom = false, or the drawn value is
    % overwritten on dispatch.
    %
    %   % A block-randomized inter-trial interval
    %   s = epsych.BlockSequence([500 1000 1500 2000], Label = "ITI");
    %   iti = s.valueAt(TRIALS.TrialIndex);
    %
    %   % Unequal but exact proportions, a run cap, and jitter
    %   s = epsych.BlockSequence([500 1000 1500 2000], Repeats = [2 2 2 1], ...
    %           MaxConsecutive = 2, Jitter = 50, ValueLimits = [250 Inf]);
    %
    %   % Non-numeric values work the same way
    %   s = epsych.BlockSequence(["tone" "noise" "am"]);
    %
    % Properties:
    %   Values               - The pool drawn from; numeric, string, or cellstr
    %   Repeats              - Occurrences per block, scalar or one per value
    %   Seed                 - RandStream seed; assign < 0 to shuffle
    %   MaxConsecutive       - Cap on runs of one value (default Inf, off)
    %   NoRepeatAcrossBlocks - Block may not start with the previous block's last
    %   Jitter               - +/-j, or [lo hi], added to numeric values
    %   JitterQuantum        - Round the jittered value to a multiple of this
    %   ValueLimits          - [lo hi] clamp applied after jitter
    %   Exhaustion           - "extend" (default), "wrap", or "error"
    %   MinLength            - Elements pregenerated on a rebuild
    %   ChunkBlocks          - Blocks appended per automatic extension
    %   MaxLength            - Hard cap on growth; guards a bad caller index
    %   Label                - Free-text tag used in log messages
    %   CommittedThrough     - Highest index handed out as a real trial value
    %   Length, BlockSize, NumBlocks, IsValid - Read-only, computed
    %
    % Methods:
    %   valueAt      - The value(s) at one or more caller indices
    %   indexAt      - Position(s) into Values, without jitter
    %   blockAt      - Block number and position within the block
    %   preview      - Look ahead without committing
    %   tally        - How many times each value has been used so far
    %   describe     - One-line summary for logs and GUIs
    %   validate     - Throw the specific reason this configuration cannot work
    %   regenerate   - Rebuild with the current seed (identical output)
    %   reseed       - Rebuild with a new seed
    %   extend       - Append whole blocks
    %   ensureLength - Extend until at least n elements exist
    %   setCommitted - Move the committed mark, including downward
    %   toStruct / fromStruct - Round trip for session records and prefs
    %
    % See also: epsych.TrialSelector, hw.Parameter,
    % documentation/epsych/epsych_BlockSequence.md

    properties (Constant, Access = private)
        FORMAT_VERSION = 1
        MAX_ATTEMPTS   = 100   % Uniform permutations tried before repair
    end

    properties (SetObservable)
        % --- Composition. Changing these invalidates the sequence. ---
        Values = []                     % Pool drawn from; numeric, string, or cellstr
        Repeats (1,:) double {mustBeNonnegative, mustBeInteger} = 1  % Per block, scalar or one per value
        Seed (1,1) double = -1          % Resolved on assignment; reads back the seed in use

        % --- Constraints. All off by default; each is a real distortion of
        % the sampling distribution and must be asked for. ---
        MaxConsecutive (1,1) double {mustBePositive} = Inf   % Cap on runs of one value
        NoRepeatAcrossBlocks (1,1) logical = false           % Block start ~= previous block end
        Jitter (1,:) double {mustBeFinite} = 0               % Scalar => +/-j; [lo hi] => asymmetric
        JitterQuantum (1,1) double {mustBeNonnegative} = 0   % Round to a multiple; 0 = off
        ValueLimits (1,2) double = [-Inf Inf]                % Clamp applied after jitter

        % --- Buffering and exhaustion. These govern how much is generated and
        % what happens past the end, never what is generated, so they do not
        % invalidate. ---
        Exhaustion (1,1) string {mustBeMember(Exhaustion,["extend","wrap","error"])} = "extend"
        MinLength (1,1) double {mustBePositive, mustBeInteger} = 1000
        ChunkBlocks (1,1) double {mustBePositive, mustBeInteger} = 20
        MaxLength (1,1) double {mustBePositive, mustBeInteger} = 1e6
        Label (1,1) string = ""
    end

    properties (SetAccess = private)
        CommittedThrough (1,1) double = 0   % Highest index handed out as a real trial value
    end

    properties (Dependent, SetAccess = private)
        Length      % Highest index the sequence can serve without extending
        BlockSize   % Elements per block, sum(resolved Repeats)
        NumBlocks   % Whole blocks currently generated
        IsValid     % True when validate would succeed
    end

    properties (Access = private)
        seqIdx_ (1,:) double = []    % Positions into Values -- the sequence proper
        jit_    (1,:) double = []    % Baked jitter offset, one per element
        grp_    (1,:) double = []    % Value index -> distinct-value group, for run checks
        offset_ (1,1) double = 0     % seqIdx_(1) serves caller index offset_+1

        % The realized prefix, materialized before a configuration change
        % discards the sequence that produced it.
        frozenVal_  = []
        frozenBase_ = []
        frozenJit_  (1,:) double = []
        frozenIdx_  (1,:) double = []
        frozenThrough_ (1,1) double = 0

        rng_                         % RandStream; never the global stream
        dirty_ (1,1) logical = true  % Configuration changed; rebuild on next access
    end

    methods
        function obj = BlockSequence(values, options)
            % s = epsych.BlockSequence(values)
            % s = epsych.BlockSequence(values, Name=Value, ...)
            %
            % Parameters:
            %   values  - Pool to draw from: numeric vector, string array, or
            %             cell of char/string. May be empty; the object then
            %             constructs but throws on use.
            %   options - Any writable property, by name.
            arguments
                values = []
                options.Repeats (1,:) double {mustBeNonnegative, mustBeInteger} = 1
                options.Seed (1,1) double = -1
                options.MaxConsecutive (1,1) double {mustBePositive} = Inf
                options.NoRepeatAcrossBlocks (1,1) logical = false
                options.Jitter (1,:) double {mustBeFinite} = 0
                options.JitterQuantum (1,1) double {mustBeNonnegative} = 0
                options.ValueLimits (1,2) double = [-Inf Inf]
                options.Exhaustion (1,1) string {mustBeMember(options.Exhaustion,["extend","wrap","error"])} = "extend"
                options.MinLength (1,1) double {mustBePositive, mustBeInteger} = 1000
                options.ChunkBlocks (1,1) double {mustBePositive, mustBeInteger} = 20
                options.MaxLength (1,1) double {mustBePositive, mustBeInteger} = 1e6
                options.Label (1,1) string = ""
            end

            % Label first, so any log message from the assignments below is
            % already attributed.
            obj.Label = options.Label;
            obj.Values = values;

            for f = string(fieldnames(options))'
                if f == "Label", continue; end
                obj.(f) = options.(f);
            end
        end

        % ---------------------------------------------------------------- %
        % Core accessors
        % ---------------------------------------------------------------- %

        function [v, info] = valueAt(obj, idx, opts)
            % [v, info] = valueAt(obj, idx)
            % [v, info] = valueAt(obj, idx, Commit = false)
            % The value(s) at one or more caller indices.
            %
            % The index is the caller's, so the same index always returns the
            % same value: a selector may re-read, rewind, or skip ahead freely.
            %
            % Parameters:
            %   idx        - Positive integer index or vector of indices.
            %   opts.Commit - Advance CommittedThrough (default true). Pass
            %                 false to inspect without recording the read as
            %                 a delivered trial value.
            %
            % Returns:
            %   v    - Values ready to write, same shape as idx. Numeric pools
            %          are jittered, quantized, and clamped; other pools are
            %          returned as stored.
            %   info - Struct of same-shape arrays: Index, Base, Jitter,
            %          ValueIndex, Block, PositionInBlock, Wrapped, Extended.
            arguments
                obj (1,1) epsych.BlockSequence
                idx double
                opts.Commit (1,1) logical = true
            end

            obj.assertIndex_(idx);
            if isempty(idx)
                v = []; info = obj.emptyInfo_();
                return
            end

            % A configuration error must not take down a running experiment:
            % keep serving the sequence already in hand and leave the object
            % dirty so a corrected configuration takes effect on the next read.
            try
                obj.ensureFresh_();
            catch ME
                if isempty(obj.seqIdx_) && obj.frozenThrough_ == 0
                    rethrow(ME)
                end
                vprintf(0, 1, 'BlockSequence(%s): keeping the previous sequence, configuration is unusable: %s', ...
                    obj.Label, ME.message)
            end

            if isempty(obj.Values)
                error('epsych:BlockSequence:NoValues', ...
                    'BlockSequence(%s) has no Values to draw from.', obj.Label);
            end

            [pos, wrapped, extended] = obj.resolvePositions_(idx);

            base  = reshape(obj.blankLike_(numel(idx)), size(idx));
            jitv  = zeros(size(idx));
            vidx  = nan(size(idx));
            blk   = nan(size(idx));
            posIn = nan(size(idx));

            isFrozen = pos == 0;
            live     = ~isFrozen;

            if any(isFrozen)
                fk = idx(isFrozen);
                base(isFrozen) = obj.frozenBase_(fk);
                jitv(isFrozen) = obj.frozenJit_(fk);
                vidx(isFrozen) = obj.frozenIdx_(fk);
            end
            if any(live)
                lk = pos(live);
                base(live) = obj.Values(obj.seqIdx_(lk));
                jitv(live) = obj.jit_(lk);
                vidx(live) = obj.seqIdx_(lk);
                B = obj.BlockSize;
                blk(live)   = ceil(lk / B);
                posIn(live) = lk - (blk(live) - 1) * B;
            end

            v = obj.applyJitter_(base, jitv);
            if any(isFrozen)
                % The frozen prefix is stored realized: a later change to
                % Jitter or ValueLimits must not retroactively alter it.
                v(isFrozen) = obj.frozenVal_(idx(isFrozen));
            end

            info = struct('Index', idx, 'Base', base, 'Jitter', jitv, ...
                'ValueIndex', vidx, 'Block', blk, 'PositionInBlock', posIn, ...
                'Wrapped', wrapped, 'Extended', extended);

            if opts.Commit
                obj.CommittedThrough = max(obj.CommittedThrough, max(idx(:)));
            end
        end

        function k = indexAt(obj, idx)
            % k = indexAt(obj, idx)
            % Position(s) into Values at the given caller indices, without jitter.
            %
            % This is how a caller block-randomizes something the class does not
            % store: build the sequence over 1:numel(myList) and index the list.
            %
            %   s = epsych.BlockSequence(1:numel(files));
            %   f = files{s.indexAt(TRIALS.TrialIndex)};
            %
            % For indices inside a frozen prefix the position refers to the
            % value list that was in force when the value was delivered.
            arguments
                obj (1,1) epsych.BlockSequence
                idx double
            end
            [~, info] = obj.valueAt(idx, Commit = false);
            k = info.ValueIndex;
        end

        function [b, pos] = blockAt(obj, idx)
            % [b, pos] = blockAt(obj, idx)
            % Block number and 1-based position within that block.
            %
            % Returns NaN for indices served from a frozen prefix, whose blocks
            % belong to a sequence that no longer exists.
            arguments
                obj (1,1) epsych.BlockSequence
                idx double
            end
            [~, info] = obj.valueAt(idx, Commit = false);
            b   = info.Block;
            pos = info.PositionInBlock;
        end

        % ---------------------------------------------------------------- %
        % Read-only inspection -- never commits
        % ---------------------------------------------------------------- %

        function v = preview(obj, startIdx, count)
            % v = preview(obj, startIdx, count)
            % The next count values from startIdx, without committing them.
            arguments
                obj (1,1) epsych.BlockSequence
                startIdx (1,1) double {mustBePositive, mustBeInteger}
                count (1,1) double {mustBePositive, mustBeInteger} = 10
            end
            v = obj.valueAt(startIdx:startIdx + count - 1, Commit = false);
        end

        function n = tally(obj, throughIdx)
            % n = tally(obj, throughIdx)
            % How many times each entry of Values has been used through an index.
            %
            % Defaults to CommittedThrough, so tally() answers "what has this
            % subject actually received so far". Positions recorded in a frozen
            % prefix refer to the list in force at the time; any that fall
            % outside the current Values are not counted.
            arguments
                obj (1,1) epsych.BlockSequence
                throughIdx (1,1) double {mustBeNonnegative, mustBeInteger} = obj.CommittedThrough
            end
            n = zeros(1, numel(obj.Values));
            if throughIdx < 1 || isempty(obj.Values), return; end
            k = obj.indexAt(1:throughIdx);
            k = k(~isnan(k) & k >= 1 & k <= numel(obj.Values));
            if isempty(k), return; end
            n = accumarray(k(:), 1, [numel(obj.Values) 1]).';
        end

        function s = describe(obj)
            % s = describe(obj)
            % One-line summary for a log line or a GUI status field.
            if isempty(obj.Values)
                s = sprintf('BlockSequence(%s): empty', obj.Label);
                return
            end
            s = sprintf('BlockSequence(%s): %d values, block %d, seed %d, %d generated, committed through %d', ...
                obj.Label, numel(obj.Values), obj.BlockSize, obj.Seed, obj.Length, obj.CommittedThrough);
        end

        % ---------------------------------------------------------------- %
        % Lifecycle
        % ---------------------------------------------------------------- %

        function validate(obj)
            % validate(obj)
            % Throw the specific reason this configuration cannot produce a
            % sequence. No side effects.
            %
            % Call this from a trial selector's initialize, so a bad design
            % fails at run start rather than at the first trial.
            if isempty(obj.Values)
                error('epsych:BlockSequence:NoValues', ...
                    'BlockSequence(%s) has no Values to draw from.', obj.Label);
            end

            r = obj.resolvedRepeats_();
            if sum(r) < 1
                error('epsych:BlockSequence:EmptyBlock', ...
                    'BlockSequence(%s): Repeats sums to zero, so a block would be empty.', obj.Label);
            end

            if ~isnumeric(obj.Values) && (any(obj.Jitter ~= 0) || obj.JitterQuantum > 0 || any(isfinite(obj.ValueLimits)))
                error('epsych:BlockSequence:JitterRequiresNumeric', ...
                    'BlockSequence(%s): Jitter, JitterQuantum, and ValueLimits need a numeric value list.', obj.Label);
            end

            if numel(obj.Jitter) > 2
                error('epsych:BlockSequence:InvalidJitter', ...
                    'BlockSequence(%s): Jitter must be a scalar or [lo hi].', obj.Label);
            end
            jr = obj.jitterRange_();
            if jr(1) > jr(2)
                error('epsych:BlockSequence:InvalidJitter', ...
                    'BlockSequence(%s): Jitter [lo hi] is reversed ([%g %g]).', obj.Label, jr(1), jr(2));
            end
            if obj.ValueLimits(1) > obj.ValueLimits(2)
                error('epsych:BlockSequence:InvalidLimits', ...
                    'BlockSequence(%s): ValueLimits is reversed ([%g %g]).', ...
                    obj.Label, obj.ValueLimits(1), obj.ValueLimits(2));
            end

            % Group counts, not value counts: a list holding the same value
            % twice must not look like two different values to a run check.
            gc = accumarray(obj.grp_(:), r(:));
            gc = gc(gc > 0);
            nGroups = numel(gc);

            constrained = isfinite(obj.MaxConsecutive) || obj.NoRepeatAcrossBlocks;
            if nGroups < 2 && constrained
                error('epsych:BlockSequence:UnsatisfiableConstraints', ...
                    ['BlockSequence(%s): MaxConsecutive and NoRepeatAcrossBlocks need at least two ' ...
                    'distinct values; the list has %d.'], obj.Label, nGroups);
            end

            if isfinite(obj.MaxConsecutive)
                % A block of B elements whose commonest group appears m times
                % can be arranged with runs no longer than k iff the other
                % B-m elements can separate them: m <= k*(B-m+1).
                B = sum(gc);
                m = max(gc);
                k = obj.MaxConsecutive;
                if m > k * (B - m + 1)
                    error('epsych:BlockSequence:UnsatisfiableConstraints', ...
                        ['BlockSequence(%s): a block of %d with %d copies of one value cannot be ' ...
                        'arranged with runs of at most %g.'], obj.Label, B, m, k);
                end
            end
        end

        function regenerate(obj)
            % regenerate(obj)
            % Rebuild the sequence with the current seed. Same seed and same
            % configuration reproduce the sequence exactly.
            %
            % Any frozen prefix is kept: values already delivered are part of
            % the session record and never change.
            obj.dirty_ = true;
            obj.ensureFresh_();
        end

        function reseed(obj, seed)
            % reseed(obj, seed)
            % Rebuild with a new seed. Omit seed, or pass a negative value, to
            % draw a fresh one from the clock without touching the global rng.
            arguments
                obj (1,1) epsych.BlockSequence
                seed (1,1) double = -1
            end
            obj.Seed = seed;   % the setter resolves, freezes, and invalidates
            obj.ensureFresh_();
        end

        function extend(obj, nBlocks)
            % extend(obj, nBlocks)
            % Append whole blocks to the end of the sequence.
            %
            % Extension only ever appends: no element already generated is
            % rewritten, so a rewind returns exactly what it returned before.
            arguments
                obj (1,1) epsych.BlockSequence
                nBlocks (1,1) double {mustBePositive, mustBeInteger} = 1
            end
            obj.ensureFresh_();
            obj.appendBlocks_(nBlocks);
        end

        function ensureLength(obj, n)
            % ensureLength(obj, n)
            % Extend until at least n caller indices can be served.
            arguments
                obj (1,1) epsych.BlockSequence
                n (1,1) double {mustBePositive, mustBeInteger}
            end
            obj.ensureFresh_();
            if n > obj.MaxLength
                error('epsych:BlockSequence:LengthLimit', ...
                    ['BlockSequence(%s): index %d exceeds MaxLength (%d). Raise MaxLength if the ' ...
                    'session really is that long.'], obj.Label, n, obj.MaxLength);
            end
            deficit = n - (obj.offset_ + numel(obj.seqIdx_));
            if deficit <= 0, return; end
            % Grow by at least ChunkBlocks, so a long session does not append
            % one block per trial.
            obj.appendBlocks_(max(obj.ChunkBlocks, ceil(deficit / obj.BlockSize)));
        end

        function setCommitted(obj, idx)
            % setCommitted(obj, idx)
            % Move the committed mark, including downward after a rewind.
            %
            % valueAt advances this mark on its own; use this only to correct
            % it, for instance after discarding trials.
            arguments
                obj (1,1) epsych.BlockSequence
                idx (1,1) double {mustBeNonnegative, mustBeInteger}
            end
            obj.CommittedThrough = idx;
        end

        % ---------------------------------------------------------------- %
        % Persistence
        % ---------------------------------------------------------------- %

        function s = toStruct(obj, opts)
            % s = toStruct(obj)
            % s = toStruct(obj, IncludeSequence = false)
            % Plain struct for a session record, a pref, or a protocol file.
            %
            % The generated sequence is included by default (a few kilobytes)
            % so the record is exact. Pass IncludeSequence = false for a
            % configuration-only struct; fromStruct then regenerates from the
            % seed, which reproduces the same sequence.
            arguments
                obj (1,1) epsych.BlockSequence
                opts.IncludeSequence (1,1) logical = true
            end
            s = struct();
            s.FormatVersion = obj.FORMAT_VERSION;
            for f = ["Values","Repeats","Seed","MaxConsecutive","NoRepeatAcrossBlocks", ...
                    "Jitter","JitterQuantum","ValueLimits","Exhaustion","MinLength", ...
                    "ChunkBlocks","MaxLength","Label"]
                s.(f) = obj.(f);
            end
            s.CommittedThrough = obj.CommittedThrough;
            s.FrozenThrough    = obj.frozenThrough_;
            s.FrozenValues     = obj.frozenVal_;
            s.FrozenBase       = obj.frozenBase_;
            s.FrozenJitter     = obj.frozenJit_;
            s.FrozenIndex      = obj.frozenIdx_;
            if opts.IncludeSequence
                s.SequenceIndex = obj.seqIdx_;
                s.SequenceJitter = obj.jit_;
                s.Offset = obj.offset_;
            end
        end
    end

    methods (Static)
        function obj = fromStruct(s)
            % obj = epsych.BlockSequence.fromStruct(s)
            % Rebuild from a toStruct result.
            %
            % Degrades rather than throwing: unrecognised or missing fields are
            % logged and left at their defaults, so an old session record still
            % opens.
            obj = epsych.BlockSequence();
            if ~isstruct(s) || ~isscalar(s)
                vprintf(2, 'BlockSequence.fromStruct: not a scalar struct; returning defaults')
                return
            end

            for f = ["Label","Values","Repeats","Seed","MaxConsecutive","NoRepeatAcrossBlocks", ...
                    "Jitter","JitterQuantum","ValueLimits","Exhaustion","MinLength", ...
                    "ChunkBlocks","MaxLength"]
                if ~isfield(s, f), continue; end
                try
                    obj.(f) = s.(f);
                catch ME
                    vprintf(2, 'BlockSequence.fromStruct: ignoring %s (%s)', f, ME.message)
                end
            end

            try
                obj.restoreState_(s);
            catch ME
                vprintf(2, 'BlockSequence.fromStruct: could not restore the generated sequence (%s)', ME.message)
            end
        end
    end

    % -------------------------------------------------------------------- %
    % Property access
    % -------------------------------------------------------------------- %

    methods
        function set.Values(obj, v)
            v = epsych.BlockSequence.normalizeValues_(v);
            if isequaln(v, obj.Values), return; end

            if obj.CommittedThrough > 0 && ~isempty(obj.Values) && ~isempty(v) ...
                    && ~strcmp(class(v), class(obj.Values))
                error('epsych:BlockSequence:ValueTypeChanged', ...
                    ['BlockSequence(%s): the value list changed type (%s to %s) after %d trials had ' ...
                    'been delivered; the frozen prefix could not be kept.'], ...
                    obj.Label, class(obj.Values), class(v), obj.CommittedThrough);
            end

            % A same-length replacement is a pure lookup-table swap: the
            % ordering and the baked jitter still apply, so the randomization
            % survives an operator retuning the values.
            remapOnly = ~isempty(obj.Values) && numel(v) == numel(obj.Values) && ~obj.dirty_;

            obj.freezeCommitted_();   % must run before the old list is lost
            obj.Values = v;
            obj.grp_   = epsych.BlockSequence.groupsOf_(v);

            if remapOnly
                vprintf(2, 'BlockSequence(%s): value list remapped in place; ordering preserved', obj.Label)
            else
                obj.invalidate_('Values changed');
            end
        end

        function set.Repeats(obj, v)
            if isequal(v, obj.Repeats), return; end
            obj.freezeCommitted_();
            obj.Repeats = v;
            obj.invalidate_('Repeats changed');
        end

        function set.Seed(obj, v)
            resolved = epsych.BlockSequence.resolveSeed_(v);
            if isequal(resolved, obj.Seed), return; end
            obj.freezeCommitted_();
            obj.Seed = resolved;
            obj.invalidate_('Seed changed');
        end

        function set.MaxConsecutive(obj, v)
            if isequal(v, obj.MaxConsecutive), return; end
            obj.freezeCommitted_();
            obj.MaxConsecutive = v;
            obj.invalidate_('MaxConsecutive changed');
        end

        function set.NoRepeatAcrossBlocks(obj, v)
            if isequal(v, obj.NoRepeatAcrossBlocks), return; end
            obj.freezeCommitted_();
            obj.NoRepeatAcrossBlocks = v;
            obj.invalidate_('NoRepeatAcrossBlocks changed');
        end

        function set.Jitter(obj, v)
            if isequal(v, obj.Jitter), return; end
            obj.freezeCommitted_();
            obj.Jitter = v;
            obj.invalidate_('Jitter changed');
        end

        function set.JitterQuantum(obj, v)
            if isequal(v, obj.JitterQuantum), return; end
            obj.freezeCommitted_();
            obj.JitterQuantum = v;
            obj.invalidate_('JitterQuantum changed');
        end

        function set.ValueLimits(obj, v)
            if isequal(v, obj.ValueLimits), return; end
            obj.freezeCommitted_();
            obj.ValueLimits = v;
            obj.invalidate_('ValueLimits changed');
        end

        function n = get.Length(obj)
            obj.tryFresh_();
            n = obj.offset_ + numel(obj.seqIdx_);
        end

        function n = get.BlockSize(obj)
            try
                n = sum(obj.resolvedRepeats_());
            catch
                n = NaN;
            end
        end

        function n = get.NumBlocks(obj)
            obj.tryFresh_();
            B = obj.BlockSize;
            if isnan(B) || B < 1
                n = 0;
            else
                n = numel(obj.seqIdx_) / B;
            end
        end

        function tf = get.IsValid(obj)
            try
                obj.validate();
                tf = true;
            catch
                tf = false;
            end
        end
    end

    % -------------------------------------------------------------------- %
    % Generation
    % -------------------------------------------------------------------- %

    methods (Access = private)
        function ensureFresh_(obj)
            % Lazy rebuild, so a multi-property edit is validated as a set
            % rather than throwing on the intermediate state.
            if ~obj.dirty_, return; end
            obj.validate();
            obj.rebuild_();
            obj.dirty_ = false;
        end

        function tryFresh_(obj)
            % ensureFresh_ for a property getter: a bad configuration must not
            % make the object undisplayable.
            try
                obj.ensureFresh_();
            catch
            end
        end

        function rebuild_(obj)
            % The frozen prefix keeps the values already delivered. Everything
            % after it is generated fresh, starting a new block at the splice
            % so no block is ever half-old and half-new.
            discarded = numel(obj.seqIdx_);
            obj.rng_     = RandStream('twister', 'Seed', obj.Seed);
            obj.offset_  = obj.frozenThrough_;
            obj.seqIdx_  = [];
            obj.jit_     = [];

            obj.appendBlocks_(ceil(obj.MinLength / obj.BlockSize));

            if obj.frozenThrough_ > 0
                vprintf(1, ['BlockSequence(%s): regenerated at trial %d; %d values preserved, ' ...
                    '%d generated but undelivered values discarded'], obj.Label, obj.frozenThrough_ + 1, ...
                    obj.frozenThrough_, max(0, discarded));
            end
        end

        function appendBlocks_(obj, nBlocks)
            B = obj.BlockSize;
            if obj.offset_ + numel(obj.seqIdx_) + nBlocks * B > obj.MaxLength
                nBlocks = floor((obj.MaxLength - obj.offset_ - numel(obj.seqIdx_)) / B);
                if nBlocks < 1
                    error('epsych:BlockSequence:LengthLimit', ...
                        'BlockSequence(%s): already at MaxLength (%d).', obj.Label, obj.MaxLength);
                end
            end

            r    = obj.resolvedRepeats_();
            pool = repelem(1:numel(obj.Values), r);
            jr   = obj.jitterRange_();

            newIdx = zeros(1, nBlocks * B);
            for b = 1:nBlocks
                tailGrp = obj.tailGroups_(newIdx, (b - 1) * B);
                blk = obj.makeBlock_(pool, tailGrp);
                newIdx((b - 1) * B + (1:B)) = blk;
            end

            obj.seqIdx_ = [obj.seqIdx_ newIdx];
            if jr(1) == 0 && jr(2) == 0
                obj.jit_ = [obj.jit_ zeros(1, numel(newIdx))];
            else
                u = rand(obj.rng_, 1, numel(newIdx));
                obj.jit_ = [obj.jit_ jr(1) + u * (jr(2) - jr(1))];
            end
        end

        function g = tailGroups_(obj, newIdx, nNew)
            % The last few group ids before the block being built. Only as many
            % as the run cap can see, which is what keeps extension O(block)
            % rather than O(length).
            need = 1;
            if isfinite(obj.MaxConsecutive), need = max(need, obj.MaxConsecutive); end
            if ~obj.NoRepeatAcrossBlocks && ~isfinite(obj.MaxConsecutive)
                g = [];
                return
            end
            avail = [obj.seqIdx_ newIdx(1:nNew)];
            if isempty(avail), g = []; return; end
            g = obj.grp_(avail(max(1, end - need + 1):end));
        end

        function blk = makeBlock_(obj, pool, tailGrp)
            % Rejection first: a uniform permutation preserves the distribution
            % over valid arrangements, which a swap-based repair does not.
            % Repair is the fallback for a block the sampler keeps missing.
            B = numel(pool);
            blk = pool;
            for a = 1:obj.MAX_ATTEMPTS
                blk = pool(randperm(obj.rng_, B));
                if obj.blockOK_(blk, tailGrp), return; end
            end

            blk = obj.repairBlock_(blk, tailGrp);
            if obj.blockOK_(blk, tailGrp)
                vprintf(2, 'BlockSequence(%s): block repaired after %d rejected permutations', ...
                    obj.Label, obj.MAX_ATTEMPTS)
                return
            end

            error('epsych:BlockSequence:UnsatisfiableConstraints', ...
                ['BlockSequence(%s): no arrangement of a block satisfies MaxConsecutive = %g ' ...
                'and NoRepeatAcrossBlocks = %d.'], obj.Label, obj.MaxConsecutive, obj.NoRepeatAcrossBlocks);
        end

        function tf = blockOK_(obj, blk, tailGrp)
            g = obj.grp_(blk);
            if obj.NoRepeatAcrossBlocks && ~isempty(tailGrp) && g(1) == tailGrp(end)
                tf = false;
                return
            end
            if ~isfinite(obj.MaxConsecutive)
                tf = true;
                return
            end
            tf = epsych.BlockSequence.maxRun_([tailGrp g]) <= obj.MaxConsecutive;
        end

        function blk = repairBlock_(obj, blk, tailGrp)
            % One swap per violation, left to right, no backtracking. A pass
            % that cannot clear every violation falls through to the caller's
            % error rather than pretending the constraint held.
            n = numel(blk);
            for pass = 1:n
                if obj.blockOK_(blk, tailGrp), return; end
                p = obj.firstFixable_(blk, tailGrp);
                if p == 0, return; end
                fixed = false;
                for q = 1:n
                    if q == p, continue; end
                    cand = blk;
                    cand([p q]) = cand([q p]);
                    if obj.blockOK_(cand, tailGrp)
                        blk = cand;
                        fixed = true;
                        break
                    end
                end
                if ~fixed, return; end
            end
        end

        function p = firstFixable_(obj, blk, tailGrp)
            % Position within blk of the first element that breaks a rule.
            g = obj.grp_(blk);
            if obj.NoRepeatAcrossBlocks && ~isempty(tailGrp) && g(1) == tailGrp(end)
                p = 1;
                return
            end
            p = 0;
            if ~isfinite(obj.MaxConsecutive), return; end
            x  = [tailGrp g];
            nT = numel(tailGrp);
            st = [true, x(2:end) ~= x(1:end-1)];
            s  = find(st);
            e  = [s(2:end) - 1, numel(x)];
            bad = find((e - s + 1) > obj.MaxConsecutive, 1);
            if isempty(bad), return; end
            % Positions s(bad)..s(bad)+k-1 are allowed; the next one is not.
            p = min(numel(g), max(1, s(bad) + obj.MaxConsecutive - nT));
        end

        function r = resolvedRepeats_(obj)
            n = numel(obj.Values);
            if isscalar(obj.Repeats)
                r = repmat(obj.Repeats, 1, n);
            elseif numel(obj.Repeats) == n
                r = obj.Repeats;
            else
                error('epsych:BlockSequence:RepeatsMismatch', ...
                    'BlockSequence(%s): Repeats has %d entries but there are %d values.', ...
                    obj.Label, numel(obj.Repeats), n);
            end
        end

        function jr = jitterRange_(obj)
            if isscalar(obj.Jitter)
                jr = [-abs(obj.Jitter) abs(obj.Jitter)];
            else
                jr = obj.Jitter(1:2);
            end
        end

        function invalidate_(obj, reason)
            obj.dirty_ = true;
            vprintf(2, 'BlockSequence(%s): invalidated (%s)', obj.Label, reason)
        end

        function freezeCommitted_(obj)
            % Materialize what has already been delivered, before the
            % configuration that produced it is discarded. Values handed to a
            % subject are part of the session record and must survive an edit.
            if obj.CommittedThrough <= obj.frozenThrough_, return; end
            if isempty(obj.seqIdx_) || isempty(obj.Values), return; end

            n = min(obj.CommittedThrough, obj.offset_ + numel(obj.seqIdx_));
            if n <= obj.frozenThrough_, return; end

            if obj.frozenThrough_ == 0
                % Seed the frozen arrays with the class of the current value
                % list, so a string or cellstr pool grows correctly below.
                obj.frozenVal_  = obj.blankLike_(0);
                obj.frozenBase_ = obj.blankLike_(0);
            end

            keep = obj.frozenThrough_ + 1 : n;
            pos  = keep - obj.offset_;
            live = pos >= 1 & pos <= numel(obj.seqIdx_);

            vi   = nan(1, numel(keep));
            jv   = zeros(1, numel(keep));
            base = obj.blankLike_(numel(keep));
            vi(live)   = obj.seqIdx_(pos(live));
            jv(live)   = obj.jit_(pos(live));
            base(live) = obj.Values(obj.seqIdx_(pos(live)));
            val = obj.applyJitter_(base, jv);

            obj.frozenIdx_(keep)  = vi;
            obj.frozenJit_(keep)  = jv;
            obj.frozenBase_(keep) = base;
            obj.frozenVal_(keep)  = val;
            obj.frozenThrough_    = n;
        end

        function [pos, wrapped, extended] = resolvePositions_(obj, idx)
            % Map caller indices onto the live sequence. Zero means "served
            % from the frozen prefix".
            wrapped  = false(size(idx));
            extended = false(size(idx));
            pos      = idx - obj.offset_;

            frozen = idx <= obj.frozenThrough_;
            pos(frozen) = 0;

            need = idx(~frozen);
            if isempty(need), return; end

            n = numel(obj.seqIdx_);
            over = max(need) - obj.offset_;
            if over > n
                switch obj.Exhaustion
                    case "extend"
                        before = n;
                        obj.ensureLength(max(need));
                        n = numel(obj.seqIdx_);
                        extended(~frozen) = (need - obj.offset_) > before;
                    case "wrap"
                        % handled per-element below
                    case "error"
                        error('epsych:BlockSequence:IndexExceedsSequence', ...
                            ['BlockSequence(%s): index %d is past the end of the sequence (%d) and ' ...
                            'Exhaustion is "error".'], obj.Label, max(need), obj.offset_ + n);
                end
            end

            if obj.Exhaustion == "wrap"
                tooFar = ~frozen & pos > n;
                if any(tooFar)
                    pos(tooFar) = mod(pos(tooFar) - 1, n) + 1;
                    wrapped(tooFar) = true;
                end
            end
            pos(~frozen) = max(pos(~frozen), 1);
        end

        function v = applyJitter_(obj, base, jitv)
            if ~isnumeric(base)
                v = base;
                return
            end
            v = base + jitv;
            if obj.JitterQuantum > 0
                v = round(v / obj.JitterQuantum) * obj.JitterQuantum;
            end
            v = min(max(v, obj.ValueLimits(1)), obj.ValueLimits(2));
        end

        function v = blankLike_(obj, n)
            % An n-element array of the same class as Values, for scatter
            % assignment.
            if iscell(obj.Values)
                v = repmat({''}, 1, n);
            elseif isstring(obj.Values)
                v = strings(1, n);
            else
                v = nan(1, n);
            end
        end

        function info = emptyInfo_(~)
            info = struct('Index', [], 'Base', [], 'Jitter', [], 'ValueIndex', [], ...
                'Block', [], 'PositionInBlock', [], 'Wrapped', [], 'Extended', []);
        end

        function assertIndex_(obj, idx)
            if isempty(idx), return; end
            if ~isnumeric(idx) || ~isreal(idx) || any(~isfinite(idx(:))) ...
                    || any(idx(:) < 1) || any(mod(idx(:), 1) ~= 0)
                error('epsych:BlockSequence:InvalidIndex', ...
                    ['BlockSequence(%s): the index must be a positive whole number. A zero or ' ...
                    'fractional index usually means a trial counter was read before it was set.'], ...
                    obj.Label);
            end
            if max(idx(:)) > obj.MaxLength
                error('epsych:BlockSequence:LengthLimit', ...
                    'BlockSequence(%s): index %d exceeds MaxLength (%d).', ...
                    obj.Label, max(idx(:)), obj.MaxLength);
            end
        end

        function restoreState_(obj, s)
            if isfield(s, 'FrozenThrough') && s.FrozenThrough > 0
                obj.frozenThrough_ = s.FrozenThrough;
                obj.frozenVal_     = s.FrozenValues;
                obj.frozenBase_    = s.FrozenBase;
                obj.frozenJit_     = s.FrozenJitter;
                obj.frozenIdx_     = s.FrozenIndex;
            end
            if isfield(s, 'SequenceIndex') && ~isempty(s.SequenceIndex)
                obj.seqIdx_ = s.SequenceIndex;
                obj.jit_    = s.SequenceJitter;
                obj.offset_ = s.Offset;
                obj.rng_    = RandStream('twister', 'Seed', obj.Seed);
                obj.dirty_  = false;
            end
            if isfield(s, 'CommittedThrough')
                obj.CommittedThrough = s.CommittedThrough;
            end
        end
    end

    methods (Static, Access = private)
        function v = normalizeValues_(v)
            % One canonical shape per supported type: a row vector of double,
            % a row string array, or a row cellstr.
            if isempty(v)
                v = [];
                return
            end
            if ischar(v)
                v = {v};            % a char row is one value, not a list of letters
            end
            if islogical(v)
                v = double(v);
            end

            if isnumeric(v)
                v = double(v(:)).';
                if any(~isfinite(v))
                    error('epsych:BlockSequence:NonFiniteValues', ...
                        ['BlockSequence: Values must be finite. NaN would defeat the run-length ' ...
                        'check, since NaN never equals itself.']);
                end
            elseif isstring(v)
                v = v(:).';
                if any(ismissing(v))
                    error('epsych:BlockSequence:NonFiniteValues', ...
                        'BlockSequence: Values must not contain <missing>.');
                end
            elseif iscell(v)
                ok = cellfun(@(x) (ischar(x) && (isrow(x) || isempty(x))) || ...
                    ((isstring(x) || isnumeric(x)) && isscalar(x)), v);
                if ~all(ok)
                    error('epsych:BlockSequence:UnsupportedValues', ...
                        'BlockSequence: a cell value list must hold char rows or scalar strings.');
                end
                v = cellfun(@(x) char(string(x)), v(:).', UniformOutput = false);
            else
                error('epsych:BlockSequence:UnsupportedValues', ...
                    ['BlockSequence: Values must be numeric, a string array, or a cell of ' ...
                    'char/string; got %s.'], class(v));
            end
        end

        function g = groupsOf_(v)
            % Distinct-value group per entry, so a list holding the same value
            % twice is treated as one value by the run constraints.
            if isempty(v)
                g = [];
                return
            end
            [~, ~, g] = unique(v(:));
            g = g(:).';
        end

        function s = resolveSeed_(s)
            % Resolve eagerly so Seed always reads back the integer actually in
            % use and can be written straight into a session record.
            % Constructing a shuffled stream takes its seed from the clock; it
            % does not advance the global stream the way randi would.
            if isempty(s) || any(~isfinite(s)) || s < 0
                s = epsych.BlockSequence.drawSeed_();
            else
                s = mod(round(s), 2^32 - 1);
            end
        end

        function s = drawSeed_()
            % Seeds are drawn from one clock-seeded source stream rather than
            % from RandStream('shuffle') each time: two sequences built in the
            % same millisecond would otherwise get the same seed and run in
            % lockstep. The source is private, so the global stream is
            % untouched either way.
            persistent src
            if isempty(src)
                src = RandStream('twister', 'Seed', 'shuffle');
            end
            s = randi(src, [0 2^32 - 2]);
        end

        function m = maxRun_(x)
            if isempty(x)
                m = 0;
                return
            end
            st = [true, x(2:end) ~= x(1:end-1)];
            m  = max(diff([find(st), numel(x) + 1]));
        end
    end
end
