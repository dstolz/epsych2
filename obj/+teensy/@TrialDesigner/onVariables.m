function onVariables(obj, verb, varargin)
% onVariables(obj, verb, varargin)
% Handle every Variables-tab action.
%
% Parameters
%   verb - 'edited', 'selected', 'add', 'remove', 'addTimer', 'addCounter',
%       'usageSelected'.
%   varargin - Verb-specific arguments.
%
% See also: teensy.Program.parameterSpecs

arguments
    obj (1,1) teensy.TrialDesigner
    verb (1,:) char
end
arguments (Repeating)
    varargin
end

P = obj.Program;

switch verb

    case 'selected'
        evt = varargin{1};
        if isempty(evt.Indices)
            return
        end
        obj.SelectedVariable = evt.Indices(1, 1);
        obj.refreshAll();
        obj.setStatus(sprintf('Selected variable %s.', ...
            P.Variables(obj.SelectedVariable).Name));

    case 'edited'
        evt = varargin{1};
        row = evt.Indices(1, 1);
        col = evt.Indices(1, 2);
        obj.pushUndo('Edit Variable');

        columns = {'Name', 'Type', 'Value', 'Min', 'Max', 'Units', ...
            'UpdateEveryTrial', 'Description'};
        field = columns{col};

        try
            if strcmp(field, 'Name')
                P.renameVariable(P.Variables(row).Name, string(evt.NewData));
            elseif ismember(field, {'Type', 'Units', 'Description'})
                P.Variables(row).(field) = string(evt.NewData);
                P.touch();
            elseif strcmp(field, 'UpdateEveryTrial')
                P.Variables(row).(field) = logical(evt.NewData);
                P.touch();
            else
                P.Variables(row).(field) = double(evt.NewData);
                P.touch();
            end
        catch ME
            vprintf(0, 1, ME);
            obj.refreshAll();
            obj.setStatus(sprintf('Cannot set %s: %s', field, ME.message));
            return
        end

        obj.refreshAll();
        obj.setStatus(sprintf('Updated %s.', field));

    case 'add'
        obj.pushUndo('Add Variable');
        v = P.addVariable(teensy.Variable("NewVar", Value = 100, ...
            Min = 0, Max = 10000, Units = "ms", ...
            Description = "Describe what this controls."));
        obj.SelectedVariable = numel(P.Variables);
        obj.refreshAll();
        obj.setStatus(sprintf('Added variable %s.', v.Name), ...
            'Reference it from a duration or threshold with the variable dropdown.');

    case 'remove'
        if obj.SelectedVariable == 0
            obj.setStatus('Select a variable to remove.');
            return
        end

        name = P.Variables(obj.SelectedVariable).Name;
        obj.pushUndo('Remove Variable');
        P.removeVariable(name);
        obj.SelectedVariable = min(obj.SelectedVariable, numel(P.Variables));
        obj.refreshAll();
        obj.setStatus(sprintf('Removed %s. Any reference to it is now an error.', name));

    case 'addTimer'
        answer = obj.promptFields_('Add Global Timer', { ...
            'Name', 'Timer1', 'text'; ...
            'DurationMs', 1000, 'numeric'});
        if isempty(answer)
            return
        end

        obj.pushUndo('Add Timer');
        P.addTimer(string(answer.Name), answer.DurationMs);
        obj.refreshAll();
        obj.setStatus(sprintf('Added timer %s.', answer.Name), ...
            'Start it with a Start Timer action, then test it with a Global Timer condition.');

    case 'addCounter'
        inputs = localInputNames_(P);
        if isempty(inputs)
            obj.setStatus('Add an input channel before adding a counter.');
            return
        end

        answer = obj.promptFields_('Add Counter', { ...
            'Name', 'Count1', 'text'; ...
            'Channel', char(inputs(1)), ['choice:' strjoin(cellstr(inputs), '|')]; ...
            'Edge', 'Rising', 'choice:Rising|Falling|Either'});
        if isempty(answer)
            return
        end

        obj.pushUndo('Add Counter');
        P.addCounter(string(answer.Name), string(answer.Channel), string(answer.Edge));
        obj.refreshAll();
        obj.setStatus(sprintf('Added counter %s on %s.', answer.Name, answer.Channel), ...
            'Test it with a Counter condition, and clear it with a Reset Counter action.');

    case 'usageSelected'
        evt = varargin{1};
        if isempty(evt.Indices) || obj.SelectedVariable == 0
            return
        end

        row = evt.Indices(1, 1);
        stateName = obj.HVariables.Usage.Data{row, 1};
        idx = P.stateIndex(stateName);
        if idx == 0
            return
        end

        obj.SelectedState = idx;
        obj.TabGroup.SelectedTab = obj.HStates.Tab;
        obj.refreshAll();
        obj.setStatus(sprintf('Jumped to state %s.', stateName));

end
end


function names = localInputNames_(program)
% names = localInputNames_(program)
% Input channel names, for the counter source dropdown.
names = strings(1, 0);
for i = 1:numel(program.Channels)
    if program.Channels(i).Direction == "Input"
        names(end+1) = program.Channels(i).Name;
    end
end
end
