classdef FilenameValidator < handle
    properties 
        EditField           matlab.ui.control.EditField
        PreviousValue       string
        Parent              matlab.ui.container.Container
    end

    methods
        function obj = FilenameValidator(parent, defaultFilename)
            arguments
                parent matlab.ui.container.Container
                defaultFilename string
            end

            obj.Parent = parent;
            p = obj.Parent.Position;

            obj.EditField = uieditfield(obj.Parent, 'text', ...
                'Value', defaultFilename, ...
                'HorizontalAlignment', 'left', ...
                'ValueChangedFcn', @(src, event)obj.onValueChanged(), ...
                'Position', [5 10 p(3) - 40 22]);  % Leave padding on sides


            obj.PreviousValue = defaultFilename;
        end
    end

    methods (Access = private)
        function onValueChanged(obj)
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
