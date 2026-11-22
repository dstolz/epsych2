function smoke_test_ne1000_settings_cache
% smoke_test_ne1000_settings_cache
% Two opt-in ways hw.NE1000 can stop repeating itself on the wire, both off
% by default, each a blocking RS-232 transaction saved:
%
%   SettingsCacheInterval  a setting the pump reported answers the next read
%   SkipUnchangedWrites    a Rate or Volume the pump was just read back
%                          holding is not written again in a trial dispatch
%
% Runs against tmp/NE1000_Mock, which overrides only the transport seam and
% logs every command line, so the counts here are commands a pump would see.
%
% Verifies:
%   1) off (the default): every read of a setting is a query
%   2) with an interval: the second read is served; Status and the dispensed
%      volumes never are
%   3) a write through the interface drops that setting's entry
%   4) a change at the keypad is seen once the interval has passed
%   5) an alarm, a refused write, a Diameter write and a reconnect drop everything
%   6) holdsValue: Rate needs the same four digits AND the same units; Volume
%      the same four digits; nothing else is ever "already held"
%   7) in a dispatch an unchanged Rate/Volume is not sent, a changed one is,
%      and a rate the pump holds in other units is rewritten with units
%   8) both on: a trial's sweep and dispatch put nothing on the wire for
%      Rate and Volume
%
% No hardware, no windows.
%
%   matlab -batch "run('tmp/smoke_test_ne1000_settings_cache.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));
addpath(here);

fprintf('\n=== smoke_test_ne1000_settings_cache ===\n');

pump = NE1000_Mock();
cleanup = onCleanup(@() localDelete(pump));
assert(pump.IsConnected, 'the mock pump should connect');
assert(pump.SettingsCacheInterval == 0 && ~pump.SkipUnchangedWrites, 'both are off by default');

pRate = pump.find_parameter('Rate');
pVol = pump.find_parameter('Volume');
pDia = pump.find_parameter('Diameter', includeInvisible = true);
pDir = pump.find_parameter('Direction', includeInvisible = true);
pStatus = pump.find_parameter('Status', includeInvisible = true);
pInf = pump.find_parameter('VolumeInfused');

pRate.Value = 2;
pVol.Value = 0.05;

% --- 1. off: every read is a query -------------------------------------------
pump.Log = {};
a = pRate.Value; b = pRate.Value;
assert(a == 2 && b == 2 && localCount(pump, 'RAT') == 2, 'off: two reads are two RAT queries');
fprintf('PASS: 1 off by default, every read of a setting is a query\n');

% --- 2. with an interval -----------------------------------------------------
pump.SettingsCacheInterval = 30;
pump.Log = {};
a = pRate.Value;                      % a query, and the cache is seeded
b = pRate.Value;                      % served
c = pump.get_parameter('Rate');       % by name, as the operator panel reads it
assert(a == 2 && b == 2 && c == 2, 'the cached value is the value');
assert(localCount(pump, 'RAT') == 1, 'one query for three reads (got %d)', localCount(pump, 'RAT'));
[~] = pVol.Value; [~] = pVol.Value;
[~] = pDia.Value; [~] = pDia.Value;
[~] = pDir.Value; [~] = pDir.Value;
assert(localCount(pump, 'VOL') == 1 && localCount(pump, 'DIA') == 1 && localCount(pump, 'DIR') == 1, ...
    'Volume, Diameter and Direction are settings too');

pump.Log = {};
[~] = pStatus.Value; [~] = pStatus.Value;
assert(localCount(pump, '') == 2, 'Status is never served from the cache');
pump.DispenseCacheInterval = 0;
[~] = pInf.Value; [~] = pInf.Value;
assert(localCount(pump, 'DIS') == 2, 'the dispensed volume is never served from the settings cache');
fprintf('PASS: 2 a setting is served from what the pump reported; Status and DIS are not\n');

% --- 3. a write drops that setting -------------------------------------------
pump.Log = {};
pRate.Value = 3;
assert(pRate.Value == 3, 'the read after a write is the new value');
assert(localCount(pump, 'RAT') == 1, 'and it was asked of the pump, not served');
[~] = pVol.Value;
assert(localCount(pump, 'VOL') == 0, 'another setting''s entry is untouched by that write');
fprintf('PASS: 3 a write drops the entry of the setting written\n');

% --- 4. the keypad -----------------------------------------------------------
pump.SettingsCacheInterval = 0.2;
[~] = pRate.Value;                    % seed (the long-interval entry may still stand)
pump.SimRate = 9;                     % someone turned the knob
stale = pRate.Value;
pause(0.3);
fresh = pRate.Value;
assert(stale == 3, 'inside the interval the pump is not asked, so the keypad change is not seen');
assert(fresh == 9, 'after the interval it is (got %g)', fresh);
pump.SettingsCacheInterval = 30;
fprintf('PASS: 4 a keypad change is seen once the interval has passed\n');

% --- 5. what drops everything ------------------------------------------------
[~] = pRate.Value; [~] = pVol.Value;
pump.PendingAlarm = 'S';              % the next command is answered with a stall alarm
[~] = pStatus.Value;
pump.Log = {};
[~] = pRate.Value; [~] = pVol.Value;
assert(localCount(pump, 'RAT') == 1 && localCount(pump, 'VOL') == 1, 'an alarm drops every setting');

epoch0 = pump.DeviceEpoch;
pump.Log = {};
pDia.Value = 21.59;                   % the pump rescales rates and volume units on this
[~] = pRate.Value; [~] = pVol.Value;
assert(localCount(pump, 'RAT') == 1 && localCount(pump, 'VOL') == 1, 'a Diameter write drops every setting');
assert(pump.DeviceEpoch > epoch0, 'and retires every read-back');

pump.Log = {};
ok = pump.set_parameter('Diameter', 500);   % out of range: refused
assert(~ok, 'the mock refuses a 500 mm syringe');
[~] = pRate.Value;
assert(localCount(pump, 'RAT') == 1, 'a refused write drops every setting');

pump.disconnect();
pump.connect();
pRate = pump.find_parameter('Rate');
pVol = pump.find_parameter('Volume');
pump.Log = {};
[~] = pRate.Value;
assert(localCount(pump, 'RAT') == 1, 'a reconnect drops every setting');
fprintf('PASS: 5 an alarm, a Diameter write, a refused write and a reconnect drop everything\n');

% --- 6. holdsValue -----------------------------------------------------------
pRate.Value = 2;
[~] = pRate.Value;                    % the pump reports 2 MH
assert(pump.holdsValue(pRate, 2, 2), 'the same rate in the same units is held');
assert(pump.holdsValue(pRate, 2, 2.0004), 'what formats to the same four digits is the same rate');
assert(~pump.holdsValue(pRate, 2, 2.01), 'a different rate is not');
assert(~pump.holdsValue(pRate, 2, NaN), 'NaN is never held');
assert(pump.holdsValue(pVol, 0.05, 0.05) && ~pump.holdsValue(pVol, 0.05, 0.06), 'Volume by its four digits');
pDia = pump.find_parameter('Diameter', includeInvisible = true);
assert(~pump.holdsValue(pDia, 21.59, 21.59), 'Diameter is always written');
assert(~pump.holdsValue(pump.find_parameter('Direction', includeInvisible = true), 'Infuse', 'Infuse'), 'so is Direction');

pump.SimRateUnits = 'UM';             % the keypad put the pump in uL/min
pump.SettingsCacheInterval = 0;
[~] = pRate.Value;                    % the pump reports 2 UM
assert(~pump.holdsValue(pRate, 2, 2), 'the same number in other units is another rate');
fprintf('PASS: 6 holdsValue: four digits, and for a rate the units too\n');

% --- 7. in a dispatch --------------------------------------------------------
pump.SkipUnchangedWrites = true;
[~] = pRate.Value;                    % read back: 2 UM, the interface writes MH
pump.Log = {};
localAllowSkip(pump, true);
pRate.Value = 2;
localAllowSkip(pump, false);
assert(localCount(pump, 'RAT2.000MH') == 1, ...
    'a rate held in other units is written again, with units (log: %s)', strjoin(pump.Log, ' | '));
assert(strcmp(pump.SimRateUnits, 'MH'), 'and the pump is back in the interface''s units');

[~] = pRate.Value; [~] = pVol.Value;  % read back: 2 MH, 0.05
pump.Log = {};
localAllowSkip(pump, true);
pRate.Value = 2;
pVol.Value = 0.05;
localAllowSkip(pump, false);
assert(isempty(pump.Log), 'an unchanged Rate and Volume put nothing on the wire (log: %s)', strjoin(pump.Log, ' | '));
assert(pump.WritesSkipped == 2, 'both skips are counted');

[~] = pRate.Value;
pump.Log = {};
localAllowSkip(pump, true);
pRate.Value = 2.5;
localAllowSkip(pump, false);
assert(localCount(pump, 'RAT2.500MH') == 1 && pump.SimRate == 2.5, 'a changed rate is written');

[~] = pRate.Value;
pump.Log = {};
pRate.Value = 2.5;                    % no dispatch: an operator's commit
assert(localCount(pump, 'RAT2.500MH') == 1, 'outside a dispatch the write always goes out');
fprintf('PASS: 7 in a dispatch an unchanged Rate/Volume is not sent; a changed one is\n');

% --- 8. both on: a trial costs the pump nothing for Rate and Volume ----------
pump.SettingsCacheInterval = 30;
[~] = pRate.Value; [~] = pVol.Value;  % the first trial's sweep seeds the cache
pump.Log = {};
for trial = 1:5
    pump.invalidateDeviceValues();    % the trial loop, before its trial-end read
    r = pRate.Value; v = pVol.Value;  % the sweep
    localAllowSkip(pump, true);
    pRate.Value = r;                  % the dispatch rewrites what the table holds
    pVol.Value = v;
    localAllowSkip(pump, false);
end
assert(isempty(pump.Log), 'five trials, nothing on the wire for Rate and Volume (log: %s)', strjoin(pump.Log, ' | '));
assert(pump.SimRate == 2.5 && pump.SimVolume == 0.05, 'and the pump holds what the table says');
fprintf('PASS: 8 both on: sweep and dispatch put nothing on the wire for Rate and Volume\n');

fprintf('smoke_test_ne1000_settings_cache: ALL PASS\n');
end


function n = localCount(pump, cmd)
% Command lines the pump saw that are exactly CMD (after the address prefix).
n = 0;
for k = 1:numel(pump.Log)
    line = regexprep(strtrim(pump.Log{k}), '^\d+', '');
    if strcmp(line, cmd), n = n + 1; end
end
end

function localAllowSkip(dev, tf)
% Stand in for the dispatcher: what dispatchNextTrial(i, AllowSkip=true) sets.
dev.InDispatch = tf;
dev.DispatchMaySkip = tf && dev.SkipUnchangedWrites;
end

function localDelete(h)
try
    if isvalid(h), delete(h); end
catch
end
end
