classdef PhaseSelector < handle

    properties
        Names (1,:) string
        Filenames (1,:) string {mustBeFile}
    end

    properties (SetAccess = private)
        RUNTIME

        CurrentPhase (1,1) uint8 = 0

        h_PhaseSelect 
        h_WritePhase
    end


    methods
        function obj = PhaseSelector(RUNTIME, options)
            arguments
                RUNTIME

                options.Names (1,:) string
                options.Filenames (1,:) string {mustBeFile}
            end

            if numel(options.Names) ~= numel(options.Filenames)
                error('Names and Filenames must have the same number of elements.')
            end

            obj.RUNTIME = RUNTIME;
            obj.Names = options.Names;
            obj.Filenames = options.Filenames;
            
        end

        function h = addWritePhase(obj, parent, position)
            % h = addWritePhase(obj, parent, position)
            % Adds a button UI control to the specified parent container for writing the current phase to file.
            % Parameters:
            %   parent   - Handle to the parent container (e.g., uifigure, uipanel)
            %   position - [left bottom width height] position vector
            % Returns:
            %   h - Handle to the created button UI control

            arguments
                obj
                parent {mustBeNonempty}
                position (1,4) double {mustBeFinite, mustBeNonnegative}
            end

            h = uibutton(parent, ...
                'Text', 'Write Phase', ...
                'Position', position, ...
                'ButtonPushedFcn', @(src,evt) obj.writePhaseParameters(src));

            obj.h_WritePhase = h;
        end

        function writePhaseParameters(obj, src)
            % write all hardware and software parameters to a new file

            [fn,pth] = uiputfile('*.json','Save Current Parameters');
            if isequal(fn,0) || isequal(pth,0)
                vprintf(3,'User canceled save operation.')
                return
            end

            filepath = fullfile(pth, fn);


            
        end


        function h = addPhaseSelect(obj, parent, position)
            % hDropdown = addPhaseSelect(obj, parent, position)
            % Adds a dropdown UI control to the specified parent container for selecting Names.
            % Parameters:
            %   parent   - Handle to the parent container (e.g., uifigure, uipanel)
            %   position - [left bottom width height] position vector
            % Returns:
            %   hDropdown - Handle to the created dropdown UI control

            arguments
                obj
                parent {mustBeNonempty}
                position (1,4) double {mustBeFinite, mustBeNonnegative}
            end

            h = uidropdown(parent, ...
                'Items', cellstr(obj.Names), ...
                'Position', position, ...
                'ValueChangedFcn', @(src,evt)obj.onDropdownChanged(src));

            obj.h_PhaseSelect = h;
        end

        function onDropdownChanged(obj, src)
            % Callback for dropdown value change
            % Updates CurrentPhase based on selected value
            idx = find(obj.Names == string(src.Value), 1);
            if ~isempty(idx)
                obj.CurrentPhase = uint8(idx);
            end
        end

        

    end

end