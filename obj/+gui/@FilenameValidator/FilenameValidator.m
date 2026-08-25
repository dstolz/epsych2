classdef FilenameValidator < handle
    % obj = gui.FilenameValidator(RUNTIME, parent, defaultFilename)
    % Edit-field helper that validates and updates the runtime data filename.
    %
    % This widget enforces a ".mat" extension, disallows invalid characters,
    % and warns when the requested file already exists.
    %
    % Methods:
    %   (private) onValueChanged - Validate and commit the new filename.
    properties 
        EditField           matlab.ui.control.EditField
        PreviousValue       string
        Parent              matlab.ui.container.Container
    end

    properties (SetAccess = private)
        RUNTIME              % Reference to the main runtime object
    end

    methods (Static)
        function s = getComponentSpec()
            % s = gui.FilenameValidator.getComponentSpec()
            % See gui.ComponentSpec.
            s = gui.ComponentSpec();
            s.type        = 'FilenameField';
            s.label       = 'Filename Field';
            s.category    = 'Add-ons';
            s.description = 'Edit field that validates the session data filename';
            s.shape       = ["runtime","parent","arg:defaultFilename"];
            s.options     = gui.ComponentSpecOption('name','defaultFilename','inputType','text');
        end
    end

    methods
        function obj = FilenameValidator(RUNTIME, parent, defaultFilename)
            arguments
                RUNTIME
                parent matlab.ui.container.Container
                defaultFilename string
            end

            obj.RUNTIME = RUNTIME;
            obj.Parent = parent;
            p = obj.Parent.Position;

            obj.EditField = uieditfield(obj.Parent, 'text', ...
                'Value', defaultFilename, ...
                'HorizontalAlignment', 'left', ...
                'ValueChangedFcn', @(src, event)obj.onValueChanged(), ...
                'Position', [5 10 p(3) - 40 22]);  % Leave padding on sides


            obj.PreviousValue = defaultFilename;

            % Preview (test) runs never save data; match the light-blue
            % "PREVIEW MODE" styling used elsewhere (e.g. RunExpt's figure
            % color) so the field can't be mistaken for a live save target.
            if RUNTIME.isTest
                obj.EditField.BackgroundColor = [0.78 0.87 1.00];
                obj.EditField.Tooltip = "Preview mode: no data file will be saved.";
            end
        end
    end

    methods (Access = private)
        function onValueChanged(obj)
            R = obj.RUNTIME;
            

            newValue = strtrim(obj.EditField.Value);

            % Validate extension
            if ~endsWith(newValue, '.mat', 'IgnoreCase', true)
                uialert(ancestor(obj.Parent,'figure'), ...
                    "Filename must end with '.mat'.", ...
                    'Invalid Filename', ...
                    'Icon', 'error');
                obj.revertValue();
                return;
            end

            % Validate filename
            [folder, name, ext] = fileparts(newValue);
            if isempty(name) || ~obj.isValidFilename([name, ext])
                uialert(ancestor(obj.Parent,'figure'), ...
                    "Filename contains invalid characters.", ...
                    'Invalid Filename', ...
                    'Icon', 'error');
                obj.revertValue();
                return;
            end

            % Check if file exists
            if isfile(newValue)
                uialert(ancestor(obj.Parent,'figure'), ...
                    "File already exists: " + newValue, ...
                    'File Exists', ...
                    'Icon', 'warning', ...
                    'Modal', true);
                obj.revertValue();
                return;
            end

            % Passed validation
            obj.PreviousValue = newValue;
            vprintf(1,'Data filename updated: "%s.mat"; location: "%s"',name,folder)

            R.TRIALS.DataFilename = newValue;
        end

        function revertValue(obj)
            % Revert to the previous valid value
            obj.EditField.Value = obj.PreviousValue;
        end

        function tf = isValidFilename(~, name)
            % Check for invalid characters (platform-independent)
            % Windows-invalid: <>:"/\|?*
            % MATLAB also disallows control characters

            invalidChars = '<>:"/\|?*&$%@=';
            tf = all(~ismember(name, invalidChars)) && ...
                all(name >= " " & name <= "~"); % printable ASCII
        end
    end

end
