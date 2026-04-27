function showParameterDetailsDialog(obj, parameter)
% showParameterDetailsDialog(obj, parameter)
% Open a detail uifigure for a single parameter.
% Displays all metadata, current value, expression info, expression
% aliases, pair membership, and other parameters that reference this one.
%
% Parameters:
%   parameter   - hw.Parameter instance to inspect.

% ---- gather relational data ----
allParameters   = obj.getAllParameters();
expressionText  = obj.getParameterExpression(parameter);
pairName        = obj.getParameterPair(parameter);
expressionError = obj.getExpressionErrorMessage(parameter);
aliases         = obj.getExpressionAliases(parameter, allParameters);

pairedParams = hw.Parameter.empty(1, 0);
if ~isempty(pairName)
    for idx = 1:numel(allParameters)
        if ~isequal(allParameters(idx), parameter) && ...
                strcmp(obj.getParameterPair(allParameters(idx)), pairName)
            pairedParams(end + 1) = allParameters(idx); %#ok<AGROW>
        end
    end
end

referencingParams = hw.Parameter.empty(1, 0);
for idx = 1:numel(allParameters)
    if isequal(allParameters(idx), parameter)
        continue
    end
    refExpr = obj.getParameterExpression(allParameters(idx));
    if isempty(refExpr)
        continue
    end
    for aliasIdx = 1:numel(aliases)
        if contains(refExpr, aliases{aliasIdx})
            referencingParams(end + 1) = allParameters(idx); %#ok<AGROW>
            break
        end
    end
end

% ---- build formatted text lines ----
lines = {};

    function addSection(title)
        if ~isempty(lines)
            lines{end + 1} = '';
        end
        sep = repmat(char(9472), 1, max(0, 46 - strlength(title) - 1));
        lines{end + 1} = [upper(title) ' ' sep];
    end

    function addField(label, value)
        lines{end + 1} = sprintf('  %-22s  %s', [label ':'], value);
    end

    function addText(text)
        lines{end + 1} = ['  ' text];
    end

% Identity
addSection('Identity');
addField('Name',        parameter.Name);
addField('Type',        parameter.Type);
addField('Module',      parameter.Module.Name);
addField('Interface',   localInterfaceName_(parameter));
addField('Access',      parameter.Access);
addField('Unit',        localOrDash_(parameter.Unit));
addField('Visible',     localBoolLabel_(parameter.Visible));
addField('Trigger',     localBoolLabel_(parameter.isTrigger));
addField('Random',      localBoolLabel_(parameter.isRandom));
addField('Array',       localBoolLabel_(parameter.isArray));
addField('Min',         localNumLabel_(parameter.Min));
addField('Max',         localNumLabel_(parameter.Max));
if strlength(string(parameter.Description)) > 0
    addField('Description', char(string(parameter.Description)));
end

% Value
addSection('Value');
fullValue = obj.getParameterValueFull(parameter);
if isempty(fullValue)
    addField('Current Value', '(empty)');
elseif isnumeric(fullValue) || islogical(fullValue)
    addField('Current Value', mat2str(fullValue));
else
    valueStr = char(string(fullValue));
    valueLines = strsplit(valueStr, newline);
    addField('Current Value', valueLines{1});
    for vIdx = 2:numel(valueLines)
        addText(['  ' valueLines{vIdx}]);
    end
end
if parameter.lastUpdated > 0
    dt = datetime(parameter.lastUpdated, 'ConvertFrom', 'datenum', 'TimeZone', 'local');
    addField('Last Updated', char(dt, 'yyyy-MM-dd HH:mm:ss'));
end

% Expression
addSection('Expression');
addField('Alias(es)', strjoin(aliases, ',  '));
if ~isempty(expressionText)
    addField('Expression', expressionText);
end
if ~isempty(expressionError)
    addText(['[!] ' expressionError]);
end
if isempty(expressionText) && isempty(expressionError)
    addText('(none)');
end

% Pair membership
if ~isempty(pairName)
    addSection(sprintf('Pair: %s', pairName));
    if isempty(pairedParams)
        addText('(only member in this pair)');
    else
        for idx = 1:numel(pairedParams)
            p = pairedParams(idx);
            valueCount = localValueCount_(p.Values);
            addField(sprintf('%s.%s', p.Module.Name, p.Name), ...
                sprintf('%s  |  %d value(s)', p.Type, valueCount));
        end
    end
end

% Referenced by
if ~isempty(referencingParams)
    addSection('Referenced by Expressions in');
    for idx = 1:numel(referencingParams)
        p = referencingParams(idx);
        addField(sprintf('%s.%s', p.Module.Name, p.Name), ...
            obj.getParameterExpression(p));
    end
end

% ---- build UI ----
fig = uifigure( ...
    'Name', sprintf('Parameter Details  —  %s', parameter.Name), ...
    'Position', [200 150 560 480], ...
    'Resize', 'on', ...
    'Color', [0.965 0.970 0.980]);

uitextarea(fig, ...
    'Value', lines, ...
    'Position', [10 46 540 424], ...
    'Editable', 'off', ...
    'FontName', 'Courier New', ...
    'FontSize', 11, ...
    'BackgroundColor', [0.994 0.996 1.000], ...
    'FontColor', [0.06 0.09 0.14]);

uibutton(fig, 'push', ...
    'Text', 'Close', ...
    'Position', [230 10 100 28], ...
    'FontWeight', 'bold', ...
    'ButtonPushedFcn', @(~, ~) close(fig));
end

% ---- local helpers ----

function label = localBoolLabel_(tf)
    if tf
        label = 'Yes';
    else
        label = 'No';
    end
end

function label = localNumLabel_(value)
    if isinf(value)
        if value > 0
            label = '+Inf';
        else
            label = '-Inf';
        end
    else
        label = num2str(value);
    end
end

function label = localOrDash_(text)
    if isempty(text)
        label = char(8212);
    else
        label = char(string(text));
    end
end

function name = localInterfaceName_(parameter)
    name = char(8212);
    try
        iface = parameter.Module.parent;
        if ischar(iface.Type) || isstring(iface.Type)
            name = char(iface.Type);
        end
    catch
    end
end

function count = localValueCount_(values)
    count = numel(values);
end
