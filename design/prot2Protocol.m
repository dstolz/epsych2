function protocol_obj = prot2Protocol(old_prot_struct)
    % protocol_obj = prot2Protocol(old_prot_struct)
    %
    % Convert legacy .prot protocol struct to new epsych.Protocol object.
    %
    % This utility allows old protocols created with ep_ExperimentDesign
    % to be loaded and viewed in the new system. The resulting protocol
    % uses hw.Software as the backend interface, allowing offline inspection,
    % modification, and re-export.
    %
    % Parameters:
    %   old_prot_struct - Struct loaded from old .prot MAT file with fields:
    %       MODULES, OPTIONS, INFO, COMPILED (optional), meta (optional)
    %
    % Returns:
    %   protocol_obj - New epsych.Protocol instance populated from legacy data
    %
    % Example:
    %   load('old_protocol.prot', 'protocol');
    %   new_protocol = prot2Protocol(protocol);
    %   new_protocol.save('new_protocol.eprot');

    arguments
        old_prot_struct struct
    end

    % Create new protocol
    protocol_obj = epsych.Protocol(Info=old_prot_struct.INFO);

    % Copy options
    if isfield(old_prot_struct, 'OPTIONS')
        for fname = fieldnames(old_prot_struct.OPTIONS)'
            fname = char(fname);
            try
                protocol_obj.setOption(fname, old_prot_struct.OPTIONS.(fname));
            catch
                vprintf(1, 'Could not map option %s', fname);
            end
        end
    end

    % Convert MODULES to parameters on Software interface
    if isfield(old_prot_struct, 'MODULES')
        mods = old_prot_struct.MODULES;
        mod_names = fieldnames(mods);
        
        for m_idx = 1:length(mod_names)
            mod_name = mod_names{m_idx};
            mod_data = mods.(mod_name);
            
            % Each row in mod_data is: {name, direction, buddy, values, random_flag, wav_flag, calibration}
            if isfield(mod_data, 'data') && ~isempty(mod_data.data)
                data_table = mod_data.data;
                
                for row_idx = 1:size(data_table, 1)
                    param_name = data_table{row_idx, 1};
                    direction = data_table{row_idx, 2};
                    % buddy = data_table{row_idx, 3};
                    % values = data_table{row_idx, 4};
                    % random_flag = data_table{row_idx, 5};
                    % wav_flag = data_table{row_idx, 6};
                    % calibration = data_table{row_idx, 7};
                    
                    if isempty(param_name)
                        continue;
                    end
                    
                    % Try to parse values
                    try
                        val = str2num(data_table{row_idx, 4}); %#ok<ST2NM>
                        if isempty(val)
                            val = 1;
                        end
                    catch
                        val = 1;
                    end
                    
                    % Map direction to Access
                    access = 'Any';
                    if strcmp(direction, 'Read')
                        access = 'Read';
                    elseif strcmp(direction, 'Write')
                        access = 'Write';
                    elseif any(strcmp(direction, {'Any', 'Read / Write', 'Read/Write', 'Write/Read'}))
                        access = 'Any';
                    end
                    
                    % Add parameter to Software interface
                    try
                        protocol_obj.addParameter('Software', param_name, val, Access=access);
                    catch ME
                        vprintf(1, 'Could not add parameter "%s": %s', param_name, ME.message);
                    end
                end
            end
        end
    end

    vprintf(2, 'Converted legacy protocol to epsych.Protocol format');
end
