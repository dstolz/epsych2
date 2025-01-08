classdef TDTRP < handle
%TDTRP  RPcoX wrapper
%   obj = TDTRP(CIRCUITPATH, DEVICETYPE, varargin) connects to Workbench server
%
%   obj.RP   RPcoX object
%
%   obj = TDTRP(CIRCUITPATH, DEVICETYPE, 'parameter', value,...)
%
%   'parameter', value pairs
%      'INTERFACE'  string, interface type 'USB' or 'GB' (default)
%      'NUMBER'     integer, device number as enumerated by zBusMon (default 1)
%      'FS'         float, sampling rate to run the circuit at (otherwise
%                   uses circuit default
%
%   Set mode:
%      obj.halt     stop the processing chain
%      obj.load     load the processing chain
%      obj.run      run the processing chain
%
%   Software trigger:
%      result = obj.trg(TRIGNUM), where TRIGNUM is the trigger index
%
%   Write to parameter tag:
%      result = obj.write(TAGNAME, VALUE), where TAGNAME and VALUE
%      are strings, write the value(s) to parameter tag
%
%      result   1 if successful, 0 otherwise
%
%      result = obj.write(TAGNAME,VALUE,'parameter',value,...)
%
%      'parameter', value pairs
%          'FORMAT'  string, destination format (array only)
%                    options are 'F32' (default) 'I32' 'I16' 'I8'
%          'OFFSET'  scalar, offset into buffer (array only).
%                    default is 0.
%
%   Read parameter tag:
%      value = obj.read(TAGNAME), where TAGNAME is a string, reads
%      the values from parameter tag
%
%      value   value(s) read from hardware tag
%
%      obj.read(TAGNAME,'parameter',value,...)
%
%      'parameter', value pairs
%          'SOURCE'  string, source format (array only)
%                    options are 'F32' (default) 'I32' 'I16' 'I8'
%          'DEST'    string, destination format (array only)
%                    options are 'F64' 'F32' (default) 'I32' 'I16' 'I8'
%          'SIZE'    scalar, number of words to read (array only).
%                    default is the entire buffer.
%          'OFFSET'  scalar, offset into buffer (array only).
%                    default is 0.
%          'NCHAN'   scalar, number of channels in buffer (array
%                    only). Used for de-interlacing data. Default is 1.
%
    properties
       RP;
       PARTAG     = [];
       FS         = 0;
       INTERFACE  = 'GB';
       DEVICETYPE = '';
       NUMBER     = 1;
       CYC        = -1;
    end
    
    methods
        function obj = setup(obj)
            % create map of tags and their sizes for all devices
            tag_num = double(obj.RP.GetNumOf('ParTag'));
            obj.PARTAG = cell(1, tag_num);
            for i = 1:tag_num
                obj.PARTAG{i}.tag_name = obj.RP.GetNameOf('Partag', i);
                obj.PARTAG{i}.tag_type = obj.RP.GetTagType(obj.PARTAG{i}.tag_name);
                obj.PARTAG{i}.tag_size = obj.RP.GetTagSize(obj.PARTAG{i}.tag_name);
            end
            obj.FS = obj.RP.GetSFreq;
            obj.CYC = obj.RP.GetCycUse;
        end
    end
    
    methods
        
        function obj = TDTRP(CIRCUITPATH, DEVICETYPE, varargin)
            if nargin > 3
                % parse varargin
                for i = 1:2:length(varargin)
                    eval(['obj.' upper(varargin{i}) '=varargin{i+1};']);
                end
            end
            
            %First instantiate a variable for the ActiveX wrapper interface
            obj.RP = actxserver('RPco.X');
            
            obj.DEVICETYPE = upper(DEVICETYPE);
            ALLOWED_DEVICES = {'RP2', 'RA16', 'RL2', 'RV8', 'RM1', 'RM2', ...
                'RX5', 'RX6', 'RX7', 'RX8', 'RZ2', 'RZ5', 'RZ6'};

            % check if device is in our list
            if ~ismember(obj.DEVICETYPE, ALLOWED_DEVICES)
                error([obj.DEVICETYPE ' is not a valid device type, valid devices are: ' strjoin(ALLOWED_DEVICES, ', ')]);
            end

            % check if file exists
            if ~(exist(CIRCUITPATH, 'file'))
                error([CIRCUITPATH ' doesn''t exist'])
            end

            % connect to device
            eval(['obj.RP.Connect' obj.DEVICETYPE '(''' obj.INTERFACE ''', ' num2str(obj.NUMBER) ');']);

            % stop any processing chains running on device
            obj.RP.Halt; 

            % clears all the buffers and circuits on the device
            obj.RP.ClearCOF;

            % load circuit
            disp(['Loading ' CIRCUITPATH]);
            if obj.FS > 0
                obj.RP.LoadCOFsf(CIRCUITPATH, obj.FS);
            else
                obj.RP.LoadCOF(CIRCUITPATH);
            end

            % start circuit
            obj.RP.Run;
            obj.status();
            obj.setup();
        end

        function obj = halt(obj)
            obj.RP.Halt;
        end
        
        function obj = load(obj, CIRCUITPATH)
            if obj.FS > 0
                obj.RP.LoadCOFsf(CIRCUITPATH, obj.FS);
            else
                obj.RP.LoadCOF(CIRCUITPATH);
            end
        end
        
        function obj = run(obj)
            obj.RP.Run();
        end
        
        function obj = trg(obj, TRIGNUM)
            obj.RP.SoftTrg(TRIGNUM);
        end

        function result = status(obj)
            % check the status for errors
            status = double(obj.RP.GetStatus);
            if bitget(status,1)==0;
                error('Error connecting to %s', obj.DEVICETYPE);
            elseif bitget(status,2)==0;
                error('Error loading circuit'); 
            elseif bitget(status,3)==0
                error('Error running circuit'); 
            else
                disp('Circuit loaded and running');
                result = 1;
            end
        end
        
        function sz = check_tag(obj, tagname)
            sz = 0;
            tagind = -1;
            if ~isempty(obj.PARTAG)
                tags = obj.PARTAG;
                tagind = -1;
                for j = 1:numel(tags)
                    if strcmp(tags{j}.tag_name, tagname)
                        tagind = j;
                        sz = tags{j}.tag_size;
                        break;
                    end
                end
            end
            if tagind == -1
                warning('Tag name %s not found', tagname);
                sz = 0;
            end
        end
        
        function result = write(obj, tagname, value, varargin)

            % defaults
            FORMAT = 'F32';
            OFFSET = 0;

            % parse varargin
            for i = 1:2:length(varargin)
                eval([upper(varargin{i}) '=varargin{i+1};']);
            end

            % check if tagname is in PARTAG property and get array size
            sz = obj.check_tag(tagname);
            if sz == 0
                result = 0;
                return
            end
            
            %if array is not a row, make it a row
            if size(value, 1) > size(value, 2)
                value = value';
            end
            if ~(size(value, 2) >= size(value, 1))
                warning('array must be single row or column')
                result = 0;
                return
            end
            
            if numel(value) > sz
                warning('Number of elements (%d) larger than tag %s can hold (%d)', numel(value), tagname, sz);
                result = 0;
                return
            end

            if isscalar(value)
                result = obj.RP.SetTagVal(tagname, value);
            else
                if OFFSET > sz
                    warning('Offset (%d) larger than %s tag size (%d)', OFFSET, tagname, sz);
                    result = 0;
                    return
                end
                result = obj.RP.WriteTagVEX(tagname, OFFSET, FORMAT, value);
            end
        end
        
        function value = read(obj, tagname, varargin)            
            % defaults
            SOURCE = 'F32';
            DEST = 'F32';
            OFFSET = 0;
            NCHAN = 1;
            SIZE = -1;

            % parse varargin
            for i = 1:2:length(varargin)
                eval([upper(varargin{i}) '=varargin{i+1};']);
            end
            
            % check if tagname is in PARTAG property and get array size
            sz = obj.check_tag(tagname);
            if sz == 0
                value = [];
                return
            end
            
            if OFFSET > sz
                warning('Offset (%d) > %s tag size (%d)', OFFSET, tagname, sz);
                value = [];
                return
            end
            
            if SIZE == -1
                SIZE = sz - OFFSET;
            end
            
            % do the actual reading
            value = obj.RP.ReadTagVEX(tagname, OFFSET, SIZE, SOURCE, DEST, NCHAN);
        end
        
        function delete(obj)
            obj.RP.Halt();
        end
    end
end