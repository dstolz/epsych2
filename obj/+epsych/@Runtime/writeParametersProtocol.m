function writeParametersProtocol(obj, filepath, description)
% writeParametersProtocol(obj, filepath, description)
% Save the current session state as a protocol (.eprot) phase file.
%
% Phases and protocols share one format: saving a phase serializes the session's
% epsych.Protocol. Because the Runtime borrows the Protocol's own hw.Interface
% handles (see RunExpt.ExptDispatch), the protocol's parameters hold the live
% runtime values -- but not all runtime edits land on those handles when they
% are made: a deferred commit (gui.Parameter_Update without the immediate
% modifier) writes only TRIALS.trials until the next trial dispatch, and no
% editing path updates a parameter's design-time Values list at all. The
% serialized snapshot is therefore reconciled with the session's effective
% values (see local_syncRuntimeValues below) so the file records what the
% session is actually running, in both Value and -- for single-level
% parameters -- Values, which a phase load's recompile uses to regenerate the
% trial table. The resulting file opens anywhere a protocol does
% (ProtocolDesigner, RunExpt, epsych.Protocol.load) and loads as a phase via
% readParameters.
%
% The live protocol object is not mutated: the snapshot is serialized directly
% rather than through Protocol.save, which would bump the live protocol's
% version/lastModified metadata as a side effect. The saved file keeps the source
% protocol's version so the phase records its lineage.
%
% Parameters:
%   obj                        The runtime object; obj.Protocol must be set.
%   filepath (1,:) string      Path for the output .eprot file. If not provided,
%                              prompts user to select a location.
%   description (1,1) string   Optional phase description; stored as the saved
%                              protocol's Info text.
%
% See also: readParameters, phaseParameterData, epsych.Protocol.save,
%   writeParametersJSON

arguments
    obj
    filepath (1,:) string = ""
    description (1,1) string = ""
end

assert(~isempty(obj.Protocol) && isvalid(obj.Protocol), ...
    'epsych:Runtime:NoProtocol', ...
    'Runtime.Protocol is not set. It is assigned from the session protocol when the experiment is dispatched (see RunExpt.ExptDispatch); assign it manually for scripted use.');

% If filepath is not provided, prompt user to select file
if filepath == ""
    [fn,pth] = uiputfile({'*.eprot','Phase Protocol (*.eprot)'}, 'Save Current Parameters As Phase Protocol');
    if isequal(fn,0) || isequal(pth,0)
        vprintf(3,'User canceled save operation.')
        return
    end
    filepath = fullfile(pth, fn);
end

[~,~,ext] = fileparts(filepath);
if strlength(ext) == 0
    filepath = filepath + ".eprot";
end

% toStruct captures the live parameter values (shared handles, see above) and
% stamps lastModified itself.
protocol = obj.Protocol.toStruct();

% Overlay the values the session is actually using; toStruct alone misses
% deferred trial-table commits and never refreshes design-time Values.
protocol = local_syncRuntimeValues(obj, protocol);

if strlength(description) > 0
    protocol.Info = char(description);
end

% Same MAT layout as epsych.Protocol.save: a single 'protocol' struct variable.
builtin('save', char(filepath), 'protocol', '-mat');

vprintf(0, 'Phase protocol saved to: %s', filepath)

end


function protocol = local_syncRuntimeValues(obj, protocol)
% protocol = local_syncRuntimeValues(obj, protocol)
% Reconcile the serialized parameter structs with the session's effective values.
%
% Two runtime editing paths leave the serialized snapshot stale:
%   - gui.Parameter_Update's deferred commit writes only TRIALS.trials; the
%     hw.Parameter (and hardware) catch up at the next trial dispatch, so a
%     phase saved before that boundary records the pre-edit Value.
%   - No editing path updates a parameter's design-time Values list, and a
%     phase load schedules a recompile that regenerates the trial table from
%     Values (see readParameters) -- so a phase whose Values list is stale
%     silently reverts the runtime edit at the first trial boundary after load,
%     and ProtocolDesigner displays the stale design values.
%
% For single-level parameters the effective value -- the committed trial-table
% value for dispatched (UpdateEveryTrial) parameters, the current Value
% otherwise -- is written into both Value and Values. Parameters that cannot
% carry a single committed scalar are left untouched: read-only, trigger,
% StimType, expression-driven, randomized, multi-level (roved), and any whose
% trial-table column varies across rows (managed per trial, e.g. by a
% staircase trial selector).

% Committed trial-table values keyed by validName: one entry per writeparam
% column whose rows all agree. A column whose rows differ marks its parameter
% as per-trial managed, exempting it from syncing entirely.
committed = struct;
perTrial = struct;
TR = obj.TRIALS;
if isstruct(TR) && ~isempty(TR) && isfield(TR, 'trials') && isfield(TR, 'writeParamIdx') ...
        && iscell(TR(1).trials) && isstruct(TR(1).writeParamIdx)
    % Phase saves snapshot subject 1's protocol (see RunExpt.ExptDispatch).
    T = TR(1);
    fn = fieldnames(T.writeParamIdx);
    for k = 1:numel(fn)
        col = T.trials(:, T.writeParamIdx.(fn{k}));
        if all(cellfun(@(c) isequaln(c, col{1}), col))
            committed.(fn{k}) = col{1};
        else
            perTrial.(fn{k}) = true;
        end
    end
end

synced = strings(1, 0);
for i = 1:numel(protocol.InterfaceData)
    modules = protocol.InterfaceData{i}.Modules;
    for m = 1:numel(modules)
        params = modules{m}.Parameters;
        for k = 1:numel(params)
            S = params{k};

            if strcmp(S.Access, 'Read') || S.isTrigger || S.isRandom ...
                    || strcmp(S.Type, 'StimType') ...
                    || strlength(string(S.Expression)) > 0 ...
                    || numel(S.Values) > 1
                continue
            end

            vn = matlab.lang.makeValidName(S.Name);
            if isfield(perTrial, vn), continue, end

            % Between trial boundaries the trial table is the source of truth
            % for dispatched parameters (a deferred commit lands there first
            % and dispatch copies it onto the parameter); the live Value is
            % authoritative for everything else.
            if S.UpdateEveryTrial && isfield(committed, vn)
                v = committed.(vn);
            else
                v = S.Value;
            end
            if isempty(v) || (isnumeric(v) && any(isnan(v(:))))
                continue
            end

            if ~isequaln(S.Value, v) || ~isequaln(S.Values, {v})
                synced(end+1) = string(S.Name);
            end
            S.Value = v;
            S.Values = {v};
            params{k} = S;
        end
        modules{m}.Parameters = params;
    end
    protocol.InterfaceData{i}.Modules = modules;
end

if ~isempty(synced)
    vprintf(2, 'Phase save: reconciled %d parameter(s) with runtime values: %s', ...
        numel(synced), strjoin(synced, ', '))
end

end
