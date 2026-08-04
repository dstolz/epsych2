function [coefValue, cancelled] = editParameterCoefficientBufferValue(obj, parameter)
    % [coefValue, cancelled] = editParameterCoefficientBufferValue(obj, parameter)
    % Open the modal coefficient-buffer editor for one Coefficient Buffer parameter.
    % Coefficients can be pasted as free-form numeric text or extracted from the
    % equalization filter stored in a stimgen calibration (.esgc) file.
    %
    % Parameters:
    % 	parameter	- Coefficient Buffer parameter being edited.
    %
    % Returns:
    % 	coefValue	- Numeric row vector of filter coefficients ([] to clear).
    % 	cancelled	- True when the dialog is dismissed without Apply.

    currentCoefs = localFlattenBufferValues_(parameter.Values);

    dialog = uifigure( ...
        'Name', sprintf('Edit Coefficient Buffer: %s', parameter.Name), ...
        'Position', [240 190 760 500], ...
        'WindowStyle', 'modal', ...
        'Resize', 'off');

    uilabel(dialog, ...
        'Text', sprintf('Coefficient buffer for %s', parameter.Name), ...
        'Position', [20 458 400 22], ...
        'FontSize', 14, ...
        'FontWeight', 'bold');

    uilabel(dialog, ...
        'Text', ['Paste filter coefficients below (numbers separated by spaces, commas, semicolons, or newlines), ' ...
                 'or extract them from a calibration file.'], ...
        'Position', [20 430 700 18], ...
        'FontAngle', 'italic');

    inputArea = uitextarea(dialog, ...
        'Position', [20 150 720 270], ...
        'Value', localFormatCoefficients_(currentCoefs), ...
        'ValueChangedFcn', @(~, ~) updateParseState(), ...
        'BackgroundColor', [0.997 0.998 0.999]);

    countLabel = uilabel(dialog, ...
        'Text', '', ...
        'Position', [20 120 460 18], ...
        'FontColor', [0.35 0.42 0.52]);

    sourceLabel = uilabel(dialog, ...
        'Text', '', ...
        'Position', [20 98 700 18], ...
        'FontAngle', 'italic', ...
        'FontColor', [0.35 0.42 0.52]);

    uibutton(dialog, 'push', ...
        'Text', 'Extract from Calibration File...', ...
        'Position', [20 20 210 32], ...
        'Tooltip', 'Load the equalization FIR filter coefficients from a stimgen calibration (.esgc) file.', ...
        'ButtonPushedFcn', @onExtractFromCalibration);

    uibutton(dialog, 'push', ...
        'Text', 'Clear', ...
        'Position', [242 20 90 32], ...
        'ButtonPushedFcn', @onClear);

    uibutton(dialog, 'push', ...
        'Text', 'Cancel', ...
        'Position', [528 20 90 32], ...
        'ButtonPushedFcn', @(~, ~) delete(dialog));

    applied = false;
    applyButton = uibutton(dialog, 'push', ...
        'Text', 'Apply', ...
        'Position', [630 20 90 32], ...
        'FontWeight', 'bold', ...
        'ButtonPushedFcn', @onApply);

    updateParseState();
    uiwait(dialog);

    if ~applied
        coefValue = [];
        cancelled = true;
        if isvalid(dialog)
            delete(dialog);
        end
        return
    end

    coefValue = currentCoefs;
    cancelled = false;
    if isvalid(dialog)
        delete(dialog);
    end

    function onExtractFromCalibration(~, ~)
        startPath = obj.getLastBrowseDirectory();
        if isempty(startPath) || ~isfolder(startPath)
            startPath = pwd;
        end

        [fileName, pathName] = uigetfile( ...
            {'*.esgc', 'EPsych Stim Calibration (*.esgc)'}, ...
            'Extract Coefficients from Calibration', startPath);
        figure(dialog); % uigetfile drops modal focus
        if isequal(fileName, 0)
            return
        end
        obj.setLastBrowseDirectory(pathName);
        calibrationFile = fullfile(pathName, fileName);

        try
            engine = stimgen.calibration.Engine.load(calibrationFile);
        catch ME
            vprintf(0, 1, ME);
            uialert(dialog, sprintf('Unable to load calibration file:\n%s', ME.message), ...
                'Calibration Load Failed');
            return
        end

        calData = engine.CalibrationData;
        if ~isstruct(calData) || ~isfield(calData, 'filter') || isempty(calData.filter)
            uialert(dialog, ...
                ['The selected calibration has no equalization filter. ' ...
                 'Design one in the calibration GUI (Design Filter), save the calibration, and try again.'], ...
                'No Filter in Calibration');
            return
        end

        filt = calData.filter;
        if isa(filt, 'digitalFilter')
            coefs = filt.Coefficients;
        elseif isnumeric(filt)
            coefs = filt;
        else
            uialert(dialog, sprintf('Unsupported filter representation in calibration file: %s', class(filt)), ...
                'Unsupported Filter');
            return
        end

        coefs = double(reshape(coefs, 1, []));
        inputArea.Value = localFormatCoefficients_(coefs);
        sourceLabel.Text = localDescribeFilterSource_(fileName, calData, coefs);
        updateParseState();
    end

    function onClear(~, ~)
        inputArea.Value = {''};
        sourceLabel.Text = '';
        updateParseState();
    end

    function onApply(~, ~)
        [coefs, parseError] = localParseCoefficients_(inputArea.Value);
        if ~isempty(parseError)
            uialert(dialog, parseError, 'Invalid Coefficients');
            return
        end
        currentCoefs = coefs;
        applied = true;
        delete(dialog);
    end

    function updateParseState()
        [coefs, parseError] = localParseCoefficients_(inputArea.Value);
        if ~isempty(parseError)
            countLabel.Text = parseError;
            countLabel.FontColor = [0.75 0.2 0.2];
            applyButton.Enable = 'off';
            return
        end

        applyButton.Enable = 'on';
        countLabel.FontColor = [0.35 0.42 0.52];
        if isempty(coefs)
            countLabel.Text = 'No coefficients entered. Apply clears the buffer.';
        else
            countLabel.Text = sprintf('%d coefficients.', numel(coefs));
        end
    end
end


function coefs = localFlattenBufferValues_(values)
    % Existing Values may be {} / {vector} / legacy per-sample scalar cells.
    coefs = [];
    if isempty(values)
        return
    end
    for idx = 1:numel(values)
        v = values{idx};
        if isnumeric(v) || islogical(v)
            coefs = [coefs, double(reshape(v, 1, []))]; %#ok<AGROW>
        end
    end
end


function lines = localFormatCoefficients_(coefs)
    if isempty(coefs)
        lines = {''};
        return
    end
    % %.15g round-trips double-precision FIR taps without loss.
    parts = compose("%.15g", coefs);
    lines = {char(strjoin(parts, ' '))};
end


function [coefs, parseError] = localParseCoefficients_(rawLines)
    parseError = '';
    text = strjoin(cellstr(rawLines), ' ');

    % Accept bracketed MATLAB-style vectors and common list separators.
    text = regexprep(text, '[\[\],;]', ' ');
    text = strtrim(text);
    if isempty(text)
        coefs = [];
        return
    end

    [coefs, ~, errMsg, nextIndex] = sscanf(text, '%f');
    remainder = strtrim(text(min(nextIndex, numel(text) + 1):end));
    if ~isempty(errMsg) || ~isempty(remainder)
        coefs = [];
        parseError = sprintf('Could not parse coefficients near: "%s"', ...
            localTruncateText_(remainder, 40));
        return
    end

    coefs = reshape(coefs, 1, []);
    if any(~isfinite(coefs))
        coefs = [];
        parseError = 'Coefficients must be finite (no NaN or Inf values).';
    end
end


function text = localTruncateText_(text, maxLength)
    if isempty(text)
        text = '...';
    elseif numel(text) > maxLength
        text = [text(1:maxLength) '...'];
    end
end


function description = localDescribeFilterSource_(fileName, calData, coefs)
    details = {sprintf('%d taps', numel(coefs))};
    if isfield(calData, 'filterSource') && strlength(string(calData.filterSource)) > 0
        details{end + 1} = sprintf('%s LUT', calData.filterSource);
    end
    if isfield(calData, 'filterDesign') && isstruct(calData.filterDesign)
        design = calData.filterDesign;
        if isfield(design, 'sampleRate')
            details{end + 1} = sprintf('Fs = %.4f Hz', design.sampleRate);
        end
        if isfield(design, 'designedOn')
            details{end + 1} = sprintf('designed %s', string(design.designedOn));
        end
    end
    description = sprintf('Extracted from %s (%s)', fileName, strjoin(details, ', '));
end
