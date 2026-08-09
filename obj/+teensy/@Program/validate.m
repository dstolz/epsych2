function iss = validate(obj)
% iss = validate(obj)
% Check the whole program and report everything wrong with it.
%
% Two kinds of check live here: the ones that span objects (duplicate names,
% pin conflicts, reachability), and the aggregation of every contained
% object's own validate. Per-object checks stay with their object so the
% inspector panels can validate a single item as it is edited.
%
% Severity drives behavior downstream: teensy.Compiler refuses to emit while
% any "error" is present, but always returns the report, and the designer's
% Compile tab tints rows by severity and can jump to the offending item.
%
% Returns:
%   iss - 1xN issue struct array (Severity, Category, Message, Where, Remedy);
%       empty when the program is clean. See teensy.issue.
%
% See also: teensy.issue, teensy.Program.graph, teensy.Compiler

arguments
    obj (1,1) teensy.Program
end

iss = teensy.issue();

% --- Identity -------------------------------------------------------------

if strlength(obj.Name) == 0
    iss(end+1) = teensy.issue("warning", "Name", ...
        "The program has no name.", Where = "Program", ...
        Remedy = "Name it on the File > Edit Info dialog; the name is saved with it.");
end

% --- Contents present -----------------------------------------------------

if isempty(obj.States)
    iss(end+1) = teensy.issue("error", "Structure", ...
        "The program has no states.", Where = "Program", ...
        Remedy = "Add a state, or start from a template on the File > New From Template menu.");
    return
end

stateNames = [obj.States.Name];

if strlength(obj.StartState) == 0
    iss(end+1) = teensy.issue("error", "Structure", ...
        "No start state is set.", Where = "Program", ...
        Remedy = "Right-click a state in the diagram and choose Set as Start.");
elseif obj.stateIndex(obj.StartState) == 0
    iss(end+1) = teensy.issue("error", "Structure", ...
        sprintf("The start state '%s' does not exist.", obj.StartState), Where = "Program", ...
        Remedy = "Pick an existing state as the start state.");
end

% --- Duplicate names ------------------------------------------------------

iss = [iss, localDuplicates_(stateNames, "State")];
iss = [iss, localDuplicates_([obj.Channels.Name], "Channel")];
iss = [iss, localDuplicates_([obj.Variables.Name], "Variable")];
iss = [iss, localDuplicates_(localNames_(obj.GlobalTimers), "Timer")];
iss = [iss, localDuplicates_(localNames_(obj.Counters), "Counter")];

% --- Pin conflicts --------------------------------------------------------
% Channel.validate checks a pin against the board's capabilities; only the
% program can see that two channels claim the same pin.

assigned = find([obj.Channels.Pin] >= 0);
pins = [obj.Channels(assigned).Pin];
[uniquePins, ~, groupIdx] = unique(pins);
for g = 1:numel(uniquePins)
    members = assigned(groupIdx == g);
    if numel(members) < 2
        continue
    end
    iss(end+1) = teensy.issue("error", "Pin", ...
        sprintf("Pin %d is claimed by %s.", uniquePins(g), ...
            strjoin("'" + [obj.Channels(members).Name] + "'", ", ")), ...
        Where = sprintf("Channel '%s'", obj.Channels(members(1)).Name), ...
        Remedy = "Give each channel its own pin on the Channels tab.");
end

% --- Counters -------------------------------------------------------------

for i = 1:numel(obj.Counters)
    C = obj.Counters(i);
    where = sprintf("Counter '%s'", C.Name);

    if strlength(C.Channel) == 0
        iss(end+1) = teensy.issue("error", "Counter", ...
            "The counter has no input channel.", Where = where, ...
            Remedy = "Pick the input channel whose edges it should count.");
        continue
    end

    idx = obj.channelIndex(C.Channel);
    if idx == 0
        iss(end+1) = teensy.issue("error", "Counter", ...
            sprintf("There is no channel named '%s'.", C.Channel), Where = where, ...
            Remedy = "Pick an existing input channel, or add it on the Channels tab.");
    elseif obj.Channels(idx).Direction ~= "Input"
        iss(end+1) = teensy.issue("error", "Counter", ...
            sprintf("'%s' is an output; counters read inputs.", C.Channel), Where = where, ...
            Remedy = "Pick an input channel.");
    end
end

% --- Global timers --------------------------------------------------------

for i = 1:numel(obj.GlobalTimers)
    T = obj.GlobalTimers(i);
    where = sprintf("Timer '%s'", T.Name);

    [isRef, refName] = teensy.isVarRef(T.DurationMs);
    if isRef
        if obj.variableIndex(refName) == 0
            iss(end+1) = teensy.issue("error", "Variable", ...
                sprintf("The duration refers to undefined variable '%s'.", refName), ...
                Where = where, ...
                Remedy = "Add the variable on the Variables tab, or enter a literal duration.");
        end
    elseif ~(isnumeric(T.DurationMs) && isscalar(T.DurationMs) && T.DurationMs > 0)
        iss(end+1) = teensy.issue("error", "Timer", ...
            "The duration must be a positive number of milliseconds.", Where = where, ...
            Remedy = "Enter a duration greater than zero.");
    end
end

% --- Contained objects ----------------------------------------------------

for i = 1:numel(obj.Channels)
    iss = [iss, obj.Channels(i).validate(obj)];
end

for i = 1:numel(obj.Variables)
    iss = [iss, obj.Variables(i).validate(obj)];
end

for i = 1:numel(obj.States)
    iss = [iss, obj.States(i).validate(obj)];
end

% --- Reachability ---------------------------------------------------------
% Done last so it is not run against a program already known to be malformed
% in a way that would make the graph misleading.

G = obj.graph();
reachable = G.Reachable(:);

unreachable = find(~reachable);
for k = 1:numel(unreachable)
    i = unreachable(k);
    iss(end+1) = teensy.issue("warning", "Reachability", ...
        "No transition path reaches this state from the start state.", ...
        Where = sprintf("State '%s'", stateNames(i)), ...
        Remedy = "Add a transition into it, or delete it.");
end

isTerminal = [obj.States.IsTerminal]';
if ~any(isTerminal)
    iss(end+1) = teensy.issue("error", "Reachability", ...
        "No state is marked terminal, so a trial can never complete.", Where = "Program", ...
        Remedy = "Mark the outcome states terminal so they raise TrialComplete.");
elseif ~any(isTerminal & reachable)
    iss(end+1) = teensy.issue("error", "Reachability", ...
        "No terminal state is reachable, so a trial can never complete.", Where = "Program", ...
        Remedy = "Add a transition path from the start state to an outcome state.");
end

% A trial that never marks latency reports RespLatency as NaN, which reads as
% a hardware fault rather than as a paradigm that simply does not measure it.
if ~localHasAction_(obj, "MarkLatency")
    iss(end+1) = teensy.issue("info", "Latency", ...
        "No action marks the response latency, so RespLatency stays unset.", ...
        Where = "Program", ...
        Remedy = "Add a Mark Latency action on the transition you consider the response.");
end
end


function iss = localDuplicates_(names, label)
% iss = localDuplicates_(names, label)
% Report names that appear more than once in a name list.
iss = teensy.issue();
if numel(names) < 2
    return
end

[uniqueNames, ~, groupIdx] = unique(names);
counts = accumarray(groupIdx(:), 1);
for k = find(counts > 1)'
    iss(end+1) = teensy.issue("error", "Name", ...
        sprintf("%d items share the name '%s'.", counts(k), uniqueNames(k)), ...
        Where = sprintf("%s '%s'", label, uniqueNames(k)), ...
        Remedy = "Names identify items on the wire, so each must be unique.");
end
end


function names = localNames_(structArray)
% names = localNames_(structArray)
% Name field of a struct array as a string array.
if isempty(structArray)
    names = strings(1, 0);
    return
end
names = string({structArray.Name});
end


function tf = localHasAction_(obj, kind)
% tf = localHasAction_(obj, kind)
% True when any state or transition carries an action of the given kind.
tf = false;
for i = 1:numel(obj.States)
    S = obj.States(i);
    if localAnyKind_(S.EntryActions, kind) || localAnyKind_(S.ExitActions, kind)
        tf = true;
        return
    end
    for k = 1:numel(S.Transitions)
        if localAnyKind_(S.Transitions(k).Actions, kind)
            tf = true;
            return
        end
    end
end
end


function tf = localAnyKind_(actions, kind)
% tf = localAnyKind_(actions, kind)
% True when an action array contains the given kind.
tf = ~isempty(actions) && any([actions.Kind] == kind);
end
