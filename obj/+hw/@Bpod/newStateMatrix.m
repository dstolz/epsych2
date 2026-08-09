function sma = newStateMatrix(obj)
% sma = newStateMatrix(obj)
% Create a blank Bpod state matrix ready for addState.
%
% Transcribed from the blank-matrix literal in Bpod's BpodObject.m:101-115
% (`obj.BlankStateMatrix`), not from GenerateBlankStateMatrix.m. The two
% disagree on one value and only BpodObject.m is correct:
%
%   BpodObject.m           GlobalCounterEvents = ones(1,5)*255
%   GenerateBlankStateMatrix.m  GlobalCounterEvents = ones(1,5)*254
%
% compileMatrix_ transmits `GlobalCounterEvents-1`, and the firmware treats a
% counter as attached whenever its event byte is < 254
% (Bpod_MainModule_0_6.ino:441). The 255 form therefore sends 254 = "no event
% attached", while the 254 form would send 253 and silently attach every
% unused counter to event code 253. Do not switch to the other literal.
%
% The blank matrix is a plain struct, deliberately: it is the same object
% Bpod protocol code passes around, so a paradigm ported from Bpod runs here
% unchanged. Fields, and the quirks worth knowing:
%   nStates             - Written by sendStateMatrix, never by addState.
%   nStatesInManifest   - Count of states in add order.
%   Manifest            - State names in the order the user ADDED them. The
%                         event stream's state indices refer to this order
%                         after sendStateMatrix permutes the matrix, not to
%                         the order states were first referenced.
%   StateNames          - State names in the order they were first REFERENCED
%                         (a forward reference in StateChangeConditions
%                         creates the name before the state is defined).
%   InputMatrix         - nStates x 40 target state per input event.
%   OutputMatrix        - nStates x 17 output action values.
%   GlobalTimerMatrix   - nStates x 5 target state per global timer end.
%   GlobalCounterMatrix - nStates x 5 target state per global counter end.
%   GlobalTimers        - Durations in SECONDS (scaled to ticks at compile).
%   GlobalCounterEvents - 1-based index into hw.Bpod.EVENT_NAMES, 255 = none.
%   StateTimers         - Per-state timer in SECONDS.
%   StatesDefined       - 1 once addState defines a state, 0 while it is only
%                         referenced. sendStateMatrix refuses a matrix with
%                         any 0 left.
%   PortsEnabled/WiresEnabled - Input channel configuration. See below.
%
% PortsEnabled/WiresEnabled are additions, not part of Bpod's blank matrix.
% Bpod reads them from `BpodSystem.InputsEnabled`, which is a GUI-backed
% struct loaded from Settings Files/BpodInputConfig.mat and edited through
% the port-config window. hw.Bpod never loads the Bpod MATLAB layer, so the
% configuration rides on the matrix instead. They default to all-enabled
% because the firmware's own default is all-DISABLED
% (Bpod_MainModule_0_6.ino:72-73), and a disabled port simply never produces
% Port*In/Port*Out events, with no error anywhere.
%
% Returns:
%   sma - Blank state matrix struct.
%
% See also: hw.Bpod.addState, hw.Bpod.sendStateMatrix,
%           documentation/hw/hw_Bpod.md

sma.nStates = 0;
sma.nStatesInManifest = 0;

% Upstream preallocates 127 entries for a 128-state machine; the last slot is
% grown on demand. Kept as-is so the struct matches Bpod's byte for byte.
sma.Manifest = cell(1, obj.MAX_STATES - 1);  % state names in the order added

sma.StateNames = {'Placeholder'};            % state names in the order referenced
sma.InputMatrix = ones(1, 40);
sma.OutputMatrix = zeros(1, 17);
sma.GlobalTimerMatrix = ones(1, 5);
sma.GlobalTimers = zeros(1, 5);
sma.GlobalTimerSet = zeros(1, 5);            % set to 1 by setGlobalTimer
sma.GlobalCounterMatrix = ones(1, 5);
sma.GlobalCounterEvents = ones(1, 5) * 255;  % 255 = "no event attached"
sma.GlobalCounterThresholds = zeros(1, 5);
sma.GlobalCounterSet = zeros(1, 5);          % set to 1 by setGlobalCounter
sma.StateTimers = 0;
sma.StatesDefined = 1;                       % referenced = 0, defined = 1

% Input channel configuration, transmitted as the last 12 bytes of the
% 8-bit block. All enabled: see the note above.
sma.PortsEnabled = ones(1, 8);
sma.WiresEnabled = ones(1, 4);

vprintf(3, 'Bpod: created a blank state matrix (max %d states)', obj.MAX_STATES);
end
