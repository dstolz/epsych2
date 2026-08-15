function [P, pump] = create_pump_protocol(filename, options)
% [P, pump] = create_pump_protocol(filename, Name=Value, ...)
% Build the smallest protocol that exercises gui.SyringePump end to end: an
% hw.NE1000 reward pump whose dispensed Volume steps through three levels
% across trials, plus the software parameters and core triggers every
% protocol needs.
%
% The pump must be CONNECTED for this to work: hw.NE1000 builds its
% parameter table during the connect handshake, so an offline interface has
% no Volume or Rate to compile into the trial table. With no Port given the
% protocol is built against tmp/NE1000_Mock, the in-process simulated pump
% the hw.NE1000 smoke tests use, so this runs anywhere.
%
% Parameters:
%   filename - Output .eprot path. Default: PumpExample.eprot in this folder.
%
% Name=Value:
%   Port     - Serial port of a real pump. Default '' (simulated pump).
%   Diameter - Syringe inside diameter, mm. Default 21.59 (a 30 mL syringe).
%              At or above 14 mm the pump reports volumes in mL, below it in
%              uL — which is why the Volume levels below are in mL.
%   Rate     - Pumping rate in uL/min. Default 1000 (20 uL in 1.2 s).
%   Save     - Write the .eprot. Default true.
%
% Returns:
%   P    - The compiled epsych.Protocol.
%   pump - The connected hw.NE1000 (or NE1000_Mock) it was built against.
%
% Try it:
%   create_pump_protocol                     % simulated pump
%   create_pump_protocol(Port = 'COM4')      % a real NE-1000
%
% See also run_pump_session, PumpBehaviorGUI, gui.SyringePump, hw.NE1000

arguments
    filename (1,:) char = ''
    options.Port (1,:) char = ''
    options.Diameter (1,1) double {mustBeInRange(options.Diameter, 0.1, 50)} = 21.59
    options.Rate (1,1) double {mustBePositive} = 1000
    options.Save (1,1) logical = true
end

here = fileparts(mfilename('fullpath'));
addpath(here); % PumpBehaviorGUI must be resolvable when a session launches it

if isempty(filename)
    filename = fullfile(here, 'PumpExample.eprot');
end

% --- The pump ------------------------------------------------------------
% RateUnits is fixed at uL/min here rather than left at the interface default
% of mL/hr, because gui.SyringePump puts the interface into the units it
% displays when it attaches. Authoring the protocol in those same units keeps
% the Rate the trial table re-asserts every trial and the Rate the operator
% sees in the panel the same number -- which is why PumpBehaviorGUI states
% RateUnits='UM' on the panel too, rather than taking its mL/min default.
if isempty(options.Port)
    assert(exist('NE1000_Mock', 'class') == 8, ...
        ['No Port given and tmp/NE1000_Mock is not on the path. ' ...
         'Run epsych_startup, or pass Port= for a real pump.'])
    pump = NE1000_Mock(SyringeDiameter = options.Diameter, RateUnits = 'UM');
    vprintf(0, 'Building the protocol against a SIMULATED pump (NE1000_Mock).')
else
    pump = hw.NE1000(options.Port, SyringeDiameter = options.Diameter, RateUnits = 'UM');
end

P = epsych.Protocol(Name = 'PumpExample', ...
    Info = 'Minimal reward-pump protocol for testing gui.SyringePump');
P.addInterface(pump);

% --- Per-trial reward size -----------------------------------------------
% Volume and Rate arrive already declared by the pump's connect handshake
% (Visible, Access='Any'), so they are trial-table columns and are recorded
% in DATA. Giving Volume three design-time levels is all it takes for the
% runtime to write a different reward size to the pump on every trial.
pVol = pump.find_parameter('Volume');
pVol.Values = num2cell([0.02 0.04 0.06]);   % mL — 20, 40, 60 uL
pVol.Description = "Reward volume dispensed by one Start pulse, in mL " + ...
    "(the pump reports volumes in mL at this syringe diameter).";

% hw.NE1000 labels its volume parameters from RateUnits, but the pump picks
% the units it actually reports volumes in from the SYRINGE DIAMETER — uL
% below 14 mm, mL at or above. With Rate in uL/min and a 21.59 mm syringe
% those disagree, so the labels are corrected here; otherwise every display
% fed by these parameters (gui.NextTrial, gui.Parameter_Monitor, the trial
% table) reads "0.04 uL" for a 40 uL reward.
volumeUnit = 'mL';
if options.Diameter < 14, volumeUnit = 'uL'; end
for p = pump.find_parameter({'Volume','VolumeInfused','VolumeWithdrawn'})
    p.Unit = volumeUnit;
end

pRate = pump.find_parameter('Rate');
pRate.Values = {options.Rate};
pRate.Value = options.Rate;

% --- Software parameters -------------------------------------------------
sw = P.SoftwareModule;

% isRandom redraws the value uniformly in [Min, Max] on every dispatch.
p = sw.add_parameter('ITI', 3, Unit = 's', ...
    Description = "Delay between rewards, redrawn each trial");
p.Min = 2;
p.Max = 4;
p.isRandom = true;

% Every protocol needs the three core triggers; the runtime refuses to start
% without them (epsych.Runtime.resolveCoreParameters).
sw.add_parameter('x_NewTrial_1',      0, isTrigger = true);
sw.add_parameter('x_ResetTrig_1',     0, isTrigger = true);
sw.add_parameter('x_TrialComplete_1', 0, isTrigger = true);

% --- Validate, compile, save ---------------------------------------------
issues = P.validate();
for k = 1:numel(issues)
    vprintf(0, 1, 'Protocol issue (%s): %s', issues(k).field, issues(k).message)
end
assert(~any([issues.severity] == 2), 'Protocol has validation errors — not saving.')

P.compile();
assert(P.COMPILED.ntrials > 0, 'Compile produced no trials.')
vprintf(0, 'Compiled %d conditions over parameters: %s', ...
    P.COMPILED.ntrials, strjoin(P.COMPILED.writeparams, ', '))

if options.Save
    % The saved file reloads with an OFFLINE hw.NE1000 carrying this
    % parameter table; its Port is whatever was used here ('MOCK' for the
    % simulated pump), so correct it on the rig before running from RunExpt.
    P.save(filename);
end

if nargout == 0, clear P pump; end
