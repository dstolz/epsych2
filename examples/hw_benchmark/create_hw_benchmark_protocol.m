function outFile = create_hw_benchmark_protocol(outFile)
% outFile = create_hw_benchmark_protocol(outFile)
% Build a Software-only protocol carrying hw.benchmarkIO's default contract, so
% Utilities > Hardware > I/O Benchmark... has something to time with no
% hardware attached: add a subject using the saved .eprot, then run the menu item.
%
% The Software backend keeps what it is written, so the scalar read-back and
% buffer round trip work; timings are the in-memory floor, not a device's.
% For a real rig, add the same parameter names to that interface instead
% (an RPvds tag needs the ! prefix on the trigger).
%
%   matlab -batch "run('examples/hw_benchmark/create_hw_benchmark_protocol.m')"
arguments
    outFile (1,:) char = fullfile(fileparts(mfilename('fullpath')), 'HwBenchmark_Software.eprot')
end

p = epsych.Protocol( ...
    Name = 'HwBenchmarkSoftware', ...
    Info = 'Software-only protocol carrying the hw.benchmarkIO contract parameters.');

p.setOption('trialFunc',        '');
p.setOption('compileAtRuntime', false);
p.setOption('ConnectionType',   'GB');

mod = p.SoftwareModule.Module;
mod.add_parameter('WScalar',   0, Type='Float');
mod.add_parameter('RScalar',   0, Type='Float', Access='Read');
mod.add_parameter('BenchTrig', 0, isTrigger=true);
% One tag: the benchmark times it at each size the operator asks for.
mod.add_parameter('Buf',       0, Type='Buffer', isArray=true);

p.compile();
p.save(outFile);
fprintf('Protocol saved to: %s\n', outFile);
end
