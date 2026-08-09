function iss = issue(severity, category, message, options)
% iss = teensy.issue()
% iss = teensy.issue(severity, category, message)
% iss = teensy.issue(severity, category, message, Where=where, Remedy=remedy)
% Build one validation issue, or the empty issue array that seeds a report.
%
% Every validate method in the teensy package returns a 1xN array of these
% structs, so the Compile tab renders one uniform table, the GUI can jump from a
% row back to the offending object, and reports concatenate without reshaping.
% Call with no arguments to get the correctly-shaped empty array to grow.
%
% Parameters
%   severity - "error", "warning" or "info". Omit (or "") for the empty array.
%   category - Short grouping label, e.g. "Name", "Pin", "Reachability".
%   message  - One sentence saying what is wrong.
%   Where    - Location of the problem, e.g. "State 'Cue' transition 2".
%   Remedy   - What the user should do about it.
%
% Returns
%   iss - 1x1 struct with fields Severity, Category, Message, Where and Remedy,
%       or the 0x0 struct array carrying those same fields when no severity is
%       given.
%
% Example
%   iss = teensy.issue();
%   iss(end+1) = teensy.issue("error", "Pin", "Pin 99 is not on the board", ...
%       Where = "Channel 'Poke'", ...
%       Remedy = "Pick a pin from the board pinout.");
%
% See also: teensy.Program, teensy.State, teensy.Channel

arguments
    severity (1,1) string {mustBeMember(severity, ["error","warning","info",""])} = ""
    category (1,1) string = ""
    message (1,1) string = ""
    options.Where (1,1) string = ""
    options.Remedy (1,1) string = ""
end

% Field order is fixed here so that issue arrays from different classes always
% concatenate.
iss = struct('Severity', "", 'Category', "", 'Message', "", 'Where', "", 'Remedy', "");

if strlength(severity) == 0
    iss = repmat(iss, 0, 0);
    return
end

iss.Severity = severity;
iss.Category = category;
iss.Message = message;
iss.Where = options.Where;
iss.Remedy = options.Remedy;
