
function t = TrigSYNTrial(SYN,module,trig)
% TrigSYNTrial(SYN,module,trig)
% t = TrigSYNTrial(SYN,module,trig)
% 
% Use with EPsych experiments
% 
% Returns an approximate timestamp from the PC just after trigger.  Use
% timestamps from TDT hardware for higher accuracy.
% 
% See also, TrigRPTrial
% 
% Daniel.Stolzberg@gmail.com


e = SYN.setParameterValue(module,trig,1);
% t = hat;
t = datetime('now');
if ~e, throwerrormsg(module,trig); end
pause(0.001)
e = SYN.setParameterValue(module,trig,0); 
if ~e, throwerrormsg(module,trig); end

function throwerrormsg(module,trig)
beep
errordlg(sprintf('UNABLE TO TRIGGER "%s" ON MODULE "%s"',trig,module),'RP TRIGGER ERROR','modal')
error('UNABLE TO TRIGGER "%s" ON MODULE "%s"',trig,module)
