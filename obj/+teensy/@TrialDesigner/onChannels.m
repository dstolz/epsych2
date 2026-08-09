function onChannels(obj, verb, varargin)
% onChannels(obj, verb, varargin)
% Handle every Channels-tab action.
%
% One entry point per tab keeps the undo/dirty/refresh/status sequence in a
% single place; every branch pushes an undo snapshot before mutating, and
% every path ends with a status message.
%
% Parameters
%   verb - 'edited', 'selected', 'add', 'duplicate', 'remove', 'defaults',
%       'field', 'pin', 'livePulse', 'liveOn', 'liveOff'.
%   varargin - Verb-specific arguments.
%
% See also: teensy.TrialDesigner.refreshAll

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
        obj.SelectedChannel = evt.Indices(1, 1);
        obj.refreshAll();
        obj.setStatus(sprintf('Selected channel %s.', ...
            P.Channels(obj.SelectedChannel).Name));

    case 'edited'
        evt = varargin{1};
        row = evt.Indices(1, 1);
        col = evt.Indices(1, 2);
        obj.pushUndo('Edit Channel');

        columns = {'Name', '', '', 'Pin', 'ActiveHigh', 'DebounceMs', ...
            'ThresholdHigh', 'ThresholdLow', 'IdleState', 'Units', 'Notes'};
        field = columns{col};
        if isempty(field)
            obj.refreshAll();
            return
        end

        if strcmp(field, 'Name')
            P.renameChannel(P.Channels(row).Name, string(evt.NewData));
        else
            P.Channels(row).(field) = localCoerce_(field, evt.NewData);
            P.touch();
        end

        obj.refreshAll();
        obj.setStatus(sprintf('Updated %s.', field));

    case 'add'
        direction = varargin{1};
        kind = varargin{2};
        obj.pushUndo('Add Channel');

        pin = localNextFreePin_(P, direction, kind);
        base = localDefaultName_(direction, kind);

        switch direction + "/" + kind
            case "Input/Digital"
                c = teensy.Channel.digitalIn(base, pin);
            case "Output/Digital"
                c = teensy.Channel.digitalOut(base, pin);
            case "Input/Analog"
                c = teensy.Channel.analogIn(base, pin);
            otherwise
                c = teensy.Channel.analogOut(base, pin);
        end

        added = P.addChannel(c);
        obj.SelectedChannel = numel(P.Channels);
        obj.refreshAll();
        obj.setStatus(sprintf('Added %s on pin %d.', added.Name, added.Pin));

    case 'duplicate'
        if obj.SelectedChannel == 0
            obj.setStatus('Select a channel to duplicate.');
            return
        end
        obj.pushUndo('Duplicate Channel');

        c = P.Channels(obj.SelectedChannel);
        c.Pin = localNextFreePin_(P, c.Direction, c.Kind);
        added = P.addChannel(c);
        obj.SelectedChannel = numel(P.Channels);
        obj.refreshAll();
        obj.setStatus(sprintf('Duplicated as %s.', added.Name));

    case 'remove'
        if obj.SelectedChannel == 0
            obj.setStatus('Select a channel to remove.');
            return
        end

        name = P.Channels(obj.SelectedChannel).Name;
        users = localChannelUsers_(P, name);
        if ~isempty(users)
            answer = uiconfirm(obj.Figure, ...
                sprintf(['%s is used by %d condition(s) or action(s). Removing it ' ...
                    'will leave those referring to a channel that does not exist.'], ...
                    name, numel(users)), ...
                'Channel In Use', Options = {'Remove Anyway', 'Cancel'}, ...
                DefaultOption = 'Cancel', CancelOption = 'Cancel', Icon = 'warning');
            if ~strcmp(answer, 'Remove Anyway')
                obj.setStatus('Kept the channel.');
                return
            end
        end

        obj.pushUndo('Remove Channel');
        P.removeChannel(name);
        obj.SelectedChannel = min(obj.SelectedChannel, numel(P.Channels));
        obj.refreshAll();
        obj.setStatus(sprintf('Removed %s.', name));

    case 'defaults'
        answer = uiconfirm(obj.Figure, ...
            ['Replace the channel list with a standard operant box: nose poke, ' ...
             'lick spout, reward valve, house light, sync out and a piezo.'], ...
            'Load Default Channels', Options = {'Replace', 'Cancel'}, ...
            DefaultOption = 'Cancel', CancelOption = 'Cancel', Icon = 'question');
        if ~strcmp(answer, 'Replace')
            return
        end

        obj.pushUndo('Load Default Channels');
        P.Channels = teensy.Channel.defaultSet();
        P.touch();
        obj.SelectedChannel = 1;
        obj.refreshAll();
        obj.setStatus('Loaded the default channel set.');

    case 'field'
        if obj.SelectedChannel == 0
            return
        end
        field = varargin{1};
        value = varargin{2};
        obj.pushUndo('Edit Channel');

        if strcmp(field, 'Name')
            P.renameChannel(P.Channels(obj.SelectedChannel).Name, string(value));
        else
            P.Channels(obj.SelectedChannel).(field) = localCoerce_(field, value);
            P.touch();
        end

        obj.refreshAll();
        obj.setStatus(sprintf('Updated %s.', field));

    case 'pin'
        if obj.SelectedChannel == 0
            return
        end
        label = varargin{1};

        if strcmp(label, '(none)')
            pin = -1;
        else
            pin = sscanf(label, '%d');
        end

        if contains(label, 'used by')
            uialert(obj.Figure, ...
                sprintf('Pin %d already belongs to another channel.', pin), ...
                'Pin In Use', Icon = 'warning');
            obj.refreshAll();
            return
        end

        obj.pushUndo('Set Pin');
        P.Channels(obj.SelectedChannel).Pin = pin;
        P.touch();
        obj.refreshAll();
        obj.setStatus(sprintf('Assigned pin %d.', pin));

    case {'livePulse', 'liveOn', 'liveOff'}
        localLiveIO_(obj, verb);

end
end


% =========================================================================
function value = localCoerce_(field, value)
% value = localCoerce_(field, value)
% Coerce a table or control value into what the Channel property expects.
switch field
    case {'Name', 'Units', 'Notes', 'PullMode', 'AnalogOutMode'}
        value = string(value);
    case 'ActiveHigh'
        value = logical(value);
    otherwise
        value = double(value);
end
end


function pin = localNextFreePin_(program, direction, kind)
% pin = localNextFreePin_(program, direction, kind)
% First board pin that suits this channel and is not already claimed.
board = program.Board;

if kind == "Analog" && direction == "Input"
    capability = "analogIn";
elseif kind == "Analog"
    capability = "pwm";
else
    capability = "digital";
end

used = [];
if ~isempty(program.Channels)
    used = [program.Channels.Pin];
end

for pin = 0:board.NumPins - 1
    if board.isReserved(pin) || ~board.supports(capability, pin)
        continue
    end
    if ~ismember(pin, used)
        return
    end
end

pin = -1;
end


function name = localDefaultName_(direction, kind)
% name = localDefaultName_(direction, kind)
% A starting name for a new channel.
if direction == "Input" && kind == "Digital"
    name = "DigIn";
elseif direction == "Output" && kind == "Digital"
    name = "DigOut";
elseif direction == "Input"
    name = "AnaIn";
else
    name = "AnaOut";
end
end


function users = localChannelUsers_(program, name)
% users = localChannelUsers_(program, name)
% Where a channel is referenced, so removing it can warn first.
users = strings(1, 0);

for i = 1:numel(program.States)
    S = program.States(i);

    for a = [S.EntryActions, S.ExitActions]
        if any(strcmp(a.channelsUsed(), name))
            users(end+1) = S.Name;
        end
    end

    for k = 1:numel(S.Transitions)
        if any(strcmp(S.Transitions(k).channelsUsed(), name))
            users(end+1) = S.Name;
        end
    end
end

for i = 1:numel(program.Counters)
    if strcmp(program.Counters(i).Channel, name)
        users(end+1) = string(program.Counters(i).Name);
    end
end
end


function localLiveIO_(obj, verb)
% localLiveIO_(obj, verb)
% Drive a real output on a connected board, for wiring checks.
if obj.SelectedChannel == 0
    obj.setStatus('Select an output channel first.');
    return
end

c = obj.Program.Channels(obj.SelectedChannel);
if c.Direction ~= "Output"
    obj.setStatus('Live I/O only drives output channels.');
    return
end

if isempty(obj.Interface) || ~isa(obj.Interface, 'hw.Teensy') || ~obj.Interface.IsConnected
    obj.setStatus('No connected Teensy is bound to this designer.', ...
        'Bind a board by opening the designer from the Protocol Designer.');
    return
end

try
    switch verb
        case 'livePulse'
            obj.Interface.set_parameter(char(c.Name), 1);
            obj.Interface.flushWrites();
            pause(0.05);
            obj.Interface.set_parameter(char(c.Name), 0);
            obj.Interface.flushWrites();
            obj.setStatus(sprintf('Pulsed %s for 50 ms.', c.Name));
        case 'liveOn'
            obj.Interface.set_parameter(char(c.Name), 1);
            obj.Interface.flushWrites();
            obj.setStatus(sprintf('Drove %s high.', c.Name));
        otherwise
            obj.Interface.set_parameter(char(c.Name), 0);
            obj.Interface.flushWrites();
            obj.setStatus(sprintf('Drove %s low.', c.Name));
    end
catch ME
    vprintf(0, 1, ME);
    obj.setStatus(sprintf('Live I/O failed: %s', ME.message));
end
end
