%% Custom GUI with EPsych GUI objects
%
% The basic idea is to create graphical containers - seperate figures,
% panels, or axes - in an arrangement that you find useful.  EPsych GUI
% objects can be created in these containers by using the object creation
% syntax below. Example objects include: 
%   gui.OnlinePlot  ... Plotting parameters running in the RPvds circuit
%   gui.PsychPlot   ... Basic psychophysics plot for hit rate, false-alarm
%                       rate, or d-prime
%   gui.History     ... Table displaying trial history
%   gui.Triggers    ... Allows user to update logical components running on
%                       the RPvds circuit
% 
% You can create a GUI using the GUIDE utility (see: help guide) or
% manually as in the example below.
%
% * Note that a protocol needs to be running in order for this to work

 % Need to pass RUNTIME to GUI objects
global AX % Need to pass AX to the GUI objects that access the TDT hardware directly using ActiveX

BoxID = 1; % define which Subject is being used (if running multiple subjects simultaneously)


% Create a new figure for the GUI objects.
f = figure('Name','Basic EPsych GUI','NumberTitle','off','Position',[400 100 800 450]);


% Create containers for GUI objects:

% Plotting objects requires an axes container - an axes object will be
% created if another type of container (figure or uipanel) is specified.
axPsychPlot  = axes(f,'Units','Normalized','Position',[0.1 0.1 0.3 0.5]);
axOnlinePlot = axes(f,'Units','Normalized','Position',[0.1 0.78 0.6 0.2]);

% Information objects require uipanel objects.
pHistory  = uipanel(f,'Units','Normalized','Position',[0.5 0.05 0.45 0.55]);
pTriggers = uipanel(f,'Units','Normalized','Position',[0.75 0.78 0.2 0.2]);


% Create the psychophysics object
D = psychophysics.Detection;

% Create the OnlinePlot object and assign it to the axOnlinePlot container
watchedParameters = {'!TrialDelivery','~InTrial_TTL','~DelayPeriod', ...
    '~RespWindow','~Spout_TTL','~ShockOn','~GO_Stim','~NOGO_Stim'};
gui.OnlinePlot(RUNTIME,AX,watchedParameters,axOnlinePlot,BoxID);

% Create the PsychPlot object and assign it to the axPsychPlot container
gui.PsychPlot(D,RUNTIME.HELPER,axPsychPlot);

% Create the trial History object and assign it to the pHistory container
gui.History(D,RUNTIME.HELPER,pHistory);

% Create the Triggers table
gui.Triggers(RUNTIME,AX,pTriggers,BoxID);

% launch the other GUIs custom to your setup
% MR_BehaviorGUI_Startup;

