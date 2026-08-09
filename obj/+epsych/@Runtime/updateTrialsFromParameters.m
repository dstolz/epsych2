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

    ind = ismember({Parameters.Name}, obj.TRIALS.writeparams);
    Parameters(~ind) = [];

    if isempty(Parameters), return, end

    vprintf(3, 'Updating TRIALS information from %d parameters: %s', numel(Parameters), strjoin({Parameters.Name},', '))

    % Mutate a local copy and assign back once. Writing directly to
    % obj.TRIALS.trials(:,idx) inside the loop would re-trigger the
    % set.TRIALS setter (and its per-subject resolveCoreParameters /
    % dispatchNextTrial) on every iteration, dispatching trials over and
    % over. Batching the writes fires the setter a single time.
    TRIALS = obj.TRIALS;
    for k = 1:numel(Parameters)
        pName = Parameters(k).Name;
        pVal = Parameters(k).Value;

        idx = TRIALS.writeParamIdx.(pName);
        TRIALS.trials(:,idx) = {pVal};
    end
    obj.TRIALS = TRIALS;
end
