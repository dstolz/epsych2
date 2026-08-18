function smoke_test_calibration_gain_fields()
% smoke_test_calibration_gain_fields()
% Verify the two recorded-only hardware gain fields, Engine.AdcGain and
% Engine.DacAttenuation, from the model layer up to the CalibrationGui dialog
% that sets them.
%
% Five things are checked:
%
%   1. Both default to 0 dB and survive every serialization path a
%      calibration has: StimCalibration.toStruct, saveobj/loadobj, and the
%      .esgc file. An .esgc written before the fields existed loads at 0 dB
%      rather than failing.
%   2. They are exposed on stimgen.StimCalibration as delegated properties,
%      so a StimType's calibration reports them.
%   3. The CalibrationGui's Hardware and Analysis Settings window carries an
%      ADC Gain and a DAC Attenuation row under a heading that says they are
%      recorded, not applied, and each pushes to the engine as it is
%      committed like every other field on that window.
%   4. Closing the window remembers both in the GUI's preferences, and a
%      fresh window restores them onto a factory engine.
%   5. Neither changes a lookup: compute_adjusted_voltage returns the same
%      voltage before and after 40/60 dB are recorded. This is the whole
%      point of the pair -- the sweep was measured through the rig's gain, so
%      it is already inside the tables, and applying it again would
%      double-count it.
%
% Runs headless. No adapter is needed; nothing here plays a signal.
%
%   matlab -batch "cd('tmp'); smoke_test_calibration_gain_fields"

thisDir = fileparts(mfilename('fullpath'));
run(fullfile(thisDir, '..', 'epsych_startup.m'));

% The GUI writes these two on its close path. Put the rig's own values back
% afterwards, including "never set".
GRP = 'StimCalibrationGui';
KEYS = ["AdcGain" "DacAttenuation"];
saved = struct();
for k = KEYS
    if ispref(GRP, char(k))
        saved.(k) = getpref(GRP, char(k));
        rmpref(GRP, char(k));
    end
end
restorePrefs = onCleanup(@() restore_prefs_(GRP, KEYS, saved)); %#ok<NASGU>

%% 1-2. Model layer: defaults, delegation, and every serialization path.
cal = stimgen.StimCalibration();
assert(cal.AdcGain == 0 && cal.DacAttenuation == 0, 'both default to 0 dB');

cal.AdcGain = 26;
cal.DacAttenuation = 18.5;
assert(cal.AdcGain == 26 && cal.DacAttenuation == 18.5, 'delegated setters reach the Engine');

s = cal.toStruct();
c2 = stimgen.StimCalibration();
c2.Engine.restore(s);
assert(c2.AdcGain == 26 && c2.DacAttenuation == 18.5, 'toStruct round trip');

c3 = stimgen.StimCalibration.loadobj(cal.saveobj());
assert(c3.AdcGain == 26 && c3.DacAttenuation == 18.5, 'saveobj/loadobj round trip');

% .esgc needs a calibration to save; restore() is the supported way in, the
% measurement properties being SetAccess = protected.
cal.Engine.restore(struct('CalibrationData', struct('tone', struct( ...
    'frequency', [1000; 2000], 'measurement', [1; 1], ...
    'spl_db', [80; 80], 'voltage', [0.5; 0.5]))));
ffn = fullfile(tempdir, 'smoke_gain_fields.esgc');
ffnOld = fullfile(tempdir, 'smoke_gain_fields_old.esgc');
cleanupFiles = onCleanup(@() delete_if_present_({ffn, ffnOld})); %#ok<NASGU>
cal.Engine.save(ffn);
eng = stimgen.calibration.Engine.load(ffn);
assert(eng.AdcGain == 26 && eng.DacAttenuation == 18.5, '.esgc round trip');

% A file written before the fields existed: neither key present.
sOld = rmfield(load(ffn, '-mat'), {'AdcGain', 'DacAttenuation'});
save(ffnOld, '-struct', 'sOld');
engOld = stimgen.calibration.Engine.load(ffnOld);
assert(engOld.AdcGain == 0 && engOld.DacAttenuation == 0, 'older .esgc loads at 0 dB');

%% 5. Recorded, never applied.
v0 = eng.compute_adjusted_voltage("tone", 1500, 70);
eng.set_configuration(AdcGain=40, DacAttenuation=60);
v1 = eng.compute_adjusted_voltage("tone", 1500, 70);
assert(isequaln(v0, v1), 'neither field may affect compute_adjusted_voltage');
fprintf('lookup unchanged: %.6g V before and after 40/60 dB were recorded\n', v0);

%% 3. The dialog. Scope every lookup to the window this test opens -- a rig
% may well have a calibration GUI of its own on screen.
before = findall(groot, 'Type', 'figure');
gui = stimgen.calibration.CalibrationGui();
mainFig = setdiff(findall(groot, 'Type', 'figure'), before);
assert(isscalar(mainFig), 'one new window');
closeGui = onCleanup(@() delete(gui)); %#ok<NASGU>

m = findall(mainFig, 'Type', 'uimenu', 'Text', 'Hardware and Analysis Settings...');
assert(isscalar(m), 'the Options menu item is there');
before = findall(groot, 'Type', 'figure');
feval(m.MenuSelectedFcn, m, []);
dlg = setdiff(findall(groot, 'Type', 'figure'), before);
assert(isscalar(dlg) && strcmp(dlg.Name, 'Hardware and Analysis Settings'), 'dialog opened');

labels = findall(dlg, 'Type', 'uilabel');
texts = string({labels.Text});
assert(any(texts == "Hardware Gain (recorded, not applied)"), ...
    'the heading says the fields are not applied');
assert(any(texts == "ADC Gain (dB)") && any(texts == "DAC Attenuation (dB)"), ...
    'both rows present');
assert(any(texts == "Max Output Voltage (V)") && any(texts == "Spectral Analysis"), ...
    'the rows the two were inserted among are still there');

adc = field_beside_(dlg, labels, "ADC Gain (dB)");
dac = field_beside_(dlg, labels, "DAC Attenuation (dB)");
assert(adc.Value == 0 && dac.Value == 0, 'fields open at the engine value');
assert(~isempty(adc.Tooltip) && ~isempty(dac.Tooltip), ...
    'tooltips resolve from tooltips.json');

maxOutBefore = gui.Engine.MaxOutputVoltage;
adc.Value = 26;
feval(adc.ValueChangedFcn, adc, []);
dac.Value = 18.5;
feval(dac.ValueChangedFcn, dac, []);
assert(gui.Engine.AdcGain == 26 && gui.Engine.DacAttenuation == 18.5, ...
    'each field pushes to the engine as it is committed');
assert(gui.Engine.MaxOutputVoltage == maxOutBefore, ...
    'the settings sharing the window are untouched');

%% 4. Preferences: typed once per rig, not once per session. They are written
% by the figure's close request rather than the object destructor, so close
% the window the way an operator does.
feval(mainFig.CloseRequestFcn, mainFig, []);
assert(str2double(getpref(GRP, 'AdcGain')) == 26, 'AdcGain remembered');
assert(str2double(getpref(GRP, 'DacAttenuation')) == 18.5, 'DacAttenuation remembered');

gui2 = stimgen.calibration.CalibrationGui();
assert(gui2.Engine.AdcGain == 26 && gui2.Engine.DacAttenuation == 18.5, ...
    'a fresh window restores them onto a factory engine');
delete(gui2);

disp('PASS: smoke_test_calibration_gain_fields')
end

% -------------------------------------------------------------------------
function fld = field_beside_(dlg, labels, labelText)
% The numeric field sharing a grid row with a caption. The dialog's handles
% are private, so a row is found the way it is laid out.
lbl = labels(string({labels.Text}) == labelText);
flds = findall(dlg, 'Type', 'uinumericeditfield');
fld = flds(arrayfun(@(f) f.Layout.Row == lbl.Layout.Row, flds));
assert(isscalar(fld), 'one field beside "%s"', labelText);
end

% -------------------------------------------------------------------------
function restore_prefs_(grp, keys, saved)
for k = keys
    if isfield(saved, k)
        setpref(grp, char(k), saved.(k));
    elseif ispref(grp, char(k))
        rmpref(grp, char(k));
    end
end
end

% -------------------------------------------------------------------------
function delete_if_present_(files)
for k = 1:numel(files)
    if isfile(files{k}), delete(files{k}); end
end
end
