function updateTrialsFromParameters(obj, Parameters)
    % updateTrialsFromParameters(obj, Parameters)
    % Sync writable TRIALS fields from current parameter values. Updates obj.TRIALS in-place.
    %
    % Parameters:
    %   obj        - epsych.Runtime instance.
    %   Parameters - hw.Parameter array to sync from; non-writable entries are ignored.

    arguments
        obj
        Parameters (1,:) hw.Parameter
    end

    % Before the session compiles TRIALS there is no trial table to sync
    % (e.g. an autoCommit gui.components.Parameter_Control edit made pre-run), so this
    % is a no-op rather than an error.
    if ~isstruct(obj.TRIALS) || isempty(obj.TRIALS) || ~isfield(obj.TRIALS, 'writeparams')
        return
    end

    ind = ismember({Parameters.Name}, obj.TRIALS.writeparams);
    Parameters(~ind) = [];

    if isempty(Parameters), return, end

    vprintf(3, 'Updating TRIALS information from %d parameters: %s', numel(Parameters), strjoin({Parameters.Name},', '))

    % Mutate a local copy and assign back once. Writing directly to
    % obj.TRIALS.trials(:,idx) inside the loop would re-trigger the
    % set.TRIALS setter (and its per-subject resolveTriggerParameters /
    % dispatchNextTrial) on every iteration, dispatching trials over and
    % over. Batching the writes fires the setter a single time.
    TRIALS = obj.TRIALS;
    for k = 1:numel(Parameters)
        pName = Parameters(k).Name;
        % A write-only parameter cannot be read back: get.Value logs a
        % critical record and returns NaN, which would then be written into
        % every trial row and dispatched to hardware. Its design-time level
        % is what a phase load just restored, so use that.
        if isequal(Parameters(k).Access, 'Write')
            if isempty(Parameters(k).Values)
                continue
            end
            pVal = Parameters(k).Values{1};
        else
            pVal = Parameters(k).Value;
        end

        idx = TRIALS.writeParamIdx.(pName);
        TRIALS.trials(:,idx) = {pVal};
    end
    obj.TRIALS = TRIALS;
end
