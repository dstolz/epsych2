%%


%%
m = peripherals.NanoMotorControl(Port="COM6");%, AutoDetect=true); % "AutoDetect = true" will try other ports if 'Port="COM#"' fails
m.connect();

%%
m.Verbosity = "INFO";
m.Verbosity = "DETAILED";

%%
m.setRPM(60);           % motor RPM (continuous)
p = m.positionDeg();    % output-shaft degrees (open-loop)

m.moveDeg(1000, 120);     % +90 output degrees (CW) at 120 motor RPM

pause(1)

p = m.positionDeg();    % output-shaft degrees (open-loop)

pause(1)

p = m.positionDeg();    % output-shaft degrees (open-loop)
%%
m.moveDeg(-90, 30);     % +90 output degrees (CCW) at 30 motor RPM

%%
m.stop();




%%

p0 = m.positionDeg();    % output-shaft degrees (open-loop)
p1 = nan;

m.moveDeg(360, 120);     % +90 output degrees (CW) at 120 motor RPM

while p1 ~= p0


    p1 = m.positionDeg();
    % fprintf('Position = %.4f deg\n',p1)
    pause(0.01);
    p0 = m.positionDeg();
    pause(0.01);

end


%%
m.disconnect();
%%


m = peripherals.NanoMotorControlGUI(Port="COM6");

