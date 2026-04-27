% recreate_eprot_fixture.m
%
% Recreate protocol_designer_expression_pairs_test.eprot using the new
% hw.Parameter.Values / epsych.Protocol API.
%
% Run with:
%   matlab -batch "addpath(genpath('c:\src\epsych2')); run('c:\src\epsych2\tmp\recreate_eprot_fixture.m')"

%% Create protocol
p = epsych.Protocol( ...
    Info = 'Fixture covering Software and offline TDT_RPcox modules with paired parameters, mixed types, and expression references.');
p.setOption('randomize',         false);
p.setOption('numReps',           1);
p.setOption('ISI',               250);
p.setOption('trialFunc',         '');
p.setOption('compileAtRuntime',  false);
p.setOption('IncludeWAVBuffers', true);
p.setOption('UseOpenEx',         true);
p.setOption('ConnectionType',    'GB');

%% Software interface — use the default module created by Protocol constructor
mod = p.SoftwareModule.Module;  % hw.Module('Software','Params',1) from constructor

P = mod.add_parameter('baseGain',       [10 20 30],   Type='Float',   Access='Any', isArray=true);
P.UserData = struct('Pair', 'timingTriplet');

P = mod.add_parameter('trialIndex',     [1 2 3],      Type='Integer', Access='Any', isArray=true);
P.UserData = struct('Pair', 'timingTriplet');

P = mod.add_parameter('conditionLabel', 'baseline',   Type='String',  Access='Any');
P.UserData = struct('Pair', 'labelRoute');

P = mod.add_parameter('stimulusFile',   'stim_a.wav', Type='File',    Access='Any');
P.UserData = struct('Pair', 'labelRoute');

P = mod.add_parameter('gateEnabled',    true,         Type='Boolean', Access='Any'); %#ok<NASGU>

%% TDT_RPcox interface — modules "RPA" and "RPB"
tdt = hw.TDT_RPcox({}, {}, {}, Interface='GB', Connect=false);
rpa = hw.Module(tdt, 'RPA', 'RPA', uint8(1));
rpb = hw.Module(tdt, 'RPB', 'RPB', uint8(2));

% --- RPA parameters ---
P = rpa.add_parameter('gain',           [1 2 3],      Type='Float',   Access='Any', isArray=true);
P.UserData = struct('Pair', 'timingTriplet');

P = rpa.add_parameter('delayMs',        [5 10 15],    Type='Integer', Access='Any', isArray=true);
P.UserData = struct('Pair', 'timingTriplet');

P = rpa.add_parameter('bufferName',     'buf_a',      Type='String',  Access='Any');
P.UserData = struct('Pair', 'labelRoute');

P = rpa.add_parameter('triggerEnabled', false,        Type='Boolean', Access='Any'); %#ok<NASGU>

% --- RPB parameters ---
P = rpb.add_parameter('attenuation',    [0.5 1 1.5],  Type='Float',   Access='Any', isArray=true);
P.UserData = struct('Pair', 'timingTriplet');

% Expression params: Values stored as evaluated result from the original fixture.
% gainFromA and softwareLinked were un-evaluated (Value=0) in the original;
% sumLocal was evaluated to [2.5 3 3.5].
P = rpb.add_parameter('gainFromA',      0,            Type='Float',   Access='Any');
P.UserData = struct('Expression', 'RPA.gain + attenuation');

P = rpb.add_parameter('sumLocal',       [2.5 3 3.5],  Type='Float',   Access='Any', isArray=true);
P.UserData = struct('Expression', 'attenuation + 2');

P = rpb.add_parameter('softwareLinked', 0,            Type='Float',   Access='Any');
P.UserData = struct('Expression', 'Params.baseGain + attenuation');

P = rpb.add_parameter('routeLabel',     'left',       Type='String',  Access='Any');
P.UserData = struct('Pair', 'labelRoute');

P = rpb.add_parameter('enableOutput',   true,         Type='Boolean', Access='Any'); %#ok<NASGU>

tdt.setModules([rpa, rpb]);
p.addInterface(tdt);

%% Compile and save
p.compile();
outFile = 'c:\src\epsych2\tmp\protocol_designer_expression_pairs_test.eprot';
p.save(outFile);
fprintf('Fixture saved to: %s\n', outFile);
