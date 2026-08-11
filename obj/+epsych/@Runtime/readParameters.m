function P = readParameters(obj, filepath)
% P = readParameters(obj, filepath)
% Load a phase file (protocol or legacy JSON) and apply its parameters to the runtime.
%
% Phases and protocols share one format: a phase file is an .eprot/.prot protocol
% file (see writeParametersProtocol); legacy JSON snapshots written by
% writeParametersJSON remain loadable. The file is reduced to uniform parameter
% structs by epsych.Runtime.phaseParameterData, then each entry is resolved to the
% live hw.Parameter that owns it (matched to an interface by ParentType and to a
% parameter by Name) and its saved properties are restored.
%
% Serialized metadata and design-time Values are applied via fromStruct; the runtime
% Value is restored here for writable parameters (fromStruct intentionally leaves
% Value untouched for non-StimType parameters when driven this way). When a
% parameter defines an Expression, that expression is the source of truth and its
% evaluated result (the restored design-time Values) is used; otherwise the saved
% literal Value is restored. Writes to disconnected hardware are no-ops, so
% restoring Value is safe whether or not the backend is connected.
%
% Entries with no matching interface or parameter are skipped. Parameters holding
% transient session-control state -- triggers, and the operator's live toggles and
% momentary buttons (hw.Parameter.isTransientControl) -- keep their current value:
% their metadata and design-time Values are restored, but their momentary value is
% owned by the running session, not by the phase.
%
% When a session is running (TRIALS populated), a protocol recompile is scheduled
% at the next safe trial boundary by setting TRIALS.RECOMPILE_REQUESTED (applied
% by ep_TimerFcn_RunTime), so trials regenerate from the loaded phase's design-time
% Values and Expressions — not just its current values.
%
% The resolved parameters are returned so the caller can apply them as needed (e.g.
% updateTrialsFromParameters). This avoids re-reading parameters via all_parameters,
% which would discard the loaded values.
%
% Parameters:
%   obj                  The runtime object to update.
%   filepath (1,:) string
%                        Path to the phase file (.eprot, .prot, or legacy .json).
%                        If not provided or invalid, prompts user to select a file.
%
% Returns:
%   P  hw.Parameter array of the resolved parameters, in file order. Empty if the
%      load is canceled or the file cannot be read.
%
% See also: writeParametersProtocol, phaseParameterData, readParametersJSON,
%   updateTrialsFromParameters, hw.Parameter, epsych.Protocol

arguments
    obj
    filepath (1,:) string = ""
end

P = hw.Parameter.empty(1,0);

% If filepath is not provided or invalid, prompt user to select file
if filepath == "" || ~isfile(filepath)
    [fn,pth] = uigetfile({'*.eprot;*.prot;*.json','Phase Files (*.eprot, *.prot, *.json)'; ...
        '*.*','All Files (*.*)'}, 'Select Phase File to Load Parameters');
    if isequal(fn,0) || isequal(pth,0)
        vprintf(3,'User canceled load operation.')
        return
    end
    filepath = fullfile(pth, fn);
end

[paramData, metadata] = epsych.Runtime.phaseParameterData(filepath);
nP = numel(paramData);

interfaceTypes = arrayfun(@(x) string(x.Type), obj.Interfaces);

% Resolve each file entry to its live hw.Parameter and restore its saved properties.
for k = 1:nP
    S = paramData(k);

    parentType = string(S.ParentType);
    S = rmfield(S, 'ParentType'); % remove ParentType from struct before applying to Parameter since it's not an actual field of hw.Parameter and is only used for matching to the correct interface during load

    vprintf(4,'Processing parameter %d/%d: "%s" (Module: "%s")', k, nP, S.Name, parentType)

    % Match the interface that owns this parameter by its Type
    iface = obj.Interfaces(interfaceTypes == parentType);
    if isempty(iface)
        vprintf(0,1, 'No matching interface found for parameter "%s" with parent "%s". Skipping.', S.Name, parentType)
        continue
    end

    xp = iface(1).find_parameter(S.Name,includeInvisible=true);
    if isempty(xp)
        % find_parameter already warned; nothing to resolve against.
        continue
    end
    xp = xp(1);

    % Restore metadata and design-time Values. fromStruct deliberately leaves the runtime Value
    % alone, so set it here for writable, non-StimType parameters (StimType Value is handled by
    % fromStruct). When the parameter defines an Expression, that expression is the source of
    % truth: its evaluated result is the restored (design-time) Values, so derive the value from
    % those rather than the saved literal, which may have drifted from the expression at save
    % time. Otherwise restore the saved literal value. The set.Value setter clamps to bounds and
    % disconnected backends ignore the hardware write.
    % The Expression is protocol structure, not per-phase operator state: a
    % snapshot saved before the protocol defined an expression stores "",
    % which must not erase the live expression (dispatch would then silently
    % pass the compiled trial value through instead of recomputing, e.g.
    % RespWinDelay stuck at its compile-time value). A non-empty expression
    % in the file is applied deliberately.
    % Transient session-control state (triggers, operator toggles) is excluded
    % from the Value restore: it belongs to the live session, not the phase.
    % Restoring it would re-assert a button press captured whenever the phase
    % was saved -- a phase saved with "Deliver Trials" active would start
    % delivering trials on load. Metadata and design-time Values are still
    % restored, so the parameter's definition travels with the phase; only its
    % momentary value is left alone.
    restoreValue = ~hw.Parameter.isTransientControl(S);

    liveExpression = xp.Expression;
    xp.fromStruct(S, restoreValue);
    if strlength(xp.Expression) == 0 && strlength(liveExpression) > 0
        xp.Expression = liveExpression;
    end
    if restoreValue && ~strcmp(xp.Type,'StimType') && ~strcmp(xp.Access,'Read')
        if strlength(xp.Expression) > 0 && ~isempty(xp.Values)
            xp.Value = xp.Values{1};
        end
    end

    if ~restoreValue
        vprintf(3, 'Phase load: kept live value of session-control parameter "%s"', xp.Name)
    end

    P(end+1) = xp;
end

% A phase can change design-time structure (Values lists, Expressions), not just
% current values, so schedule a protocol recompile at the next safe trial
% boundary (ep_TimerFcn_RunTime regenerates TRIALS.trials from the protocol,
% whose parameters were just updated above). Outside a running session TRIALS is
% empty and trials are compiled at session start, so there is nothing to
% schedule. Subjects running a different protocol object are skipped: their
% parameters were not touched by this load, and recompiling them would only
% reset their selector state.
if ~isempty(P) && isstruct(obj.TRIALS) && isfield(obj.TRIALS, 'RECOMPILE_REQUESTED')
    TRIALS = obj.TRIALS;
    scheduled = 0;
    for i = 1:numel(TRIALS)
        if isfield(TRIALS, 'protocol') && isa(TRIALS(i).protocol, 'epsych.Protocol') ...
                && ~isempty(obj.Protocol) && TRIALS(i).protocol ~= obj.Protocol
            continue
        end
        TRIALS(i).RECOMPILE_REQUESTED = true;
        scheduled = scheduled + 1;
    end
    obj.TRIALS = TRIALS;
    if scheduled > 0
        vprintf(1, 'Phase load: protocol recompile scheduled at the next trial boundary for %d subject(s).', scheduled)
    end
end

% append metadata about the loaded phase to the obj.Phase property (create if it doesn't exist). This can be used by the GUI to display information about the currently loaded phase.
if ~isprop(obj,'Phase'), obj.addprop('Phase'); end
obj.Phase(end+1).Description = metadata.Description;
obj.Phase(end).ParametersLoaded = true;
obj.Phase(end).FilePath = filepath;
obj.Phase(end).JSONPath = filepath; % legacy field name kept for scripts written against the JSON-only phase format
obj.Phase(end).ParameterData = paramData;
obj.Phase(end).LoadTimestamp = datetime('now');
obj.Phase(end).Source = metadata.Source;
obj.Phase(end).Metadata = metadata.Extra;

vprintf(3, 'Read %d parameters from %s', numel(P), filepath)

end
