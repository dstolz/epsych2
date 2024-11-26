function setup_interface(obj)
% setup_interface(obj)
%
% defines obj.HW
%
% where obj.ModuleType is a valid module type: 'RZ5','RX6','RP2', etc..
%   obj.ModuleID is the module id.  default is 1.
%   obj.ConnectionType is a connection type:  'GB' or 'USB'
%   obj.RPfilename is the full path to an RPvds file.
%
% returns hw which is the handle to the RPco.x control.  Also returns
% status which is a bitmask of the module status.  Use with bitget function
%   Bit# 0 = Connected
%   Bit# 1 = Circuit loaded
%   Bit# 2 = Circuit running
%   Bit# 3 = RA16BA Battery
% (see page 43 of ActiveX reference manual for more status values).
%
% Optionally specify the sampling frequency (obj.SamplingRate).  See "LoadCOFsf" in the
% TDT ActiveX manual for more info.
%   obj.SamplingRate = 0  for 6 kHz
%   obj.SamplingRate = 1  for 12 kHz
%   obj.SamplingRate = 2  for 25 kHz
%   obj.SamplingRate = 3  for 50 kHz
%   obj.SamplingRate = 4  for 100 kHz
%   obj.SamplingRate = 5  for 200 kHz
%   obj.SamplingRate = 6  for 400 kHz
%   obj.SamplingRate > 50 for arbitrary sampling rates
%
% See also TDT_SetupDA, TDT_SetupTT, bitget
%
% DJS (c) 2010
% DJS 2023: updated for use with TDT_RPcox object


if isempty(obj.Module.), obj.ModuleID = 1; end

if ~exist(obj.RPfilename,'file')
    beep
    errordlg(sprintf('File does not exist: "%s"',obj.RPfilename),'File Does Not Exist', ...
        'modal');
    return
end

h = findobj('Name','RPfig');
if isempty(h)
    h = figure('Visible','off','Name','RPfig');
end

hw = actxcontrol('RPco.x','parent',h);
obj.HW = hw;

if obj.HWstatus == "running"
    fprintf('RPco.X already connected, loaded, and running.\n')
    return
end

if ischar(obj.ModuleID), obj.ModuleID = str2double(obj.ModuleID); end

if ~eval(sprintf('RP.Connect%s(''%s'',%d)',obj.ModuleType,obj.ConnectionType,obj.ModuleID))
    beep
    errordlg(sprintf(['Unable to connect to %s_%d module via %s connection!\n\n', ...
        'Ensure all modules are powered on and connections are secured\n\n', ...
        'Ensure the module is recognized in the zBusMon program.'], ...
        obj.ModuleType,obj.ModuleID,obj.ConnectionType),'Connection Error','modal');
    CloseUp(hw,h);
    return
    
else
    fprintf('%s_%d connected ... ',obj.ModuleType,obj.ModuleID)
    hw.ClearCOF;
    
    if nargin == 5
        e = hw.LoadCOFsf(obj.RPfilename,obj.SamplingRate);
    else
        e = hw.LoadCOF(obj.RPfilename);
    end
    
    if e  
        fprintf('loaded ...')
        if ~hw.Run
            beep
            errordlg(sprintf(['Unable to run %s module!\n\n', ...
                'Ensure all modules are powered on and connections are secured'], ...
                obj.ModuleType),'Run Error','modal');
            Cobj.close_interface;
            return
        else
            fprintf('running\n')
        end
        
    else
        beep
        errordlg(sprintf(['Unable to load RPvds file to %s module!\n\n', ...
            'The RPvds file exists, but can not be loaded for some reason'], ...
            obj.ModuleType),'Loading Error','modal');
        obj.close_interface;
        return
    end


end





