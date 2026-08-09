function onStates(obj, verb, varargin)
% onStates(obj, verb, varargin)
% Handle every States-tab action.
%
% Parameters
%   verb - 'selected', 'add', 'duplicate', 'rename', 'remove', 'setstart',
%       'terminal', 'up', 'down', 'field', 'durationVar', 'respcode',
%       'addAction', 'editAction', 'removeAction', 'actionSelected',
%       'addTrans', 'editTrans', 'removeTrans', 'transUp', 'transDown',
%       'transSelected', 'autolayout', 'snap'.
%   varargin - Verb-specific arguments.
%
% See also: teensy.TrialDesigner.drawDiagram, teensy.TrialDesigner.editCondition_

arguments
    obj (1,1) teensy.TrialDesigner
    verb (1,:) char
end
arguments (Repeating)
    varargin
end

P = obj.Program;
idx = obj.SelectedState;

switch verb

    case 'selected'
        src = varargin{1};
        if isempty(src.Value)
            return
        end
        obj.SelectedState = src.Value;
        obj.refreshAll();
        obj.setStatus(sprintf('Selected state %s.', P.States(obj.SelectedState).Name));

    case 'select'
        obj.SelectedState = varargin{1};
        obj.refreshAll();

    case 'add'
        obj.pushUndo('Add State');
        s = P.addState(teensy.State("NewState", DurationMs = 1000));
        P.States(end).Position = [0.5 0.5];
        obj.SelectedState = numel(P.States);
        obj.refreshAll();
        obj.setStatus(sprintf('Added %s.', s.Name), ...
            'Give it a duration and a transition out.');

    case 'duplicate'
        if idx == 0
            obj.setStatus('Select a state to duplicate.');
            return
        end
        obj.pushUndo('Duplicate State');
        s = P.States(idx);
        s.Position = s.Position + [0.04 -0.06];
        added = P.addState(s);
        obj.SelectedState = numel(P.States);
        obj.refreshAll();
        obj.setStatus(sprintf('Duplicated as %s.', added.Name));

    case 'rename'
        if idx == 0
            return
        end
        answer = obj.promptFields_('Rename State', ...
            {'Name', char(P.States(idx).Name), 'text'});
        if isempty(answer)
            return
        end
        obj.pushUndo('Rename State');
        old = P.States(idx).Name;
        P.renameState(old, string(answer.Name));
        obj.refreshAll();
        obj.setStatus(sprintf('Renamed %s to %s; transitions were rewritten.', ...
            old, P.States(idx).Name));

    case 'remove'
        if idx == 0
            obj.setStatus('Select a state to remove.');
            return
        end

        name = P.States(idx).Name;
        incoming = localIncoming_(P, name);
        if ~isempty(incoming)
            answer = uiconfirm(obj.Figure, ...
                sprintf(['%d transition(s) point at %s. Removing it leaves them ' ...
                    'targeting a state that does not exist, which validation ' ...
                    'reports as an error.'], numel(incoming), name), ...
                'State In Use', Options = {'Remove Anyway', 'Cancel'}, ...
                DefaultOption = 'Cancel', CancelOption = 'Cancel', Icon = 'warning');
            if ~strcmp(answer, 'Remove Anyway')
                return
            end
        end

        obj.pushUndo('Remove State');
        P.removeState(name);
        obj.SelectedState = min(idx, numel(P.States));
        obj.refreshAll();
        obj.setStatus(sprintf('Removed %s.', name));

    case 'setstart'
        if idx == 0
            return
        end
        obj.pushUndo('Set Start State');
        P.StartState = P.States(idx).Name;
        P.touch();
        obj.refreshAll();
        obj.setStatus(sprintf('Trials now begin in %s.', P.StartState));

    case 'terminal'
        if idx == 0
            return
        end
        obj.pushUndo('Toggle Terminal');
        P.States(idx).IsTerminal = ~P.States(idx).IsTerminal;
        P.touch();
        obj.refreshAll();
        if P.States(idx).IsTerminal
            obj.setStatus(sprintf('%s now ends the trial.', P.States(idx).Name), ...
                'Give it response bits so the outcome is not Undefined.');
        else
            obj.setStatus(sprintf('%s no longer ends the trial.', P.States(idx).Name));
        end

    case {'up', 'down'}
        if idx == 0
            return
        end
        obj.pushUndo('Reorder States');
        offset = -1;
        if strcmp(verb, 'down')
            offset = 1;
        end
        name = P.States(idx).Name;
        P.moveState(name, offset);
        obj.SelectedState = P.stateIndex(name);
        obj.refreshAll();
        obj.setStatus('Reordered the state list.');

    case 'field'
        if idx == 0
            return
        end
        field = varargin{1};
        value = varargin{2};
        obj.pushUndo('Edit State');

        switch field
            case 'Name'
                P.renameState(P.States(idx).Name, string(value));
            case 'Notes'
                P.States(idx).Notes = string(strjoin(cellstr(value), newline));
                P.touch();
            case 'DurationMs'
                P.States(idx).DurationMs = double(value);
                P.touch();
            case 'IsTerminal'
                P.States(idx).IsTerminal = logical(value);
                P.touch();
        end

        obj.refreshAll();
        obj.setStatus(sprintf('Updated %s.', field));

    case 'durationVar'
        if idx == 0
            return
        end
        choice = varargin{1};
        obj.pushUndo('Set Duration Source');

        if strcmp(choice, 'literal')
            P.States(idx).DurationMs = obj.Program.resolve(P.States(idx).DurationMs);
            obj.setStatus('The duration is now a fixed number.');
        else
            P.States(idx).DurationMs = teensy.varRef(choice);
            obj.setStatus(sprintf('The duration now follows the %s variable.', choice), ...
                'Per-trial variables become trial-table columns in the Protocol Designer.');
        end

        P.touch();
        obj.refreshAll();

    case 'respcode'
        if idx == 0
            return
        end
        mask = P.States(idx).respMask();
        newMask = obj.pickBitMask_(mask, char(P.States(idx).Name));
        if isempty(newMask)
            return
        end

        obj.pushUndo('Set Response Code');
        [~, bits] = epsych.BitMask.Mask2Bits(uint32(newMask), 32);
        P.States(idx).RespCodeBits = reshape(bits{1}, 1, []);
        P.touch();
        obj.refreshAll();
        obj.setStatus(sprintf('Set the response code for %s.', P.States(idx).Name));

    case 'actionSelected'
        evt = varargin{1};
        if ~isempty(evt.Indices)
            obj.HStates.SelectedAction = evt.Indices(1, 1);
        end

    case 'transSelected'
        evt = varargin{1};
        if ~isempty(evt.Indices)
            obj.HStates.SelectedTransition = evt.Indices(1, 1);
        end

    case 'addAction'
        if idx == 0
            obj.setStatus('Select a state first.');
            return
        end
        which = varargin{1};
        action = obj.editAction_(teensy.Action("SetOutput"));
        if isempty(action)
            return
        end

        obj.pushUndo('Add Action');
        if strcmp(which, 'entry')
            P.States(idx).EntryActions(end+1) = action;
        else
            P.States(idx).ExitActions(end+1) = action;
        end
        P.touch();
        obj.refreshAll();
        obj.setStatus(sprintf('Added %s action: %s.', which, action.describe()));

    case 'editAction'
        [which, k] = localActionAt_(obj, P, idx);
        if k == 0
            obj.setStatus('Select an action to edit.');
            return
        end

        if strcmp(which, 'entry')
            current = P.States(idx).EntryActions(k);
        else
            current = P.States(idx).ExitActions(k);
        end

        action = obj.editAction_(current);
        if isempty(action)
            return
        end

        obj.pushUndo('Edit Action');
        if strcmp(which, 'entry')
            P.States(idx).EntryActions(k) = action;
        else
            P.States(idx).ExitActions(k) = action;
        end
        P.touch();
        obj.refreshAll();
        obj.setStatus(sprintf('Updated the action: %s.', action.describe()));

    case 'removeAction'
        [which, k] = localActionAt_(obj, P, idx);
        if k == 0
            obj.setStatus('Select an action to remove.');
            return
        end

        obj.pushUndo('Remove Action');
        if strcmp(which, 'entry')
            P.States(idx).EntryActions(k) = [];
        else
            P.States(idx).ExitActions(k) = [];
        end
        P.touch();
        obj.refreshAll();
        obj.setStatus('Removed the action.');

    case 'addTrans'
        if idx == 0
            obj.setStatus('Select a state first.');
            return
        end
        if numel(P.States) < 2
            obj.setStatus('Add another state to transition to first.');
            return
        end

        t = obj.editTransition_(teensy.Transition.to(P.States(min(idx + 1, end)).Name, ...
            teensy.Condition.timerElapsed()), idx);
        if isempty(t)
            return
        end

        obj.pushUndo('Add Transition');
        P.States(idx).Transitions(end+1) = t;
        P.touch();
        obj.refreshAll();
        obj.setStatus(sprintf('Added a transition to %s.', t.Target));

    case 'editTrans'
        k = localTransAt_(obj);
        if idx == 0 || k == 0 || k > numel(P.States(idx).Transitions)
            obj.setStatus('Select a transition to edit.');
            return
        end

        t = obj.editTransition_(P.States(idx).Transitions(k), idx);
        if isempty(t)
            return
        end

        obj.pushUndo('Edit Transition');
        P.States(idx).Transitions(k) = t;
        P.touch();
        obj.refreshAll();
        obj.setStatus('Updated the transition.');

    case 'removeTrans'
        k = localTransAt_(obj);
        if idx == 0 || k == 0 || k > numel(P.States(idx).Transitions)
            obj.setStatus('Select a transition to remove.');
            return
        end

        obj.pushUndo('Remove Transition');
        P.States(idx).Transitions(k) = [];
        P.touch();
        obj.refreshAll();
        obj.setStatus('Removed the transition.');

    case {'transUp', 'transDown'}
        k = localTransAt_(obj);
        if idx == 0 || k == 0
            return
        end

        T = P.States(idx).Transitions;
        target = k - 1;
        if strcmp(verb, 'transDown')
            target = k + 1;
        end
        if target < 1 || target > numel(T)
            return
        end

        obj.pushUndo('Reorder Transitions');
        T([k target]) = T([target k]);
        P.States(idx).Transitions = T;
        P.touch();
        obj.HStates.SelectedTransition = target;
        obj.refreshAll();
        obj.setStatus('Reordered the transitions; the first match wins.');

    case 'autolayout'
        obj.pushUndo('Auto Layout');
        P.autoLayout();
        obj.refreshAll();
        obj.setStatus('Laid the diagram out by transition depth.');

    case 'snap'
        src = varargin{1};
        src.Checked = matlab.lang.OnOffSwitchState(~strcmp(src.Checked, 'on'));
        obj.HStates.Snap = strcmp(src.Checked, 'on');
        obj.setStatus('Toggled snap to grid.');

end
end


% =========================================================================
function names = localIncoming_(program, stateName)
% names = localIncoming_(program, stateName)
% States with a transition targeting the named state.
names = strings(1, 0);
for i = 1:numel(program.States)
    S = program.States(i);
    for k = 1:numel(S.Transitions)
        if strcmp(S.Transitions(k).Target, stateName)
            names(end+1) = S.Name;
        end
    end
end
end


function [which, k] = localActionAt_(obj, program, idx)
% [which, k] = localActionAt_(obj, program, idx)
% Map the selected action-table row onto an entry or exit action index.
%
% The table shows entry actions above exit actions, so the row number has to
% be split back into which list it came from.
which = 'entry';
k = 0;

if idx == 0 || ~isfield(obj.HStates, 'SelectedAction')
    return
end

row = obj.HStates.SelectedAction;
nEntry = numel(program.States(idx).EntryActions);
nExit = numel(program.States(idx).ExitActions);

if row < 1 || row > nEntry + nExit
    return
end

if row <= nEntry
    which = 'entry';
    k = row;
else
    which = 'exit';
    k = row - nEntry;
end
end


function k = localTransAt_(obj)
% k = localTransAt_(obj)
% Selected transition row, or 0.
k = 0;
if isfield(obj.HStates, 'SelectedTransition')
    k = obj.HStates.SelectedTransition;
end
end
