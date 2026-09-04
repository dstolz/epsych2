function smoke_test_nanomotor_protocol()
% smoke_test_nanomotor_protocol()
% Exercise peripherals.NanoMotorControl against canned firmware replies:
% the EN?/POSD?/STATUS?/MOVE?/GEAR? parsers, the ERR and BUSY policy, and the
% SERQUIET handshake connect() performs.
%
% The two regressions this pins down, both silent before 2026-09-01:
%   1. "POSD ?" -- what the Nano prints when a reply is built with snprintf
%      "%f" (the Arduino AVR core links avr-libc's integer-only vfprintf).
%      Every float in a reply is rendered with dtostrf for this reason.
%   2. "EN 1 ACTUAL 0" -- not a bare prefixed number, so enableQuery() used to
%      throw on every call.
%
% No hardware: NanoMotorControl_Mock replaces the transport only.
%
%   matlab -batch "run('tmp/smoke_test_nanomotor_protocol.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));
addpath(here);

nFail = 0;


% 1. EN? -- two fields, and the class reports both --------------------------
m = mockWith('EN?', "EN 1 ACTUAL 0");
[permitted, actual] = m.enableQuery();
nFail = nFail + check(permitted == true,  'EN? permitted is the first field');
nFail = nFail + check(actual == false,    'EN? ACTUAL is read, not mirrored from permitted');

m = mockWith('EN?', "EN 0 ACTUAL 1");
[permitted, actual] = m.enableQuery();
nFail = nFail + check(permitted == false && actual == true, 'EN? the two fields are independent');

m = mockWith('EN?', "EN 1");
[permitted, actual] = m.enableQuery();
nFail = nFail + check(permitted == true && actual == true, ...
    'EN? without ACTUAL (older firmware) falls back to the permission flag');

nFail = nFail + checkThrows(@() mockWith('EN?', "EN").enableQuery(), ...
    'NanoMotorControl:ParseError', 'EN? with no value is a parse error');


% 2. POSD? -- the float regression ------------------------------------------
m = mockWith('POSD?', "POSD -12.345600");
nFail = nFail + check(abs(m.positionDeg() - -12.3456) < 1e-9, 'POSD? parses a negative degree value');

m = mockWith('POSD?', "POSD 0.000000");
nFail = nFail + check(m.positionDeg() == 0, 'POSD? parses zero');

nFail = nFail + checkThrows(@() mockWith('POSD?', "POSD ?").positionDeg(), ...
    'NanoMotorControl:ParseError', 'POSD ? (snprintf %f on AVR) is a parse error, not a silent NaN');


% 3. STATUS? -- every numeric field arrives as a number ----------------------
statusLine = "STATUS EN=1 MODE=USB GEAR=54/95 OUTDIR=-1 ENDELAYMS=5 LIMRPM=240.000 " + ...
             "HWMAXRPM=281.250 USB_RPM=-60.000 TGT_SPS=-12800.000 MOVE=0 POS=-1234 POSD=-3.470526";
m = mockWith('STATUS?', statusLine);
S = m.status();
nFail = nFail + check(isnumeric(S.LIMRPM)   && abs(S.LIMRPM - 240) < 1e-9,      'STATUS LIMRPM is numeric');
nFail = nFail + check(isnumeric(S.HWMAXRPM) && abs(S.HWMAXRPM - 281.25) < 1e-9, 'STATUS HWMAXRPM is numeric');
nFail = nFail + check(isnumeric(S.USB_RPM)  && abs(S.USB_RPM + 60) < 1e-9,      'STATUS USB_RPM keeps its sign');
nFail = nFail + check(isnumeric(S.POSD)     && abs(S.POSD + 3.470526) < 1e-9,   'STATUS POSD is numeric');
nFail = nFail + check(S.POS == -1234,                                           'STATUS POS is numeric');
nFail = nFail + check(m.GearDriverTeeth == 54 && m.GearDrivenTeeth == 95 && m.OutputDirSign == -1, ...
    'STATUS syncs the local gear fields');

% The GUI reads LIMRPM to set its speed limit; "?" must not become a limit.
m = mockWith('STATUS?', replace(statusLine, "LIMRPM=240.000", "LIMRPM=?"));
S = m.status();
nFail = nFail + check(~isnumeric(S.LIMRPM) || isnan(double(S.LIMRPM)), ...
    'a "?" field never reads back as a number');


% 4. GEAR? and MOVE? --------------------------------------------------------
m = mockWith('GEAR?', "GEAR DRIVER=54 DRIVEN=95 OUTDIR=-1 OUTREV_PER_MOTORREV=0.568421");
G = m.gearQuery();
nFail = nFail + check(G.DRIVER == 54 && G.DRIVEN == 95 && G.OUTDIR == -1, 'GEAR? parses the teeth counts');
nFail = nFail + check(abs(m.OutputRevPerMotorRev - 54/95) < 1e-9, 'GEAR? updates OutputRevPerMotorRev');

m = mockWith('MOVE?', "MOVE 1 TGT=12800 REM=900 REMDEG=25.628906 RPM=120.000");
M = m.moveQuery();
nFail = nFail + check(M.Active == true && M.TGT == 12800 && M.REM == 900, 'MOVE? parses an active move');
nFail = nFail + check(isnumeric(M.REMDEG) && abs(M.REMDEG - 25.628906) < 1e-9, 'MOVE? REMDEG is numeric');

m = mockWith('MOVE?', "MOVE 0");
nFail = nFail + check(m.moveQuery().Active == false, 'MOVE 0 is an inactive move');


% 5. ERR and BUSY are distinguishable ---------------------------------------
nFail = nFail + checkThrows(@() mockWith('SPD', "ERR SPD requires numeric steps/s").setSpeedSteps(0), ...
    'NanoMotorControl:DeviceError', 'an ERR line raises DeviceError');

nFail = nFail + checkThrows(@() mockWith('POS?', "BUSY").positionSteps(), ...
    'NanoMotorControl:DeviceBusy', 'a BUSY line raises DeviceBusy, not a parse error');

m = mockWith('POS?', "BUSY");
m.RaiseOnErr = false;
try
    m.positionSteps();
catch ME
    nFail = nFail + check(strcmp(ME.identifier,'NanoMotorControl:ParseError'), ...
        'with RaiseOnErr off, BUSY falls through to the parser');
end
nFail = nFail + check(m.LastError == "BUSY", 'BUSY is recorded in LastError');


% 6. connect() turns SERQUIET off -------------------------------------------
% Mocked at the send() layer: connect() itself opens a port, so drive the
% handshake the way connect() does and check what goes out.
m = mockWith('SERQUIET', "OK");
m.setSerialQuiet(false);
nFail = nFail + check(m.Sent(end) == "SERQUIET 0", 'setSerialQuiet(false) sends SERQUIET 0');
m.setSerialQuiet(true);
nFail = nFail + check(m.Sent(end) == "SERQUIET 1", 'setSerialQuiet(true) sends SERQUIET 1');

m = mockWith('SERQUIET?', "SERQUIET 0");
nFail = nFail + check(m.serialQuietQuery() == false, 'SERQUIET? parses');

% Firmware that predates SERQUIET answers ERR; connect() must tolerate it.
m = NanoMotorControl_Mock(containers.Map());   % everything answers ERR
try
    m.setSerialQuiet(false);
    nFail = nFail + check(false, 'unknown SERQUIET raises');
catch ME
    nFail = nFail + check(strcmp(ME.identifier,'NanoMotorControl:DeviceError'), ...
        'firmware without SERQUIET answers ERR (connect() catches this)');
end


% 7. Direction is set explicitly, not inferred from a sign ------------------
m = mockWith('RPM', "OK");
m.setReply('DIR', "OK");
m.setRPM(-60);
nFail = nFail + check(any(m.Sent == "DIR CCW"), 'a negative RPM sends DIR CCW explicitly');
nFail = nFail + check(m.Sent(end) == "RPM 60", 'the RPM magnitude follows the direction');


% ---------------------------------------------------------------------------
if nFail == 0
    fprintf('\nsmoke_test_nanomotor_protocol: PASS\n');
else
    error('smoke_test_nanomotor_protocol: %d check(s) FAILED', nFail);
end
end


function m = mockWith(key, reply)
m = NanoMotorControl_Mock(containers.Map({char(key)}, {string(reply)}));
end

function n = check(tf, what)
n = double(~tf);
if tf
    fprintf('  ok   %s\n', what);
else
    fprintf(2, '  FAIL %s\n', what);
end
end

function n = checkThrows(fcn, id, what)
try
    fcn();
    n = check(false, what);
catch ME
    n = check(strcmp(ME.identifier, id), what + " (" + ME.identifier + ")");
end
end
