function outputPath = generate_protocol_designer_test_fixture(outputPath)
% outputPath = generate_protocol_designer_test_fixture(outputPath)
% Generate a ProtocolDesigner test fixture with Software and offline
% TDT_RPcox interfaces, paired parameters across modules and interfaces,
% mixed parameter types, and example local and module-qualified expressions.
%
% Parameters:
%   outputPath - Destination .eprot path. Defaults to tmp/protocol_designer_expression_pairs_test.eprot.
%
% Returns:
%   outputPath - Saved .eprot file path.

    if nargin < 1 || isempty(outputPath)
        outputPath = fullfile(fileparts(mfilename('fullpath')), 'protocol_designer_expression_pairs_test.eprot');
    end

    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    epsych_startup();

    protocol = epsych.Protocol(Name = 'ProtocolDesignerExpressionPairsTest', ...
        Info = 'Fixture covering Software and offline TDT_RPcox modules with paired parameters, mixed types, and expression references.');
    protocol.Options.randomize = false;
    protocol.Options.numReps = 1;
    protocol.Options.ISI = 250;
    protocol.Options.ConnectionType = 'GB';

    softwareInterface = protocol.Interfaces(1);
    softwareModule = softwareInterface.Module;

    tdtInterface = hw.TDT_RPcox({}, {}, {}, Interface = 'GB', Connect = false);
    tdtModules = [ ...
        localCreateTdtModule_(tdtInterface, 'RP2', 'RPA', uint8(1), 'main_device.rcx', 1, 48828.125), ...
        localCreateTdtModule_(tdtInterface, 'RX8', 'RPB', uint8(2), 'aux_device.rcx', 2, 97656.25)];
    tdtInterface.setModules(tdtModules);
    protocol.addInterface(tdtInterface);

    localAddParameter_(softwareModule, 'baseGain', [10 20 30], ...
        Type = 'Float', Unit = 'dB', Pair = 'timingTriplet', Description = "Software gain values paired with TDT parameters");
    localAddParameter_(softwareModule, 'trialIndex', [1 2 3], ...
        Type = 'Integer', Pair = 'timingTriplet', Description = "Software integer parameter paired across interfaces");
    localAddParameter_(softwareModule, 'conditionLabel', 'baseline', ...
        Type = 'String', Pair = 'labelRoute', Description = "String values paired across interface boundaries");
    localAddParameter_(softwareModule, 'stimulusFile', 'stim_a.wav', ...
        Type = 'File', Pair = 'labelRoute', Description = "File values paired with string route labels");
    localAddParameter_(softwareModule, 'gateEnabled', true, ...
        Type = 'Boolean', Description = "Boolean parameter for type coverage");

    moduleA = tdtInterface.Module(1);
    moduleB = tdtInterface.Module(2);

    localAddParameter_(moduleA, 'gain', [1 2 3], ...
        Type = 'Float', Unit = 'V', Pair = 'timingTriplet', Description = "TDT module A gain paired with software and module B values");
    localAddParameter_(moduleA, 'delayMs', [5 10 15], ...
        Type = 'Integer', Unit = 'ms', Pair = 'timingTriplet', Description = "Module A timing parameter paired across modules and interfaces");
    localAddParameter_(moduleA, 'bufferName', 'buf_a', ...
        Type = 'String', Pair = 'labelRoute', Description = "String parameter paired with software labels and files");
    localAddParameter_(moduleA, 'triggerEnabled', false, ...
        Type = 'Boolean', Description = "Boolean parameter on module A");

    localAddParameter_(moduleB, 'attenuation', [0.5 1.0 1.5], ...
        Type = 'Float', Unit = 'V', Pair = 'timingTriplet', Description = "Module B attenuation paired with software and module A values");
    localAddParameter_(moduleB, 'gainFromA', 0, ...
        Type = 'Float', Expression = 'RPA.gain + attenuation', Description = "Cross-module expression using module.parameter syntax");
    localAddParameter_(moduleB, 'sumLocal', 0, ...
        Type = 'Float', Expression = 'attenuation + 2', Description = "Local expression using bare parameter name within the same module");
    localAddParameter_(moduleB, 'softwareLinked', 0, ...
        Type = 'Float', Expression = 'Params.baseGain + attenuation', Description = "Cross-interface expression that references the software module by name");
    localAddParameter_(moduleB, 'routeLabel', 'left', ...
        Type = 'String', Pair = 'labelRoute', Description = "String parameter paired with software and module A text parameters");
    localAddParameter_(moduleB, 'enableOutput', true, ...
        Type = 'Boolean', Description = "Boolean parameter on module B");

    protocol.save(outputPath);
end

function module = localCreateTdtModule_(interface, label, name, index, rpvdsFile, number, fs)
    module = hw.Module(interface, label, name, index);
    module.Fs = fs;
    module.Info = struct( ...
        'RPvdsFile', rpvdsFile, ...
        'Number', double(number), ...
        'FsOverride', double(fs), ...
        'ConnectionType', char(interface.ConnectionType));
end

function parameter = localAddParameter_(module, name, value, options)
    arguments
        module (1,1) hw.Module
        name (1,:) char
        value
        options.Type (1,:) char {mustBeMember(options.Type, {'Float', 'Integer', 'Boolean', 'Buffer', 'Coefficient Buffer', 'String', 'File', 'Undefined'})} = 'Float'
        options.Unit (1,:) char = ''
        options.Access (1,:) char {mustBeMember(options.Access, {'Read', 'Write', 'Any', 'Read / Write'})} = 'Any'
        options.Pair (1,:) char = ''
        options.Expression (1,:) char = ''
        options.Description (1,1) string = ""
        options.isArray (1,1) logical = false
        options.isTrigger (1,1) logical = false
        options.isRandom (1,1) logical = false
        options.Min (1,1) double = -inf
        options.Max (1,1) double = inf
    end

    userData = struct();
    if ~isempty(options.Pair)
        userData.Pair = options.Pair;
    end
    if ~isempty(options.Expression)
        userData.Expression = options.Expression;
    end
    if isempty(fieldnames(userData))
        userData = [];
    end

    parameter = module.add_parameter(name, value, ...
        Type = options.Type, ...
        Unit = options.Unit, ...
        Access = options.Access, ...
        Description = options.Description, ...
        UserData = userData, ...
        isArray = options.isArray || (iscell(value) && numel(value) > 1), ...
        isTrigger = options.isTrigger, ...
        isRandom = options.isRandom, ...
        Min = options.Min, ...
        Max = options.Max);
end