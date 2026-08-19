clc
fprintf(2,'MASTER\n')
restoredefaultpath
addpath c:\src\epsych2
epsych_startup;
global GVerbosity
GVerbosity = 4;

% The .ecfg config path is gone; name a roster project instead, or open bare.
epsych.RunExpt