% TEENSY  Teensy trial designer: model, validation, compilation and simulation.
%
% Build an operant-conditioning contingency as an explicit state machine,
% validate it, simulate it with no hardware, compile it to the wire program the
% EPsychTeensy firmware runs, and export the hw.Parameter set the EPsych runtime
% needs. Launch the GUI with teensy.TrialDesigner.
%
% Model (value classes)
%   BoardProfile - Pin capability table for a Teensy 4.0 or 4.1.
%   Channel      - Logical binding between a name and a board pin.
%   Variable     - Per-trial-settable quantity that becomes an hw.Parameter.
%   Condition    - Leaf test or boolean node guarding a transition.
%   Action       - Something the board does in a state or on a transition.
%   Transition   - Guarded edge out of a state; first match wins.
%   State        - Node of the contingency: actions, timer and ways out.
%
% Package functions
%   getFieldOr   - Read a saved struct field with a default fallback.
%   isVarRef     - Test whether a value is an "@Name" variable reference.
%   varRef       - Build the "@Name" reference string for a variable.
%   issue        - Build one validation issue, or the empty issue array.
%
% Conventions
%   Numeric fields marked "literal or @Var" hold either a double or the string
%   "@Name" naming a teensy.Variable. Use teensy.isVarRef and teensy.varRef
%   rather than testing for "@" by hand.
%
%   Every model class round-trips exactly through toStruct/fromStruct, which is
%   what the .etsm save format and the GUI undo stack are built on. fromStruct
%   tolerates structs written by older versions.
%
%   Every validate method returns a 1xN struct array built by teensy.issue, with
%   fields Severity, Category, Message, Where and Remedy.
%
% See also: hw.Teensy, epsych.BitMask, documentation/teensy/
