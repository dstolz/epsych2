% smoke_test_teensy_firmware_contract.m
% Cross-checks firmware/EPsychTeensy against the MATLAB hw.Teensy backend.
%
% The firmware and the host agree on things no compiler and no MATLAB test can
% see on their own: bit indices, protocol version, buffer sizes, parameter
% names, and the field order of a DESC line. Each of those fails SILENTLY when
% it drifts — a shifted BitMask index produces a plausible-but-wrong
% psychometric curve, not an error — so they are checked here by parsing the
% firmware source.
%
% This is not a substitute for compiling the firmware; it is the part of
% correctness that compiling would not catch anyway.
%
% Run headless:
%   matlab -batch "run('tmp/smoke_test_teensy_firmware_contract.m')"

fprintf('\n=== EPsychTeensy Firmware Contract Test ===\n\n');
results = {};

fwDir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'firmware', 'EPsychTeensy');

%% 0. Firmware sources are present
try
    required = {'EPsychTeensy.ino', 'Config.h', 'Clock.h', 'Critical.h', 'BitMask.h', ...
                'EventQueue.h', 'Params.h', 'Params.cpp', 'DigitalIO.h', 'DigitalIO.cpp', ...
                'TrialFSM.h', 'TrialFSM.cpp', 'Protocol.h', 'Protocol.cpp'};
    missing = required(~cellfun(@(f) isfile(fullfile(fwDir, f)), required));
    results(end+1,:) = check('All firmware sources present', isempty(missing));
    if ~isempty(missing)
        fprintf('    missing: %s\n', strjoin(missing, ', '));
    end
catch ME
    results(end+1,:) = check(['Source listing: ' ME.message], false);
end

config    = fileread(fullfile(fwDir, 'Config.h'));
bitmaskH  = fileread(fullfile(fwDir, 'BitMask.h'));
paramsH   = fileread(fullfile(fwDir, 'Params.h'));
paramsC   = fileread(fullfile(fwDir, 'Params.cpp'));
protocolC = fileread(fullfile(fwDir, 'Protocol.cpp'));

boxID = str2double(defineValue(config, 'BOX_ID'));

%% 1. BitMask.h mirrors epsych.BitMask exactly
% This is the highest-consequence agreement in the whole backend: the firmware
% builds RespCode from these indices and psychophysics.Detection decodes it.
try
    enumBody = extractBetween(bitmaskH, 'enum Bit : uint8_t {', '};');
    tok = regexp(enumBody{1}, '(\w+)\s*=\s*(\d+)\s*,', 'tokens');
    fwBits = containers.Map('KeyType', 'char', 'ValueType', 'double');
    for i = 1:numel(tok)
        fwBits(tok{i}{1}) = str2double(tok{i}{2});
    end

    [names, values] = epsych.BitMask.list();
    mismatched = {};
    for i = 1:numel(names)
        if isKey(fwBits, names{i}) && fwBits(names{i}) ~= double(values(i))
            mismatched{end+1} = names{i};
        end
    end
    results(end+1,:) = check('Firmware bit indices match epsych.BitMask', isempty(mismatched));
    if ~isempty(mismatched)
        fprintf('    mismatched: %s\n', strjoin(mismatched, ', '));
    end

    % Spot-check the outcomes the trial state machine actually emits.
    for nm = {'Hit', 'Miss', 'CorrectReject', 'FalseAlarm', 'Reward', 'Punish', ...
              'ResponseWindow', 'PreResponseWindow', 'PostResponseWindow', 'TrialType_0'}
        results(end+1,:) = check(sprintf('%s index defined in firmware', nm{1}), ...
            isKey(fwBits, nm{1}));
    end

    % The 1-based -> shift conversion. epsych.BitMask.Bits2Mask computes
    % sum(bitshift(uint32(1), b-1)), so bm::of(b) must be 1 << (b-1).
    results(end+1,:) = check('Firmware shifts by (bitIndex - 1)', ...
        contains(bitmaskH, '(uint32_t)1 << (bitIndex - 1)'));

    % Hit+Reward is what a rewarded Go trial produces; assert the exact mask.
    expected = epsych.BitMask.Bits2Mask([double(epsych.BitMask.Hit), double(epsych.BitMask.Reward)]);
    results(end+1,:) = check('Hit+Reward encodes as 33', expected == 33);
catch ME
    results(end+1,:) = check(['BitMask contract: ' ME.message], false);
end

%% 2. Protocol version and buffer sizes agree with hw.Teensy
try
    fwProto = str2double(defineValue(config, 'PROTO_VERSION'));
    results(end+1,:) = check('PROTO_VERSION matches hw.Teensy.PROTOCOL_VERSION', ...
        fwProto == hw.Teensy.PROTOCOL_VERSION);

    fwLine = str2double(defineValue(config, 'LINE_BUFFER_LEN'));
    % The host chunks batched SETM writes below MAX_LINE_LENGTH; if the board's
    % buffer were smaller, a long batch would be truncated mid-assignment.
    results(end+1,:) = check('LINE_BUFFER_LEN >= hw.Teensy.MAX_LINE_LENGTH', ...
        fwLine >= hw.Teensy.MAX_LINE_LENGTH);
catch ME
    results(end+1,:) = check(['Version/buffer contract: ' ME.message], false);
end

%% 3. The parameter table and its index enum cannot drift
try
    tableBody = extractBetween(paramsC, 'const ParamDef PARAMS[NUM_PARAMS] = {', '};');
    rows = regexp(tableBody{1}, '\{\s*"([^"]*)"\s*(BOX_SUFFIX)?\s*,\s*(A_\w+)\s*,\s*(P_\w+)\s*,\s*(F_\w+)', 'tokens');

    fwNames = cell(1, numel(rows));
    fwAccess = cell(1, numel(rows));
    fwFlags = cell(1, numel(rows));
    for i = 1:numel(rows)
        nm = rows{i}{1};
        if ~isempty(rows{i}{2})
            nm = [nm num2str(boxID)];   % "x_NewTrial_" BOX_SUFFIX
        end
        fwNames{i} = nm;
        fwAccess{i} = rows{i}{3};
        fwFlags{i} = rows{i}{5};
    end

    enumBody = extractBetween(paramsH, 'enum ParamIndex : uint8_t {', 'NUM_PARAMS');
    enumTok = regexp(enumBody{1}, '^\s*(PX_\w+)\s*(?:=\s*\d+\s*)?,', 'tokens', 'lineanchors');

    results(end+1,:) = check('Parameter table is non-empty', ~isempty(fwNames));
    % Order-must-match is the classic failure here: an enum entry inserted
    % without a matching table row silently shifts every later parameter.
    results(end+1,:) = check('ParamIndex enum and PARAMS table have equal length', ...
        numel(enumTok) == numel(fwNames));
    results(end+1,:) = check('Parameter names are unique', ...
        numel(unique(fwNames)) == numel(fwNames));
catch ME
    results(end+1,:) = check(['Parameter table: ' ME.message], false);
end

%% 4. The names epsych.Runtime requires exist, with usable access
try
    for nm = {sprintf('x_NewTrial_%d', boxID), sprintf('x_ResetTrig_%d', boxID), ...
              sprintf('x_TrialComplete_%d', boxID)}
        idx = find(strcmp(fwNames, nm{1}), 1);
        results(end+1,:) = check(sprintf('Firmware publishes %s', nm{1}), ~isempty(idx));
    end

    % A trigger declared write-only is dropped by Runtime.all_parameters and the
    % session aborts with epsych:RunExpt:MissingTrigger. A_RW maps to Access='Any'.
    for nm = {sprintf('x_NewTrial_%d', boxID), sprintf('x_ResetTrig_%d', boxID)}
        idx = find(strcmp(fwNames, nm{1}), 1);
        results(end+1,:) = check(sprintf('%s is a trigger', nm{1}), ...
            ~isempty(idx) && strcmp(fwFlags{idx}, 'F_TRIG'));
        results(end+1,:) = check(sprintf('%s is not write-only', nm{1}), ...
            ~isempty(idx) && ~strcmp(fwAccess{idx}, 'A_W'));
    end

    idx = find(strcmp(fwNames, sprintf('x_TrialComplete_%d', boxID)), 1);
    results(end+1,:) = check('x_TrialComplete is readable', ...
        ~isempty(idx) && strcmp(fwAccess{idx}, 'A_R'));
catch ME
    results(end+1,:) = check(['Required names: ' ME.message], false);
end

%% 5. Conventional names the shipped GUIs and analyses look for
try
    for nm = {'RespCode', 'RespLatency', 'InTrial', 'TrialType'}
        results(end+1,:) = check(sprintf('Firmware publishes %s', nm{1}), ...
            any(strcmp(fwNames, nm{1})));
    end
    % gui.components.OnlinePlot looks up these exact literals, note the ~<BoxID> suffix
    % form rather than the x_*_<BoxID> form used by the required triggers.
    for nm = {sprintf('_TrigState~%d', boxID), sprintf('_TrialNum~%d', boxID)}
        results(end+1,:) = check(sprintf('Firmware publishes %s for gui.components.OnlinePlot', nm{1}), ...
            any(strcmp(fwNames, nm{1})));
    end

    % RespCode must be an integer parameter: it is a uint32 bitmask whose high
    % bits a float32 cannot represent exactly.
    respRow = regexp(paramsC, '\{\s*"RespCode"\s*,\s*A_\w+\s*,\s*(P_\w+)', 'tokens', 'once');
    results(end+1,:) = check('RespCode is an integer parameter', ...
        ~isempty(respRow) && strcmp(respRow{1}, 'P_I'));
    results(end+1,:) = check('Integer parameters print exactly, not via %g', ...
        contains(paramsC, '"%ld"'));
catch ME
    results(end+1,:) = check(['Conventional names: ' ME.message], false);
end

%% 6. DESC line field order matches the host parser
% populateModuleParametersFromDescriptor reads
%   tok{2}=name tok{3}=access tok{4}=type tok{5}=flags tok{6}=min tok{7}=max tok{8}=unit
try
    descBody = extractBetween(protocolC, 'void cmdDesc() {', '\n}');
    if isempty(descBody)
        descBody = extractBetween(protocolC, 'void cmdDesc() {', 'void cmdGet');
    end
    body = descBody{1};

    order = regexp(body, 'Serial\.print(?:ln)?\((?:d\.)?(\w+)', 'tokens');
    order = cellfun(@(t) t{1}, order, UniformOutput = false);
    order = order(~strcmp(order, 'P'));   % the leading "P " literal

    results(end+1,:) = check('DESC emits name, acc, typ, flags, lo, hi, unit in order', ...
        isequal(order, {'name', 'acc', 'typ', 'flags', 'lo', 'hi', 'unit'}));
    results(end+1,:) = check('DESC block is delimited by BEGIN/END', ...
        contains(body, '"DESC BEGIN"') && contains(body, '"DESC END"'));
catch ME
    results(end+1,:) = check(['DESC field order: ' ME.message], false);
end

%% 7. Every command hw.Teensy issues is implemented
try
    for cmd = {'ID?', 'DESC?', 'GET', 'SET', 'SETM', 'SNAP', 'TRG', 'MODE', 'MODE?', 'EVT?', 'SYNC'}
        results(end+1,:) = check(sprintf('Firmware implements %s', cmd{1}), ...
            contains(protocolC, sprintf('"%s"', cmd{1})));
    end
    % SNAP must carry MODE, so the host's per-tick mode read is free.
    results(end+1,:) = check('SNAP carries MODE', contains(protocolC, '" MODE="'));
    results(end+1,:) = check('SNAP carries the pending event count', ...
        contains(protocolC, '" NEVT="'));
catch ME
    results(end+1,:) = check(['Command coverage: ' ME.message], false);
end

%% 8. Rollover safety and ISR discipline
try
    clockH = fileread(fullfile(fwDir, 'Clock.h'));
    results(end+1,:) = check('Firmware uses a 64-bit microsecond clock', ...
        contains(clockH, 'uint64_t micros64()'));

    % noInterrupts()/interrupts() inside anything the ISR can reach would
    % re-enable interrupts mid-section and allow the scheduler ISR to re-enter
    % itself. Everything reachable from the ISR must use critEnter/critExit.
    isrReachable = {'DigitalIO.cpp', 'TrialFSM.cpp', 'Clock.h', 'EventQueue.h'};
    offenders = {};
    for i = 1:numel(isrReachable)
        src = fileread(fullfile(fwDir, isrReachable{i}));
        hasNoInterrupts = contains(src, 'noInterrupts()');
        % Match a bare interrupts(); call, but not the tail of noInterrupts().
        hasBareInterrupts = ~isempty(regexp(src, '(?<![\w])interrupts\(\)\s*;', 'once'));
        if hasNoInterrupts || hasBareInterrupts
            offenders{end+1} = isrReachable{i};
        end
    end
    results(end+1,:) = check('ISR-reachable code uses nesting-safe critical sections', ...
        isempty(offenders));
    if ~isempty(offenders)
        fprintf('    offenders: %s\n', strjoin(offenders, ', '));
    end
catch ME
    results(end+1,:) = check(['ISR discipline: ' ME.message], false);
end

%% Summary
labels = results(:,1);
passed = cell2mat(results(:,2));
for i = 1:numel(labels)
    if passed(i)
        fprintf('  PASS  %s\n', labels{i});
    else
        fprintf('  FAIL  %s\n', labels{i});
    end
end
fprintf('\n%d passed, %d failed, %d total\n\n', sum(passed), sum(~passed), numel(passed));

if any(~passed)
    error('smoke_test_teensy_firmware_contract:Failed', '%d test(s) failed.', sum(~passed));
end


function row = check(label, tf)
row = {label, logical(tf)};
end

function v = defineValue(src, name)
% v = defineValue(src, name)
% Read the literal of a "#define <name> <literal>" from C source.
tok = regexp(src, ['#define\s+' name '\s+([^\s/]+)'], 'tokens', 'once');
if isempty(tok)
    error('Config define "%s" not found.', name);
end
v = strtrim(tok{1});
end
