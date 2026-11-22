function smoke_test_readplan
% smoke_test_readplan
% hw.ReadPlan reads a parameter list with one backend call per interface, and
% epsych.Runtime.all_parameters(valueOnly=true) -- the trial-end sweep -- goes
% through one. The contract is that nothing a caller can see changes: every
% value is exactly what P(k).Value returns, in the same order under the same
% field names. This is the standing proof of that, on a counting device.
%
% Verifies:
%   1) the sweep struct equals the per-parameter loop it replaced: values,
%      classes, field names and field order
%   2) the device group costs ONE get_parameter call, and one read per value
%   3) write-only, StimType and software parameters are served as P.Value
%      serves them, and never batched
%   4) a disconnected backend: the stored values, as P.Value gives them
%   5) a backend that cannot take an array is left on P.Value for good
%   6) a read that fails raises what P.Value raises, and does not demote
%   7) the plan is reused while the list is the same and rebuilt when it changes
%   8) the cell form (valueOnly without asStruct)
%
% No hardware, no windows.
%
%   matlab -batch "run('tmp/smoke_test_readplan.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(here);

fprintf('\n=== smoke_test_readplan ===\n');

% --- a protocol with every kind of parameter the sweep meets -----------------
P = epsych.Protocol(Info = 'readplan');
dev = CountingProbeInterface(CoerceSingle = true);
P.addInterface(dev);

p = dev.add_parameter('Gain', 0.1);              p.Value = 0.1;
p = dev.add_parameter('Count', 7, Type = 'Integer'); p.Value = 7;
p = dev.add_parameter('Flag', true, Type = 'Boolean'); p.Value = true;
p = dev.add_parameter('RespCode', 0, Type = 'Integer', Access = 'Read'); dev.put(p, uint32(17));
p = dev.add_parameter('Latency', 0, Access = 'Read');   dev.put(p, single(123.5));
p = dev.add_parameter('Buf', 0, Type = 'Buffer', Access = 'Read', isArray = true); dev.put(p, single(1:64));
p = dev.add_parameter('Hidden', 3, Visible = false);    p.Value = 3;
p = dev.add_parameter('OutOnly', 5, Access = 'Write');  p.Value = 5;
pStim = dev.add_parameter('Stim', [], Type = 'StimType');
for nm = ["x_NewTrial_1" "x_ResetTrig_1" "x_TrialComplete_1"]
    q = dev.add_parameter(char(nm), 0, isTrigger = true);
    dev.put(q, 0);
end

sw = P.SoftwareModule;
p = sw.add_parameter('SoftA', 11);       p.Value = 11;
p = sw.add_parameter('Name with space', 4); p.Value = 4;
p = sw.add_parameter('Label', 'abc', Type = 'String'); p.Value = 'abc';

rt = epsych.Runtime;
rt.isTest = true;
rt.EVENTS = epsych.EventHub;
rt.Interfaces = P.Interfaces;

% --- 1. the sweep equals the loop it replaced --------------------------------
Plist = rt.all_parameters(Access = 'Read');
legacy = struct();
for k = 1:numel(Plist)
    legacy.(Plist(k).validName) = Plist(k).Value;
end
swept = rt.all_parameters(Access = 'Read', asStruct = true, valueOnly = true);
assert(isequal(fieldnames(swept), fieldnames(legacy)), 'field names or their order changed');
fn = fieldnames(legacy);
for k = 1:numel(fn)
    a = legacy.(fn{k});
    b = swept.(fn{k});
    assert(isequaln(a, b) && strcmp(class(a), class(b)), ...
        'field %s differs: %s vs %s', fn{k}, class(a), class(b));
end
assert(isfield(swept, 'Gain') && swept.Gain == double(single(0.1)), 'Gain should be the device read-back');
assert(isa(swept.RespCode, 'double') && swept.RespCode == 17, 'numerics are returned as double');
assert(isa(swept.Buf, 'double') && numel(swept.Buf) == 64, 'a buffer comes back whole, as double');
assert(~isfield(swept, 'Hidden') && ~isfield(swept, 'OutOnly'), 'invisible and write-only stay out of the sweep');
assert(isfield(swept, matlab.lang.makeValidName('Name with space')), 'field names are the valid names');
fprintf('PASS: 1 the sweep equals the per-parameter loop (%d fields)\n', numel(fn));

% --- 2. one backend call for the device group --------------------------------
nDev = nnz(arrayfun(@(q) isa(q.Parent, 'CountingProbeInterface') && ~strcmp(q.Type, 'StimType'), Plist));
dev.resetCounts();
rt.all_parameters(Access = 'Read', asStruct = true, valueOnly = true);
assert(dev.Counts.GetCalls == 1, 'the device group cost %d get_parameter calls; expected 1', dev.Counts.GetCalls);
assert(dev.Counts.Read == nDev, 'expected %d device reads, saw %d', nDev, dev.Counts.Read);
fprintf('PASS: 2 %d device values in one get_parameter call\n', nDev);

% --- 3. what must not be batched ---------------------------------------------
plan = hw.ReadPlan([Plist, dev.find_parameter('OutOnly', includeInvisible = true)]);
v = plan.read();
assert(isnan(v{end}), 'a write-only parameter reads NaN, as P.Value gives it');
iStim = find(strcmp({Plist.Name}, 'Stim'), 1);
assert(~isempty(iStim) && isequaln(v{iStim}, pStim.Value), 'a StimType value is the host-side one');
fprintf('PASS: 3 write-only, StimType and software parameters served as P.Value serves them\n');

% --- 4. disconnected: the stored values --------------------------------------
dev.Connected = false;
legacyOff = struct();
for k = 1:numel(Plist)
    legacyOff.(Plist(k).validName) = Plist(k).Value;
end
dev.resetCounts();
sweptOff = rt.all_parameters(Access = 'Read', asStruct = true, valueOnly = true);
assert(isequaln(sweptOff, legacyOff), 'a disconnected backend must give the stored values');
assert(dev.Counts.Read == 0, 'a disconnected backend must not be read');
dev.Connected = true;
fprintf('PASS: 4 a disconnected backend gives the stored values\n');

% --- 5. a backend that cannot take an array ----------------------------------
refuser = CountingProbeInterface();
refuser.RefuseArrays = true;
r1 = refuser.add_parameter('A', 0); refuser.put(r1, 1);
r2 = refuser.add_parameter('B', 0); refuser.put(r2, 2);
planR = hw.ReadPlan([r1 r2]);
refuser.resetCounts();
v = planR.read();
assert(isequal(v, {1, 2}), 'a scalar-only backend must still give its values');
assert(refuser.Counts.Refused == 1, 'the first read should have tried the array call once');
v = planR.read();
v2 = planR.read();
assert(isequal(v, {1, 2}) && isequal(v2, {1, 2}), 'values must keep coming after the refusal');
assert(refuser.Counts.Refused == 1, ...
    'the array call was tried again after being refused (%d times in all)', refuser.Counts.Refused);
delete(refuser);
fprintf('PASS: 5 a backend that refuses an array is read one at a time from then on\n');

% --- 6. a failing read raises what P.Value raises ----------------------------
dev.ThrowOn = {'Latency'};
idLegacy = '';
try
    q = dev.find_parameter('Latency');
    q.Value;
catch ME
    idLegacy = ME.identifier;
end
idPlan = '';
try
    rt.all_parameters(Access = 'Read', asStruct = true, valueOnly = true);
catch ME
    idPlan = ME.identifier;
end
assert(strcmp(idLegacy, 'CountingProbe:readFailed') && strcmp(idPlan, idLegacy), ...
    'a failing read must raise the same error (legacy "%s", plan "%s")', idLegacy, idPlan);
dev.ThrowOn = {};
dev.resetCounts();
rt.all_parameters(Access = 'Read', asStruct = true, valueOnly = true);
assert(dev.Counts.GetCalls == 1, 'a read failure must not demote the backend from batching');
fprintf('PASS: 6 a failing read raises the same error and does not demote the backend\n');

% --- 7. reuse and rebuild ----------------------------------------------------
planA = hw.ReadPlan(Plist);
assert(planA.matches(Plist), 'a plan must match the list it was built for');
assert(~planA.matches(Plist(1:end-1)), 'a shorter list is a different list');
assert(~planA.matches(fliplr(Plist)), 'a reordered list is a different list');
extra = dev.add_parameter('Added', 9); extra.Value = 9;
swept2 = rt.all_parameters(Access = 'Read', asStruct = true, valueOnly = true);
assert(isfield(swept2, 'Added') && swept2.Added == 9, 'a parameter added mid-session must appear in the sweep');
fprintf('PASS: 7 the plan is reused for the same list and rebuilt for a changed one\n');

% --- 8. the cell form --------------------------------------------------------
Plist = rt.all_parameters(Access = 'Read');
cLegacy = arrayfun(@(q) q.Value, Plist, 'UniformOutput', false);
cPlan = rt.all_parameters(Access = 'Read', valueOnly = true);
assert(isequaln(cPlan, cLegacy) && isequal(size(cPlan), size(cLegacy)), 'the cell form changed');
fprintf('PASS: 8 valueOnly without asStruct returns the same cell\n');

fprintf('=== smoke_test_readplan: ALL PASS ===\n');
end
