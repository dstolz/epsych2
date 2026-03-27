classdef PhaseSelector < handle
% PhaseSelector(RUNTIME, PhasePath)
% GUI component for selecting and saving experimental phase parameter sets.
% Loads JSON files from a directory, provides dropdown for phase selection, and button for saving current parameters.
%
% Parameters:
%   RUNTIME   - Main runtime object with read/write parameter methods
%   PhasePath - (optional) Directory containing phase JSON files
%
% Example usage:
%   ps = gui.PhaseSelector(RUNTIME, 'C:\path\to\phase_files');
%   parentUI = uipanel(...); % create parent UI container
%   ps.addPhaseSelect(parentUI, [10 10 150 30]);
%
% See also: documentation/Architecture_Overview.md

    properties (SetObservable)
        PhasePath (1,1) string % Directory containing phase JSON files
    end

    properties (SetAccess = private)
        RUNTIME                 % Main runtime object
        Names (1,:) string      % List of phase file names
        Filenames (1,:) string {mustBeFile} % Full paths to phase files
        CurrentPhase (1,1) uint8 = 0 % Index of currently selected phase
        h_PhaseSelect           % Handle to dropdown UI control
        h_WritePhase            % Handle to write button UI control
    end



    methods
        function obj = PhaseSelector(RUNTIME, PhasePath)
            % PhaseSelector(RUNTIME, PhasePath)
            % Constructor for PhaseSelector class.
            % Loads phase files from PhasePath if provided.
            %
            % Parameters:
            %   RUNTIME   - Main runtime object
            %   PhasePath - (optional) Directory containing phase JSON files
            arguments
                RUNTIME
                PhasePath (1,1) string = ""
            end
            obj.RUNTIME = RUNTIME;
            obj.PhasePath = PhasePath;
        end


        function set.PhasePath(obj, newPath)
            % set.PhasePath(obj, newPath)
            % Set method for PhasePath property. Loads phase files from new path.
            %
            % Parameters:
            %   newPath - New directory path for phase JSON files
            obj.PhasePath = newPath;
            obj.loadPhaseFiles();
        end


        function loadPhaseFiles(obj)
            % loadPhaseFiles(obj)
            % Loads JSON files from PhasePath and updates Names and Filenames.
            % Prompts user to select directory if PhasePath is not set or invalid.
            %
            % Updates:
            %   obj.Names, obj.Filenames
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
            % writePhaseParameters(obj, src)
            % Save current hardware and software parameters to a new JSON file.
            % Prompts user for file location.
            %
            % Parameters:
            %   src - Source UI control (unused)
            %
            % See also: documentation/Architecture_Overview.md
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
            % readPhaseParameters(obj, src)
            % Callback for dropdown value change. Loads parameters from selected phase file.
            %
            % Parameters:
            %   src - Source dropdown UI control
            %
            % Updates:
            %   obj.CurrentPhase
            idx = find(obj.Names == string(src.Value), 1);
            if ~isempty(idx)
                obj.CurrentPhase = uint8(idx);
            end

            % Read parameters from file corresponding to selected phase
            filepath = obj.Filenames(idx);

            [~,fn] = fileparts(filepath);
            vprintf(0, 'Reading parameters from "%s" (%s)', fn, filepath)
            obj.RUNTIME.readParametersJSON(filepath);
        end




        function h = addWritePhase(obj, parent, position)
            % h = addWritePhase(obj, parent, position)
            % Adds a button UI control to parent for saving current phase parameters to file.
            %
            % Parameters:
            %   parent   - Handle to parent container (e.g., uifigure, uipanel)
            %   position - [left bottom width height] position vector
            %
            % Returns:
            %   h - Handle to created button UI control
            arguments
                obj
                parent {mustBeNonempty} = gcf
                position (1,4) double {mustBeFinite, mustBeNonnegative} = [10 10 150 30]
            end

            h = uibutton(parent, ...
                'Text', 'Write Phase', ...
                'Position', position, ...
                'ButtonPushedFcn', @(src,evt) obj.writePhaseParameters(src));

            obj.h_WritePhase = h;
        end



        function h = addPhaseSelect(obj, parent, position)
            % h = addPhaseSelect(obj, parent, position)
            % Adds a dropdown UI control to parent for selecting phase files.
            %
            % Parameters:
            %   parent   - Handle to parent container (e.g., uifigure, uipanel)
            %   position - [left bottom width height] position vector
            %
            % Returns:
            %   h - Handle to created dropdown UI control
            arguments
                obj
                parent {mustBeNonempty} = gcf
                position (1,4) double {mustBeFinite, mustBeNonnegative} = [10 10 150 30]
            end

            h = uidropdown(parent, ...
                'Items', cellstr(obj.Names), ...
                'Position', position, ...
                'ValueChangedFcn', @(src,evt)obj.readPhaseParameters(src));

            obj.h_PhaseSelect = h;
        end

        

    end

end