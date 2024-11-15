function t = TrigDATrial(DA,trig)
% TrigDATrial(DA,trig)
% t = TrigDATrial(DA,trig)
% 
% Use with EPsych experiments
% 
% Returns an approximate timestamp from the PC just after trigger.  Use
% timestamps from TDT hardware for higher accuracy.
% 
% See also, TrigRPTrial
% 
% Daniel.Stolzberg@gmail.com


e = DA.SetTargetVal(trig,1);
% t = hat;
t = datetime('now');
if ~e, throwerrormsg(trig); end
pause(0.001)
e = DA.SetTargetVal(trig,0); 

%If open developer controls don't work, try SYNAPSE controls
if ~e
    fprintf('Trying to trigger with synapse...')
    
    global SYN %#ok<TLEV>
    
   %Find the RZ6 amongst the gizmos
    gizmo_names = SYN.getGizmoNames();
    
    for i = 1:numel(gizmo_names)
        name = gizmo_names{i};
        modInfo = SYN.getGizmoInfo(name);
        switch modInfo.cat
            case {'Legacy'}%RZ6
                break
        end
        
    end
    
    RZ6 = gizmo_names{i};
    
    %Rename the trigger so it's compatible with the SYNAPSE API syntax
    trig = trig(strfind(trig,'.')+1:end);

    %Set and reset the trigger value here
    e = SYN.setParameterValue(RZ6,trig,1);
    t = datetime('now');
    pause(0.001)
    e = SYN.setParameterValue(RZ6,trig,0);
  
end

%If synapse controls also don't work, throw an error
if ~e
    throwerrormsg(trig);
end



function throwerrormsg(trig)
beep
errordlg(sprintf('UNABLE TO TRIGGER "%s"',trig),'RP TRIGGER ERROR','modal')
error('UNABLE TO TRIGGER "%s"',trig)
