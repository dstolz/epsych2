function smoke_test_crossinterface_expression_restore()
% smoke_test_crossinterface_expression_restore()
% Cover design-time Value restore for parameters whose Expression references a
% parameter on ANOTHER interface (e.g. "StimDelay + StimDur -
% Params.RespWinPreStim", where Params is a module on the Software interface
% and the target lives on the TDT interface).
%
% hw.Parameter.set.Value resolves such a reference through iface.Runtime;
% design-time code has no epsych.Runtime, so without
% epsych.Protocol.linkInterfacesForValueRestore the reference is unresolvable
% and the assignment throws hw:Parameter:ExpressionError. That is what broke
% ProtocolDesigner's "Modify Module" (changing a module's RPvds file), which
% clones the module and replays every parameter's Value.
%
%   matlab -batch "run('tmp/smoke_test_crossinterface_expression_restore.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

failures = {};

% ===== A. The unlinked baseline still fails ==============================
% Establishes that the link is what makes B..D pass, not some other change.
try
    P = localBuildProtocol_();
    target = localFind_(P, 'DSP', 'RespWinDelay');
    threw = false;
    try
        target.Value = 0;
    catch ME
        threw = strcmp(ME.identifier, 'hw:Parameter:ExpressionError');
    end
    assert(threw, 'expected an unlinked cross-interface assignment to throw');
    fprintf('A. unlinked cross-interface assignment throws: PASS\n');
catch ME
    failures{end+1} = sprintf('A: %s', ME.message);
    fprintf('A. unlinked baseline: FAIL (%s)\n', ME.message);
end

% ===== B. Linked restore resolves the reference ==========================
try
    P = localBuildProtocol_();
    target = localFind_(P, 'DSP', 'RespWinDelay');

    restoreLink = P.linkInterfacesForValueRestore();
    target.Value = 0;
    delete(restoreLink)

    % 1000 + 500 - 800
    assert(isequal(target.Value, 700), 'expected 700, got %s', mat2str(target.Value));

    % The link is released: interfaces present as unregistered again, and the
    % same assignment throws once more.
    for k = 1:numel(P.Interfaces)
        assert(isempty(P.Interfaces(k).Runtime), 'interface %d kept the temporary Runtime link', k);
    end
    threw = false;
    try
        target.Value = 0;
    catch
        threw = true;
    end
    assert(threw, 'link was not released');
    fprintf('B. linked restore resolves and releases: PASS\n');
catch ME
    failures{end+1} = sprintf('B: %s', ME.message);
    fprintf('B. linked restore: FAIL (%s)\n', ME.message);
end

% ===== C. A real epsych.Runtime link is left alone =======================
% An interface already registered with a Runtime sees every interface through
% it; overwriting and then clearing that link would unregister a live session.
try
    P = localBuildProtocol_();
    rt = epsych.Runtime;
    P.Interfaces(1).Runtime = rt;

    restoreLink = P.linkInterfacesForValueRestore();
    assert(P.Interfaces(1).Runtime == rt, 'existing Runtime link was replaced');
    assert(P.Interfaces(2).Runtime == P, 'unlinked interface was not linked');
    delete(restoreLink)

    assert(P.Interfaces(1).Runtime == rt, 'existing Runtime link was detached');
    assert(isempty(P.Interfaces(2).Runtime), 'temporary link was not detached');
    fprintf('C. pre-existing Runtime link preserved: PASS\n');
catch ME
    failures{end+1} = sprintf('C: %s', ME.message);
    fprintf('C. pre-existing Runtime link: FAIL (%s)\n', ME.message);
end

% ===== D. The designer's clone-and-replay sequence ========================
% Mirrors ProtocolDesigner/private/applyUpdatedModuleOptions: rebuild a module
% (as changing its RPvds file does), clone its parameters metadata-first, swap
% the module in, then replay every Value.
try
    P = localBuildProtocol_();
    iface = P.Interfaces(2);
    sourceModule = iface.Module(1);

    updatedModule = hw.Module(iface, sourceModule.Label, sourceModule.Name, sourceModule.Index);
    updatedModule.Info = sourceModule.Info;
    updatedModule.Info.RPvdsFile = 'C:\some\other\circuit.rcx';

    parameters = hw.Parameter.empty(1, 0);
    paramStructs = {};
    for k = 1:numel(sourceModule.Parameters)
        cloned = hw.Parameter(iface);
        cloned.Module = updatedModule;
        s = sourceModule.Parameters(k).toStruct();
        cloned.fromStruct(s, false);
        updatedModule.Parameters(end + 1) = cloned;
        parameters(end + 1) = cloned;
        paramStructs{end + 1} = s;
    end

    modules = iface.Module;
    modules(1) = updatedModule;
    iface.setModules(modules);

    restoreLink = P.linkInterfacesForValueRestore();
    for k = 1:numel(parameters)
        parameters(k).fromStruct(paramStructs{k});
    end
    delete(restoreLink)

    restored = localFind_(P, 'DSP', 'RespWinDelay');
    assert(isequal(restored.Value, 700), 'expected 700 after module rebuild, got %s', ...
        mat2str(restored.Value));
    assert(strcmp(restored.Module.Info.RPvdsFile, 'C:\some\other\circuit.rcx'), ...
        'rebuilt module lost its new RPvds file');
    fprintf('D. module rebuild replays cross-interface expression: PASS\n');
catch ME
    failures{end+1} = sprintf('D: %s', ME.message);
    fprintf('D. module rebuild: FAIL (%s)\n', ME.message);
end

% ===== E. Protocol load round trip (regression) ==========================
% fromStruct now takes the link from the same helper.
try
    P = localBuildProtocol_();
    f = [tempname '.eprot'];
    cleanupFile = onCleanup(@() localDeleteFile_(f));
    P.save(f);

    Q = epsych.Protocol.load(f);
    loaded = localFind_(Q, 'DSP', 'RespWinDelay');
    assert(isequal(loaded.Value, 700), 'loaded value expected 700, got %s', mat2str(loaded.Value));
    for k = 1:numel(Q.Interfaces)
        assert(isempty(Q.Interfaces(k).Runtime), 'load left interface %d linked to the Protocol', k);
    end
    fprintf('E. protocol save/load round trip: PASS\n');
catch ME
    failures{end+1} = sprintf('E: %s', ME.message);
    fprintf('E. protocol round trip: FAIL (%s)\n', ME.message);
end

fprintf('\n');
if isempty(failures)
    fprintf('ALL CHECKS PASSED\n');
else
    fprintf('%d CHECK(S) FAILED:\n', numel(failures));
    fprintf('  %s\n', failures{:});
end
end


function P = localBuildProtocol_()
% Two interfaces: Software module "Params" holds the reference target, and a
% TDT_RPcox module holds the parameter whose Expression reaches across.
P = epsych.Protocol;

sw = P.Interfaces(1);
swModule = sw.Module(1);
p = swModule.add_parameter('RespWinPreStim', 800);
p.Value = 800;

tdt = hw.TDT_RPcox;
P.addInterface(tdt);
m = hw.Module(tdt, 'RZ6', 'DSP', 1);
m.Info = struct('RPvdsFile', 'C:\some\circuit.rcx', 'Number', 1, 'ConnectionType', 'GB');
tdt.setModules(m);

p = m.add_parameter('StimDelay', 1000); p.Value = 1000;
p = m.add_parameter('StimDur', 500);    p.Value = 500;
p = m.add_parameter('RespWinDelay', 0);
p.Expression = "StimDelay + StimDur - Params.RespWinPreStim";
end


function p = localFind_(P, moduleName, paramName)
p = hw.Parameter.empty(1, 0);
for i = 1:numel(P.Interfaces)
    for m = 1:numel(P.Interfaces(i).Module)
        mod = P.Interfaces(i).Module(m);
        if ~strcmp(mod.Name, moduleName)
            continue
        end
        for k = 1:numel(mod.Parameters)
            if strcmp(mod.Parameters(k).Name, paramName)
                p = mod.Parameters(k);
                return
            end
        end
    end
end
error('parameter %s.%s not found', moduleName, paramName);
end


function localDeleteFile_(f)
if isfile(f)
    delete(f);
end
end
