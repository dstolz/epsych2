function smoke_test_calibration_gui_launch()
% smoke_test_calibration_gui_launch()
% Verify the relaxed CalibrationGui constructor and the epsych.calibrate
% launcher. Headless-safe: every GUI is closed before returning.
%
%   matlab -batch "cd('tmp'); smoke_test_calibration_gui_launch"

epsych_startup

guis = {};
cleanupObj = onCleanup(@() close_all_uifigures());

% 1. No arguments — offline engine created automatically.
g = stimgen.calibration.CalibrationGui();
assert(isa(g.Engine,'stimgen.calibration.Engine'), 'Default engine not created');
guis{end+1} = g;
fprintf('PASS: CalibrationGui() offline\n');

% 2. Host alone, no engine — the case that used to require both arguments.
host = stimbridge.RuntimeHost;
g = stimgen.calibration.CalibrationGui(host);
assert(isa(g.Engine,'stimgen.calibration.Engine'), 'Default engine not created with host');
guis{end+1} = g;
fprintf('PASS: CalibrationGui(host)\n');

% 3. Engine alone.
eng = stimgen.calibration.Engine();
g = stimgen.calibration.CalibrationGui(eng);
assert(g.Engine == eng, 'Supplied engine not retained');
guis{end+1} = g;
fprintf('PASS: CalibrationGui(eng)\n');

% 4. Either order, plus name-value.
g = stimgen.calibration.CalibrationGui(host, eng);   guis{end+1} = g;
assert(g.Engine == eng, 'Reversed positional order lost the engine');
g = stimgen.calibration.CalibrationGui(eng, host);   guis{end+1} = g;
g = stimgen.calibration.CalibrationGui(Host=host, Engine=eng); guis{end+1} = g;
assert(g.Engine == eng, 'Name-value Engine lost');
g = stimgen.calibration.CalibrationGui([]);          guis{end+1} = g;  % forwarded empty host
fprintf('PASS: order-independent and name-value forms\n');

% 5. Bad argument still raises a clear identifier.
try
    stimgen.calibration.CalibrationGui(42);
    error('Expected an error for an unrecognized argument');
catch ME
    assert(strcmp(ME.identifier,'stimgen:calibration:CalibrationGui:invalidArgument'), ...
        'Unexpected identifier: %s', ME.identifier);
end
fprintf('PASS: invalid argument rejected\n');

% 6. epsych.calibrate with no protocol — builds the host itself.
g = epsych.calibrate; guis{end+1} = g;
assert(isa(g,'stimgen.calibration.CalibrationGui'), 'epsych.calibrate returned the wrong type');
fprintf('PASS: epsych.calibrate()\n');

% 7. epsych.calibrate with a bad protocol path must warn, not throw.
g = epsych.calibrate('this_protocol_does_not_exist.eprot'); guis{end+1} = g;
assert(isa(g,'stimgen.calibration.CalibrationGui'), 'Launcher aborted on a bad protocol');
fprintf('PASS: epsych.calibrate(badPath) degrades to offline\n');

fprintf('\nAll calibration launch smoke tests passed (%d GUIs)\n', numel(guis));
end

function close_all_uifigures()
f = findall(groot,'Type','figure');
delete(f);
end
