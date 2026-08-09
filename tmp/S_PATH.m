clc
fprintf(2,'MASTER\n')
restoredefaultpath
addpath c:\src\epsych2
epsych_startup;
global GVerbosity
GVerbosity = 4;

epsych.RunExpt('D:\epsych_files\Configs\TEST_NEWPROT.ecfg')