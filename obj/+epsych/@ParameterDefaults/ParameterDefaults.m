classdef ParameterDefaults
    % epsych.ParameterDefaults
    % Per-subject parameter values, applied to the subject's protocol on Run.
    %
    % A subject's membership in a project can carry values that replace its
    % protocol's for that subject alone: a start depth where its staircase left
    % off, a reward volume sized to the animal, a narrower delay range while it
    % learns. They are stored in the roster (the membership's ParameterDefaults
    % field, see epsych.SubjectRoster.setParameterDefaults) so every rig runs
    % the subject the same way, and epsych.RunExpt applies them to the
    % subject's protocol each time Run or Preview is pressed -- before the
    % trial table is compiled, so the first trial already carries them.
    %
    % This class is the headless half: the record shape, which parameters can
    % carry a default, validation, applying and undoing, and reading values
    % back from a session or a saved data file. gui.ParameterDefaultsEditor is
    % the window over it. Static only; not constructible.
    %
    % A record names one parameter and what replaces it:
    %   Interface - the owning interface's Type ('Software', 'TDT_RPcox', ...)
    %   Module    - the owning module's Name
    %   Name      - the parameter's Name
    %   Value     - the replacement; [] leaves the protocol's value alone. A
    %               numeric vector is a list of trial levels -- a roved
    %               parameter's own set for this subject
    %   Min, Max  - replacement bounds; NaN leaves the protocol's alone
    %
    % Things a reader would otherwise re-derive:
    %   * A default replaces the parameter's DESIGN-TIME Values, and seats Value
    %     when that is a single level. Values is what compile() builds the trial
    %     table from and what hw.Interface.resetSession returns an undispatched
    %     parameter to; a Value written alone would be overwritten by the first
    %     dispatch.
    %   * Bounds are applied before the value, because hw.Parameter clamps a
    %     value into [Min Max] on write -- a default outside the protocol's
    %     range needs its bound moved first, and check() refuses one that is
    %     still out of range rather than letting the clamp change it silently.
    %   * What a Run replaced is remembered (the apply STATE, kept on the CONFIG
    %     entry) and put back before the next Run applies anything, so a
    %     default removed between runs returns the protocol's value instead of
    %     leaving the last run's in place. The state is tied to the protocol
    %     object: a reloaded protocol is pristine and starts clean.
    %   * Only parameters a stored value can mean something on are eligible:
    %     writable, not a trigger or a momentary control
    %     (hw.Parameter.isTransientControl), no Expression (it recomputes the
    %     value on every dispatch), and a Float, Integer, Boolean, String or
    %     File type. A randomized parameter takes bounds only, since its value
    %     is redrawn from them on every dispatch.
    %   * A record matches the protocol by interface, module and name, then by
    %     interface and name when the module was renamed. One that matches
    %     nothing is SKIPPED with a note, never an error: a protocol revision
    %     must not stop a subject from running.
    %   * A paired parameter (UserData.Pair) must keep its protocol's level
    %     count, or the paired expansion in compile() produces no trials.
    %
    % Static methods:
    %   empty, blank, normalize, validate, key, summary - the record
    %   parameters, eligibility, resolve, check        - against a protocol
    %   parseValue, formatValue, formatLevels          - text in the editor
    %   apply, emptyState                              - on Run
    %   rosterLink, lookup, applyToConfigEntry         - the CONFIG seam
    %   readSession, latestDataFile, readDataFile      - capture
    %
    % Example:
    %   d = epsych.ParameterDefaults.blank();
    %   d.Interface = 'Software'; d.Module = 'Params'; d.Name = 'Depth';
    %   d.Value = -10;
    %   [state, report] = epsych.ParameterDefaults.apply(protocol, d);
    %   protocol.compile();
    %
    % Documentation: documentation/epsych/epsych_ParameterDefaults.md
    % See also: epsych.SubjectRoster, gui.ParameterDefaultsEditor,
    %   epsych.RunExpt.ExptDispatch, hw.Parameter

    properties (Constant)
        % Types a default can carry a value for. Buffers and StimType hold data
        % or objects no text field can express, and 'Undefined' has no meaning.
        VALUE_TYPES = {'Float','Integer','Boolean','String','File'}

        % Types with meaningful numeric bounds.
        BOUND_TYPES = {'Float','Integer'}
    end

    methods
        function obj = ParameterDefaults()
            % Not constructible: a namespace for the static functions below.
            error('epsych:ParameterDefaults:Static', ...
                'epsych.ParameterDefaults has only static methods.');
        end
    end

    methods (Static)
        [state, report] = apply(protocol, D, state)
        [C, report] = applyToConfigEntry(C, options)
        [D, source, message] = lookup(link, options)
        T = parameters(protocol, options)
        [vals, report] = readSession(runExpt, subjectName, T)
        [file, row, message] = latestDataFile(subjectName, options)
        [vals, report] = readDataFile(file, T)
        [value, ok, message] = parseValue(text, P)

        function D = empty()
            % D = epsych.ParameterDefaults.empty()
            % A 1x0 record array: the value a membership with no defaults holds.
            D = epsych.ParameterDefaults.blank();
            D(1) = [];
        end

        function d = blank()
            % d = epsych.ParameterDefaults.blank()
            % One record with every field at its "leave the protocol alone"
            % value. The single authority for the field set.
            d = struct( ...
                'Interface', '', ...
                'Module',    '', ...
                'Name',      '', ...
                'Value',     [], ...
                'Min',       NaN, ...
                'Max',       NaN);
        end

        function state = emptyState()
            % state = epsych.ParameterDefaults.emptyState()
            % What apply remembers between runs: the protocol it applied to and
            % what it replaced there. See apply.
            state = struct('Protocol', [], ...
                'Originals', struct('Param', {}, 'Values', {}, 'Min', {}, ...
                    'Max', {}, 'SeatValue', {}));
        end

        function report = emptyReport()
            % report = epsych.ParameterDefaults.emptyReport()
            % apply's report when nothing was applied or put back.
            report = struct( ...
                'Applied',  struct('Key', {}, 'Label', {}, 'Text', {}), ...
                'Skipped',  struct('Key', {}, 'Label', {}, 'Reason', {}), ...
                'Restored', 0, ...
                'Changed',  false);
        end

        function D = normalize(D)
            % D = epsych.ParameterDefaults.normalize(D)
            % Reshape whatever a roster file holds into the record array.
            %
            % Never throws and never validates: a roster is a shared file, and
            % one malformed record must not make it unreadable for the lab.
            % A record that cannot even name a parameter is dropped; the rest
            % are coerced to the field types blank() declares.
            tmpl = epsych.ParameterDefaults.blank();
            if ~isstruct(D) || isempty(D)
                D = epsych.ParameterDefaults.empty();
                return
            end

            out = repmat(tmpl, 1, numel(D));
            keep = true(1, numel(D));
            for i = 1:numel(D)
                for f = fieldnames(tmpl)'
                    if isfield(D, f{1})
                        out(i).(f{1}) = D(i).(f{1});
                    end
                end
                try
                    out(i).Interface = char(string(out(i).Interface));
                    out(i).Module    = char(string(out(i).Module));
                    out(i).Name      = char(string(out(i).Name));
                    out(i).Min = localBound(out(i).Min);
                    out(i).Max = localBound(out(i).Max);
                    if isstring(out(i).Value)
                        out(i).Value = char(out(i).Value);
                    end
                    keep(i) = ~isempty(out(i).Name);
                catch ME
                    vprintf(2, 'epsych.ParameterDefaults: dropped an unreadable record (%s)', ME.message)
                    keep(i) = false;
                end
            end
            D = out(keep);
        end

        function [ok, message] = validate(D)
            % [ok, message] = epsych.ParameterDefaults.validate(D)
            % Structural check of a record array, with no protocol to consult:
            % every record names a parameter, carries something to apply, has
            % sensible bounds, and names a parameter no other record does.
            % What only the protocol can answer -- range, type, pairing -- is
            % check()'s.
            ok = true;
            message = '';
            if isempty(D), return, end
            if ~isstruct(D)
                ok = false;
                message = 'Parameter defaults must be a struct array.';
                return
            end

            keys = cell(1, numel(D));
            for i = 1:numel(D)
                d = D(i);
                label = epsych.ParameterDefaults.label(d);
                if isempty(d.Name)
                    ok = false;
                    message = sprintf('Parameter default %d names no parameter.', i);
                    return
                end
                if isempty(d.Value) && isnan(d.Min) && isnan(d.Max)
                    ok = false;
                    message = sprintf('The default for %s sets nothing.', label);
                    return
                end
                if ~isempty(d.Value) && ~(isnumeric(d.Value) || islogical(d.Value) || ischar(d.Value))
                    ok = false;
                    message = sprintf('The default for %s must be a number, a list of numbers, true/false, or text.', label);
                    return
                end
                if (isnumeric(d.Value) || islogical(d.Value)) && ~isempty(d.Value) ...
                        && (~isreal(d.Value) || any(~isfinite(double(d.Value(:)))))
                    ok = false;
                    message = sprintf('The default for %s must be finite.', label);
                    return
                end
                if any(isinf([d.Min d.Max]))
                    ok = false;
                    message = sprintf('The bounds for %s must be finite, or blank to keep the protocol''s.', label);
                    return
                end
                if ~isnan(d.Min) && ~isnan(d.Max) && d.Min > d.Max
                    ok = false;
                    message = sprintf('The default Min for %s is above its Max.', label);
                    return
                end
                keys{i} = epsych.ParameterDefaults.key(d);
            end

            [u, ~, j] = unique(lower(keys));
            if numel(u) < numel(keys)
                dup = find(accumarray(j(:), 1) > 1, 1);
                ok = false;
                message = sprintf('%s has more than one default.', ...
                    epsych.ParameterDefaults.label(D(find(j == dup, 1))));
            end
        end

        function k = key(d)
            % k = epsych.ParameterDefaults.key(d)
            % The identity of the parameter a record names, as one string.
            k = sprintf('%s|%s|%s', d.Interface, d.Module, d.Name);
        end

        function s = label(d)
            % s = epsych.ParameterDefaults.label(d)
            % A record's parameter as an operator reads it: Module.Name.
            if isempty(d.Module)
                s = d.Name;
            else
                s = sprintf('%s.%s', d.Module, d.Name);
            end
        end

        function txt = summary(D)
            % txt = epsych.ParameterDefaults.summary(D)
            % One line naming every default, for an export column or a note:
            %   'Depth = -10; StimDelay: Min 1000, Max 3000'
            parts = cell(1, numel(D));
            for i = 1:numel(D)
                parts{i} = epsych.ParameterDefaults.describe(D(i));
            end
            txt = strjoin(parts, '; ');
        end

        function txt = describe(d, unit)
            % txt = epsych.ParameterDefaults.describe(d)
            % txt = epsych.ParameterDefaults.describe(d, unit)
            % One record as text: 'Depth = -10 dB', 'StimDelay: Min 1000, Max 3000'.
            if nargin < 2, unit = ''; end
            b = {};
            if ~isnan(d.Min), b{end+1} = sprintf('Min %g', d.Min); end
            if ~isnan(d.Max), b{end+1} = sprintf('Max %g', d.Max); end
            bounds = strjoin(b, ', ');

            lbl = epsych.ParameterDefaults.label(d);
            if isempty(d.Value)
                txt = sprintf('%s: %s', lbl, bounds);
                return
            end

            v = epsych.ParameterDefaults.formatValue(d.Value);
            if ~isempty(unit) && ~ischar(d.Value)
                v = [v ' ' unit];
            end
            txt = sprintf('%s = %s', lbl, v);
            if ~isempty(bounds)
                txt = sprintf('%s (%s)', txt, bounds);
            end
        end

        function e = eligibility(P)
            % e = epsych.ParameterDefaults.eligibility(P)
            % Whether a default can mean anything on hw.Parameter P.
            %
            % Returns a struct:
            %   CanSetValue  - a stored value would reach the trials
            %   CanSetBounds - Min/Max are meaningful to override
            %   Reason       - why not, or a qualifier ('randomized: bounds
            %                  only'); '' when both are possible
            e = struct('CanSetValue', false, 'CanSetBounds', false, 'Reason', '');

            if strcmp(P.Access, 'Read')
                e.Reason = 'read-only';
                return
            end
            if P.isTrigger
                e.Reason = 'trigger';
                return
            end
            if ~ismember(P.Type, epsych.ParameterDefaults.VALUE_TYPES)
                e.Reason = sprintf('%s parameter', P.Type);
                return
            end
            if strlength(P.Expression) > 0
                e.Reason = 'computed by an expression';
                return
            end
            if hw.Parameter.isTransientControl(P)
                e.Reason = 'momentary control';
                return
            end

            e.CanSetBounds = ismember(P.Type, epsych.ParameterDefaults.BOUND_TYPES);
            if P.isRandom
                e.Reason = 'randomized: bounds only';
            else
                e.CanSetValue = true;
            end
        end

        function [P, how] = resolve(protocol, d)
            % [P, how] = epsych.ParameterDefaults.resolve(protocol, d)
            % The hw.Parameter in PROTOCOL that record D names, or [].
            %
            % how is 'exact' (interface, module and name), 'name' (interface and
            % name: the module was renamed or the record predates one), or ''.
            P = [];
            how = '';
            if isempty(protocol) || isempty(d.Name), return, end

            byName = [];
            for iface = protocol.Interfaces
                if ~strcmp(char(iface.Type), d.Interface), continue, end
                for m = iface.Module
                    hit = m.Parameters(strcmp({m.Parameters.Name}, d.Name));
                    if isempty(hit), continue, end
                    if strcmp(m.Name, d.Module)
                        P = hit(1);
                        how = 'exact';
                        return
                    end
                    if isempty(byName)
                        byName = hit(1);
                    end
                end
            end

            if ~isempty(byName)
                P = byName;
                how = 'name';
            end
        end

        function [ok, message] = check(d, P)
            % [ok, message] = epsych.ParameterDefaults.check(d, P)
            % Whether record D can be applied to hw.Parameter P as it stands:
            % eligibility, type, range under the effective bounds, integer
            % levels, and a paired parameter's level count.
            ok = false;
            label = epsych.ParameterDefaults.label(d);
            e = epsych.ParameterDefaults.eligibility(P);

            if ~isempty(d.Value) && ~e.CanSetValue
                message = sprintf('%s cannot take a value (%s).', label, e.Reason);
                return
            end
            if (~isnan(d.Min) || ~isnan(d.Max)) && ~e.CanSetBounds
                if isempty(e.Reason)
                    message = sprintf('%s has no bounds to override.', label);
                else
                    message = sprintf('%s has no bounds to override (%s).', label, e.Reason);
                end
                return
            end

            lo = P.Min;
            hi = P.Max;
            if ~isnan(d.Min), lo = d.Min; end
            if ~isnan(d.Max), hi = d.Max; end
            if lo > hi
                message = sprintf('%s would have Min %g above Max %g.', label, lo, hi);
                return
            end
            if P.isRandom && ~(isfinite(lo) && isfinite(hi))
                message = sprintf('%s is randomized, so its bounds must stay finite.', label);
                return
            end

            if ~isempty(d.Value)
                v = d.Value;
                switch P.Type
                    case {'Float','Integer'}
                        if ~(isnumeric(v) || islogical(v)) || ~isreal(v)
                            message = sprintf('%s takes a number.', label);
                            return
                        end
                        v = double(v(:)');
                        if any(~isfinite(v))
                            message = sprintf('%s must be finite.', label);
                            return
                        end
                        if strcmp(P.Type, 'Integer') && any(v ~= round(v))
                            message = sprintf('%s takes whole numbers.', label);
                            return
                        end
                        bad = v(v < lo | v > hi);
                        if ~isempty(bad)
                            message = sprintf(['%s = %g is outside its range [%g, %g]. Widen ' ...
                                'Min/Max for this subject to use it.'], label, bad(1), lo, hi);
                            return
                        end
                    case 'Boolean'
                        if ~isscalar(v) || ~(islogical(v) || (isnumeric(v) && any(v == [0 1])))
                            message = sprintf('%s takes true or false.', label);
                            return
                        end
                    otherwise % String, File
                        if ~ischar(v)
                            message = sprintf('%s takes text.', label);
                            return
                        end
                end

                n = numel(epsych.ParameterDefaults.levels(d.Value, P.Type));
                pair = localPairName(P);
                if ~isempty(pair) && n ~= numel(P.Values)
                    message = sprintf(['%s is paired with "%s" and has %d level(s) in the ' ...
                        'protocol, so its default must list %d as well.'], ...
                        label, pair, numel(P.Values), numel(P.Values));
                    return
                end
            end

            ok = true;
            message = '';
        end

        function L = levels(value, type)
            % L = epsych.ParameterDefaults.levels(value, type)
            % A record's Value as the cell of trial levels hw.Parameter.Values
            % holds. Text is one level whatever its length.
            if ischar(value) || isstring(value)
                L = {char(value)};
            elseif strcmp(type, 'Boolean')
                L = num2cell(logical(value(:)'));
            else
                L = num2cell(double(value(:)'));
            end
        end

        function txt = formatValue(value)
            % txt = epsych.ParameterDefaults.formatValue(value)
            % A stored value as the editor shows it and parseValue reads it
            % back: numbers with %g, a list comma-separated, true/false, text
            % as it is. [] is ''.
            if isempty(value) && ~ischar(value)
                txt = '';
            elseif ischar(value) || isstring(value)
                txt = char(value);
            elseif islogical(value)
                t = {'false','true'};
                txt = strjoin(t(double(value(:)') + 1), ', ');
            else
                txt = strjoin(compose('%g', double(value(:)')), ', ');
            end
        end

        function txt = formatLevels(P)
            % txt = epsych.ParameterDefaults.formatLevels(P)
            % A parameter's design-time Values as text, the way formatValue
            % shows a default -- what the editor's Protocol column reads.
            vals = P.Values;
            if isempty(vals)
                txt = '';
                return
            end
            parts = cell(1, numel(vals));
            for i = 1:numel(vals)
                v = vals{i};
                if ischar(v) || isstring(v)
                    parts{i} = char(v);
                elseif (isnumeric(v) || islogical(v)) && isscalar(v)
                    parts{i} = epsych.ParameterDefaults.formatValue(v);
                elseif isnumeric(v) || islogical(v)
                    parts{i} = sprintf('[%d values]', numel(v));
                else
                    parts{i} = sprintf('<%s>', class(v));
                end
            end
            txt = strjoin(parts, ', ');
        end

        function link = rosterLink(file, subjectId, projectId, D)
            % link = epsych.ParameterDefaults.rosterLink(file, subjectId, projectId, D)
            % What a CONFIG entry remembers about where its subject came from,
            % so a Run can read the subject's CURRENT defaults from the roster.
            %
            % D is the defaults as they stood at commit, used only when the
            % roster cannot be read at Run (a share gone offline) -- running on
            % the last known defaults beats running on none. State is apply's.
            arguments
                file (1,:) char = ''
                subjectId (1,:) char = ''
                projectId (1,:) char = ''
                D = epsych.ParameterDefaults.empty()
            end
            link = struct('File', file, 'SubjectID', subjectId, ...
                'ProjectID', projectId, ...
                'ParameterDefaults', epsych.ParameterDefaults.normalize(D), ...
                'State', epsych.ParameterDefaults.emptyState());
        end
    end
end

% -----------------------------------------------------------------------
function v = localBound(v)
% A stored bound as a double scalar; anything else means "keep the protocol's".
if isempty(v) || ~(isnumeric(v) || islogical(v))
    v = NaN;
else
    v = double(v(1));
end
end

% -----------------------------------------------------------------------
function pair = localPairName(P)
% The pairing group compile() expands P in, the way
% epsych.Protocol.getParameterPairName_ reads it.
pair = '';
u = P.UserData;
if ~isstruct(u) || ~isscalar(u), return, end
if isfield(u, 'Pair') && ~isempty(u.Pair)
    pair = strtrim(char(string(u.Pair)));
elseif isfield(u, 'Buddy') && ~isempty(u.Buddy)
    pair = strtrim(char(string(u.Buddy)));
end
end
