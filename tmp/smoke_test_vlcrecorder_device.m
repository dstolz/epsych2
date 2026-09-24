function smoke_test_vlcrecorder_device()
% smoke_test_vlcrecorder_device()
% Smoke test for hw.VlcRecorder's camera auto-selection. Headless: exercises
% the pure rule hw.VlcRecorder.chooseDevice and the new default, and never
% launches VLC or enumerates hardware.
%
% Verifies:
%   1) DeviceName defaults to '' rather than a named camera.
%   2) '' becomes the first enumerated device.
%   3) A chosen name is kept whether or not it is present.
%   4) The legacy default is replaced only when no camera by that name exists.
%   5) With nothing enumerated, the configured name is returned unchanged.
%
%   matlab -batch "run('tmp/smoke_test_vlcrecorder_device.m')"
%
% See also: hw.VlcRecorder, documentation/hw/hw_VlcRecorder.md

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

devs = {'Logi C270 HD WebCam', 'USB Camera'};
legacy = hw.VlcRecorder.LEGACY_DEFAULT_DEVICE;

rec = hw.VlcRecorder();
c = onCleanup(@() delete(rec));
assert(isempty(char(rec.get_parameter('DeviceName'))), 'DeviceName default is not empty');

assert(hw.VlcRecorder.chooseDevice('', devs) == "Logi C270 HD WebCam", 'empty name not resolved to first device');
assert(hw.VlcRecorder.chooseDevice('  ', devs) == "Logi C270 HD WebCam", 'blank name not resolved to first device');

assert(hw.VlcRecorder.chooseDevice('USB Camera', devs) == "USB Camera", 'present chosen name replaced');
assert(hw.VlcRecorder.chooseDevice('Unplugged Cam', devs) == "Unplugged Cam", 'absent chosen name replaced');

assert(hw.VlcRecorder.chooseDevice(legacy, devs) == "Logi C270 HD WebCam", 'absent legacy default not replaced');
assert(hw.VlcRecorder.chooseDevice(legacy, [devs {char(legacy)}]) == legacy, 'present legacy default replaced');

assert(hw.VlcRecorder.chooseDevice('', {}) == "", 'empty name changed with no devices');
assert(hw.VlcRecorder.chooseDevice(legacy, {}) == legacy, 'legacy name changed with no devices');

fprintf('smoke_test_vlcrecorder_device: all checks passed\n');
end
