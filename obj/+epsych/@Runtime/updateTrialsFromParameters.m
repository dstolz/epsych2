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

    vprintf(3, 'Updating TRIALS information from %d parameters: %s', numel(Parameters), strjoin({Parameters.Name},', '))
    for k = 1:numel(Parameters)
        pName = Parameters(k).Name;
        pVal = Parameters(k).Value;

        idx = obj.TRIALS.writeParamIdx.(pName);
        obj.TRIALS.trials(:,idx) = {pVal};
    end
end
