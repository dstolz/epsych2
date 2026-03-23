%%
% T_MotorControl.m (Moved from helpers/ to obj/+peripherals/ in repo reorganization.)
%%
m = NanoMotorControl(Port="COM6");%, AutoDetect=true); % "AutoDetect = true" will try other ports if 'Port="COM#"' fails
m.connect();
% ...existing code...
