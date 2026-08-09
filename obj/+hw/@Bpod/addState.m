function sma = addState(obj, varargin)
% sma = addState(obj, sma, 'Name', name, 'Timer', seconds, ...
%                'StateChangeConditions', conditions, 'OutputActions', actions)
% Add a state to an existing state matrix.
%
% A faithful transcription of Bpod's
% Functions/State Matrix Assembler/AddState.m. The label arguments ('Name',
% 'Timer', 'StateChangeConditions', 'OutputActions') are POSITIONAL and are
% ignored by Bpod, exactly as they are here: the syntax exists so protocol
% code written for Bpod ports over with nothing but the leading `obj.`. Do
% not convert this to a Name=Value signature; that would silently change the
% meaning of every existing Bpod paradigm.
%
% The only changes from upstream are mechanical: `global BpodSystem`'s
% EventNames/OutputActionNames become hw.Bpod.EVENT_NAMES /
% hw.Bpod.OUTPUT_ACTION_NAMES, and the 128-state ceiling becomes
% hw.Bpod.MAX_STATES.
%
% Indexing quirks preserved verbatim, because each one is load bearing:
%   - A state named in StateChangeConditions but not yet defined is appended
%     to StateNames with StatesDefined = 0, so transitions can refer forward.
%     addState later fills that same slot rather than appending a duplicate.
%   - StateNames is therefore in REFERENCE order while Manifest is in ADD
%     order. sendStateMatrix permutes into Manifest order before upload, and
%     that permuted order is what the device's event stream indexes.
%   - 'exit' resolves to NaN here and to nStates+1 in sendStateMatrix.
%   - Event codes above 40 are global timer (41-45) or global counter (46-50)
%     ends and go to their own matrices, not to InputMatrix.
%   - 'Valve', N sets bit N-1 of the valve mask; 'LED', N sets PWM(N) to 255
%     via OutputMatrix column 9+N.
%
% Parameters
%   sma                   - State matrix from newStateMatrix.
%   name                  - State name (char). 'exit' is reserved.
%   seconds               - State timer in seconds.
%   conditions            - {eventName, targetState, ...}, target 'exit' ends
%                           the matrix. Valid event names: hw.Bpod.EVENT_NAMES.
%   actions               - {actionName, value, ...}. Valid action names:
%                           hw.Bpod.OUTPUT_ACTION_NAMES plus the meta-actions
%                           'Valve', 'LED', 'LEDState'.
%
% Returns:
%   sma - The state matrix with the new state added.
%
% Usage
%   sma = iface.newStateMatrix();
%   sma = iface.addState(sma, ...
%       'Name', 'Deliver_Stimulus', ...
%       'Timer', 0.001, ...
%       'StateChangeConditions', {'Port2Out', 'WaitForResponse', 'Tup', 'ITI'}, ...
%       'OutputActions', {'Valve', 1, 'WireState', 3});
%
% See also: hw.Bpod.newStateMatrix, hw.Bpod.sendStateMatrix

% ---- Unpack the positional signature. Upstream's is
% AddState(sma, namestr, StateName, timerstr, StateTimer, conditionstr,
%          StateChangeConditions, outputstr, OutputActions)
if numel(varargin) ~= 9
    error('hw:Bpod:AddStateSyntax', ...
        ['addState takes exactly 9 arguments after obj. Usage:\n' ...
         '  sma = obj.addState(sma, ''Name'', name, ''Timer'', seconds, ...\n' ...
         '      ''StateChangeConditions'', conditions, ''OutputActions'', actions)']);
end

sma                   = varargin{1};
namestr               = varargin{2};
StateName             = varargin{3};
timerstr              = varargin{4};
StateTimer            = varargin{5};
conditionstr          = varargin{6};
StateChangeConditions = varargin{7};
outputstr             = varargin{8};
OutputActions         = varargin{9};

% Upstream ignores the labels entirely, so a transposed argument list is
% accepted in silence and produces a state with the wrong timer or the wrong
% transitions. Warn without erroring: the labels are documentation, and
% rejecting an unrecognised one would break otherwise-valid Bpod code.
checkLabel_(namestr, 'Name');
checkLabel_(timerstr, 'Timer');
checkLabel_(conditionstr, 'StateChangeConditions');
checkLabel_(outputstr, 'OutputActions');

% Sanity check state name
if strcmpi(StateName, 'exit')
    error('hw:Bpod:ExitStateExplicit', ...
        'The exit state is added automatically when sending a matrix. Do not add it explicitly.');
end

%% Check whether the new state has already been referenced. Add new blank state to matrix
nStates = length(sma.StatesDefined);
nStatesInManifest = sma.nStatesInManifest;
StateNumber = find(strcmp(StateName, sma.StateNames));
CurrentStateInManifest = nStatesInManifest + 1;
if sum(sma.StatesDefined) == obj.MAX_STATES
    error('hw:Bpod:TooManyStates', ...
        'The state matrix can have a maximum of %d states.', obj.MAX_STATES);
end
if strcmp(sma.StateNames{1}, 'Placeholder')
    CurrentState = 1;
else
    if isempty(StateNumber) % This state has not been referenced previously
        CurrentState = nStates + 1;
    else % This state was already referenced
        if sma.StatesDefined(StateNumber) == 0
            CurrentState = StateNumber;
        else
            error('hw:Bpod:StateAlreadyDefined', ...
                'The state "%s" has already been defined.', StateName);
        end
    end
end
sma.StateNames{CurrentState} = StateName;
sma.Manifest{CurrentStateInManifest} = StateName;
sma.nStatesInManifest = sma.nStatesInManifest + 1;

% Hard-coded matrix sizes (for efficiency) should be adjusted if changing
% state matrix composition. A row of self-references is the "no transition"
% default: an event with no rule leaves the machine in the current state.
sma.InputMatrix(CurrentState,:) = ones(1,40) * CurrentState;
sma.OutputMatrix(CurrentState,:) = zeros(1,17);
sma.GlobalTimerMatrix(CurrentState,:) = ones(1,5) * CurrentState;
sma.GlobalCounterMatrix(CurrentState,:) = ones(1,5) * CurrentState;
sma.StateTimers(CurrentState) = StateTimer;
sma.StatesDefined(CurrentState) = 1;

%% Make sure all the states in "StateChangeConditions" exist, and if not, create them as undefined states.
% Defensive initialisation: upstream's error helper reads ThisStateName, a
% variable this loop is what assigns. An empty condition list would otherwise
% raise "undefined variable" instead of the spelling message.
ThisStateName = StateName;
for x = 2:2:length(StateChangeConditions)
    ThisStateName = StateChangeConditions{x};
    if ~strcmpi(ThisStateName, 'exit')
        isThere = sum(strcmp(ThisStateName, sma.StateNames)) > 0;
        if isThere == 0
            NewStateNumber = length(sma.StateNames) + 1;
            sma.StateNames(NewStateNumber) = StateChangeConditions(x);
            sma.StatesDefined(NewStateNumber) = 0;
        end
    end
end

%% Add state transitions
EventNames = obj.EVENT_NAMES;
for x = 1:2:length(StateChangeConditions)
    CandidateEventCode = find(strcmp(StateChangeConditions{x}, EventNames));
    TargetState = StateChangeConditions{x+1};
    if ~strcmpi(TargetState, 'exit')
        TargetStateNumber = find(strcmp(StateChangeConditions{x+1}, sma.StateNames));
    else
        TargetStateNumber = NaN; % sendStateMatrix substitutes nStates+1
    end
    if ~isempty(CandidateEventCode)
        if CandidateEventCode > 40
            CandidateEventName = StateChangeConditions{x};
            if length(CandidateEventName) > 4
                if sum(lower(CandidateEventName(length(CandidateEventName)-3:length(CandidateEventName))) == '_end') == 4
                    if CandidateEventCode < 46
                        % This is a transition for a global timer. Add to global timer matrix.
                        GlobalTimerNumber = str2double(CandidateEventName(length(CandidateEventName) - 4));
                        if ~isnan(GlobalTimerNumber)
                            sma.GlobalTimerMatrix(CurrentState, GlobalTimerNumber) = TargetStateNumber;
                        else
                            eventSpellingError_(ThisStateName);
                        end
                    else
                        % This is a transition for a global counter. Add to global counter matrix.
                        GlobalCounterNumber = str2double(CandidateEventName(length(CandidateEventName) - 4));
                        if ~isnan(GlobalCounterNumber)
                            sma.GlobalCounterMatrix(CurrentState, GlobalCounterNumber) = TargetStateNumber;
                        else
                            eventSpellingError_(ThisStateName);
                        end
                    end
                else
                    eventSpellingError_(ThisStateName);
                end
            else
                eventSpellingError_(ThisStateName);
            end
        else
            sma.InputMatrix(CurrentState, CandidateEventCode) = TargetStateNumber;
        end
    else
        eventSpellingError_(ThisStateName);
    end
end

%% Add output actions
OutputActionNames = obj.OUTPUT_ACTION_NAMES;

% 'Valve' is an alternate syntax for "ValveState", specifying one valve to open (1-8).
% 'LED' is an alternate syntax for PWM1-8, specifying one LED to set to max brightness (1-8).
% 'LEDState' is an alternate syntax for PWM1-8: a byte coding for binary sets which LEDs are at max brightness.
MetaActions = {'Valve', 'LED', 'LEDState'};
for x = 1:2:length(OutputActions)
    MetaAction = find(strcmp(OutputActions{x}, MetaActions));
    if ~isempty(MetaAction)
        Value = OutputActions{x+1};
        switch MetaAction
            case 1
                Value = 2^(Value-1);
                sma.OutputMatrix(CurrentState,1) = Value;
            case 2
                sma.OutputMatrix(CurrentState,9+Value) = 255;
            case 3
                % Upstream leaves 'LEDState' unimplemented: the case body is
                % empty, so the requested value is dropped without a word.
                % Preserved (writing the eight PWM columns here would change
                % the behaviour of ported protocols), but no longer silent.
                vprintf(0, 1, ['Bpod: output action ''LEDState'' is not implemented ' ...
                    'in the Bpod state matrix assembler and was IGNORED for state ''%s''. ' ...
                    'Use ''LED'', n or PWM1..PWM8 instead.'], StateName);
        end
    else
        TargetEventCode = find(strcmp(OutputActions{x}, OutputActionNames));
        if ~isempty(TargetEventCode)
            Value = OutputActions{x+1};
            sma.OutputMatrix(CurrentState,TargetEventCode) = Value;
        else
            error('hw:Bpod:BadOutputAction', ...
                'Check spelling of your output actions for state: %s.', StateName);
        end
    end
end

%% Add self timer
sma.StateTimers(CurrentState) = StateTimer;
end


% ---- Local functions -------------------------------------------------------

function eventSpellingError_(stateName)
% eventSpellingError_(stateName)
% Raise Bpod's state-transition spelling error.
error('hw:Bpod:BadEventName', ...
    ['Check spelling of your state transition events for state: %s. ' ...
     'Valid events (%% is an index): Port%%In Port%%Out BNC%%High BNC%%Low ' ...
     'Wire%%High Wire%%Low SoftCode%% GlobalTimer%%_End GlobalCounter%%_End Tup'], ...
    stateName);
end


function checkLabel_(given, expected)
% checkLabel_(given, expected)
% Warn when a positional label argument is not the conventional one.
isLabel = (ischar(given) && isrow(given)) || (isstring(given) && isscalar(given));
if isLabel && strcmpi(char(given), expected)
    return
end
if isLabel
    shown = char(given);
else
    shown = sprintf('<%s>', class(given));
end
vprintf(0, 1, ['Bpod: addState expected the label ''%s'' in this position ' ...
    'but got ''%s''. The labels are positional and ignored, so a mis-ordered ' ...
    'argument list is accepted and builds the wrong state.'], expected, shown);
end
