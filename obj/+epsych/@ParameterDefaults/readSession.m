function [vals, report] = readSession(runExpt, subjectName, T)
% [vals, report] = epsych.ParameterDefaults.readSession(runExpt, subjectName, T)
% What a session holds now for the parameters T names, for one subject -- the
% editor's Copy from Session.
%
% "Now" follows the rule a phase save uses (epsych.Runtime.writeParametersProtocol):
% for a dispatched parameter, the committed trial-table value, since a deferred
% commit lands there before it reaches the parameter; for everything else, the
% parameter's live Value. The one departure is a column that varies across the
% trial table -- a parameter a staircase or other selector manages trial by
% trial. A phase save leaves those alone so as not to freeze the staircase;
% here the live Value is exactly what is wanted, because "start the next
% session where this one is" is the reason to copy it.
%
% Reading a live Value is a device round trip on a connected backend, so this
% is a button's action, never a poll. A read that throws is reported in that
% row's Error and the rest go on.
%
% Parameters:
%   runExpt     - epsych.RunExpt holding the session.
%   subjectName - the subject's Name in the session.
%   T           - rows from epsych.ParameterDefaults.parameters (only
%                 Interface, Module and Name are used).
%
% Returns:
%   vals   - (1,:) struct aligned with T: Found, Value, Levels, Min, Max,
%            Source ('trial table' | 'live' | ''), Error.
%   report - struct: Found (the subject is in the session), HasRun (a run's
%            trial table was available), Message.
%
% See also: epsych.ParameterDefaults.readDataFile, epsych.Runtime.writeParametersProtocol
arguments
    runExpt
    subjectName (1,:) char
    T struct
end

vals = repmat(struct('Found', false, 'Value', [], 'Levels', {{}}, 'Min', NaN, ...
    'Max', NaN, 'Source', '', 'Error', ''), 1, numel(T));
report = struct('Found', false, 'HasRun', false, 'Message', '');

if isempty(runExpt) || ~isa(runExpt, 'epsych.RunExpt') || ~isvalid(runExpt)
    report.Message = 'No session window is open.';
    return
end

C = [];
for c = runExpt.CONFIG
    if isstruct(c) && ~isempty(c.SUBJECT) && strcmp(c.SUBJECT.Name, subjectName)
        C = c;
        break
    end
end
if isempty(C) || ~isa(C.PROTOCOL, 'epsych.Protocol') || ~isvalid(C.PROTOCOL)
    report.Message = sprintf('"%s" is not in the current session.', subjectName);
    return
end
report.Found = true;

% The trial table of the run that is going or just stopped, matched by name:
% CONFIG can be reordered or edited after a Stop, TRIALS cannot.
committed = struct();
perTrial = struct();
TR = [];
try
    TR = runExpt.RUNTIME.TRIALS;
catch ME
    vprintf(3, 'epsych.ParameterDefaults.readSession: no trials (%s)', ME.message)
end
if isstruct(TR) && ~isempty(TR) && isfield(TR, 'trials') && isfield(TR, 'writeParamIdx') ...
        && isfield(TR, 'Subject')
    k = find(arrayfun(@(t) ~isempty(t.Subject) && strcmp(t.Subject.Name, subjectName), TR), 1);
    if ~isempty(k) && iscell(TR(k).trials) && isstruct(TR(k).writeParamIdx)
        report.HasRun = true;
        fn = fieldnames(TR(k).writeParamIdx);
        for j = 1:numel(fn)
            col = TR(k).trials(:, TR(k).writeParamIdx.(fn{j}));
            if isempty(col), continue, end
            if all(cellfun(@(x) isequaln(x, col{1}), col))
                committed.(fn{j}) = col{1};
            else
                perTrial.(fn{j}) = true;
            end
        end
    end
end

for i = 1:numel(T)
    d = epsych.ParameterDefaults.blank();
    d.Interface = T(i).Interface;
    d.Module = T(i).Module;
    d.Name = T(i).Name;
    P = epsych.ParameterDefaults.resolve(C.PROTOCOL, d);
    if isempty(P), continue, end

    v = vals(i);
    v.Found = true;
    v.Levels = P.Values;
    v.Min = P.Min;
    v.Max = P.Max;

    e = epsych.ParameterDefaults.eligibility(P);
    if e.CanSetValue
        vn = P.validName;
        try
            if P.UpdateEveryTrial && isfield(committed, vn) && ~isfield(perTrial, vn)
                v.Value = committed.(vn);
                v.Source = 'trial table';
            elseif strcmp(P.Access, 'Write')
                % Nothing to read back from a write-only parameter; its design
                % level is what it was last given.
                if isscalar(P.Values), v.Value = P.Values{1}; end
                v.Source = 'live';
            else
                v.Value = P.Value;
                v.Source = 'live';
            end
        catch ME
            v.Error = ME.message;
            vprintf(2, 'Copy from session: could not read %s (%s)', P.Name, ME.message)
        end
    end
    vals(i) = v;
end
end
