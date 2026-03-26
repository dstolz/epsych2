classdef PhaseSelector < handle

    properties (SetObservable)
        PhasePath (1,1) string
    end

    properties (SetAccess = private)
        RUNTIME

        Names (1,:) string
        Filenames (1,:) string {mustBeFile}

        CurrentPhase (1,1) uint8 = 0

        h_PhaseSelect 
        h_WritePhase
    end


    methods
        function obj = PhaseSelector(RUNTIME, PhasePath)
            arguments
                RUNTIME
                PhasePath (1,1) string = ""
            end

            

            obj.RUNTIME = RUNTIME;
            obj.PhasePath = PhasePath;

        end

        function set.PhasePath(obj, newPath)
            obj.PhasePath = newPath;
            obj.loadPhaseFiles();
        end

        function loadPhaseFiles(obj)
            % Load JSON files from the specified PhasePath and populate Names and Filenames properties.
            if obj.PhasePath == "" || ~isfolder(obj.PhasePath)
                [fn,pth] = uigetfile('*.json','Select Directory Containing Phase JSON Files','MultiSelect','off');
                if isequal(fn,0) || isequal(pth,0)
                    vprintf(3,'User canceled directory selection. No phase files loaded.')
                    return
                end
                obj.PhasePath = pth;
            end

            jsonFiles = dir(fullfile(obj.PhasePath, '*.json'));
            nFiles = numel(jsonFiles);

            if nFiles == 0
                vprintf(3, 'No JSON files found in PhasePath: "%s".', obj.PhasePath)
                return
            end

            obj.Names = string({jsonFiles.name});
            obj.Filenames = string(fullfile({jsonFiles.folder}, {jsonFiles.name}));

            vprintf(3, 'Loaded %d phase files from "%s".', nFiles, obj.PhasePath)
        end

        function writePhaseParameters(obj, src)
            % write all hardware and software parameters to a new file

            [fn,pth] = uiputfile('*.json','Save Current Parameters');
            if isequal(fn,0) || isequal(pth,0)
                vprintf(3,'User canceled save operation.')
                return
            end

            filepath = fullfile(pth, fn);

            [~,fn] = fileparts(filepath);
            vprintf(0, 'Writing current parameters to "%s" (%s)', fn, filepath)
            obj.RUNTIME.writeParametersJSON(filepath);
            
        end

        function readPhaseParameters(obj, src)
            % Callback for dropdown value change
            % Updates CurrentPhase based on selected value
            idx = find(obj.Names == string(src.Value), 1);
            if ~isempty(idx)
                obj.CurrentPhase = uint8(idx);
            end

            % read parameters from file corresponding to selected phase
            filepath = obj.Filenames(idx);

            [~,fn] = fileparts(filepath);
            vprintf(0, 'Reading parameters from "%s" (%s)', fn, filepath)
            obj.RUNTIME.readParametersJSON(filepath);
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
                'ValueChangedFcn', @(src,evt)obj.readPhaseParameters(src));

            obj.h_PhaseSelect = h;
        end

        

    end

end