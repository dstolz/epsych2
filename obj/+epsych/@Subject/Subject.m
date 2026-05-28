classdef (Abstract) Subject < handle
    % epsych.Subject
    % S = epsych.DefaultSubject(...)
    % Abstract base class for experiment subject definitions.
    %
    % Required abstract properties (must be implemented by subclasses):
    %   BoxID   - Apparatus/box index (positive integer)
    %   Name    - Subject identifier string
    %   Sex     - Subject sex descriptor
    %   Species - Species designation
    %
    % Optional concrete properties (with defaults):
    %   Weight  - Body weight (default: NaN)
    %   Notes   - Freeform notes (default: '')
    %
    % Methods:
    %   toStruct()    - Convert to plain struct for serialization/backward compatibility
    %   isValid()     - Returns true if all required fields are populated
    %   validate()    - Throws an error if the subject is not valid
    %
    % Static methods:
    %   fromStruct(S) - Construct an epsych.DefaultSubject from a plain struct S
    %
    % Usage:
    %   % Create via concrete subclass or fromStruct helper:
    %   S = epsych.Subject.fromStruct(struct('BoxID',1,'Name','M001','Sex','M','Species','Mouse'))
    %   S.isValid()       % true
    %   raw = S.toStruct()
    %
    % See also: epsych.DefaultSubject, epsych.RunExpt

    % ---------------------------------------------------------------------------
    % Abstract properties — concrete subclasses must define all four
    % ---------------------------------------------------------------------------
    properties (Abstract)
        BoxID    % Apparatus/box index (positive integer)
        Name     % Subject identifier string
        Sex      % Subject sex descriptor
        Species  % Species designation
    end

    % ---------------------------------------------------------------------------
    % Optional properties with sensible defaults
    % ---------------------------------------------------------------------------
    properties
        Weight  = NaN  % Body weight in grams (optional)
        Notes   = ''   % Freeform notes (optional)
    end

    % ---------------------------------------------------------------------------
    % Concrete methods available to all subclasses
    % ---------------------------------------------------------------------------
    methods

        function S = toStruct(self)
            % S = toStruct(self)
            % Convert this Subject to a plain scalar struct.
            % Returns a struct with fields BoxID, Name, Sex, Species, Weight, Notes.
            S.BoxID   = self.BoxID;
            S.Name    = self.Name;
            S.Sex     = self.Sex;
            S.Species = self.Species;
            S.Weight  = self.Weight;
            S.Notes   = self.Notes;
        end

        function tf = isValid(self)
            % tf = isValid(self)
            % Returns true when all required fields are non-empty.
            % Returns false if BoxID is non-positive or Name/Sex/Species are empty.
            tf = ~isempty(self.BoxID) && isnumeric(self.BoxID) && self.BoxID >= 1 ...
                && ~isempty(self.Name) && strlength(string(self.Name)) > 0 ...
                && ~isempty(self.Sex)  && strlength(string(self.Sex))  > 0 ...
                && ~isempty(self.Species) && strlength(string(self.Species)) > 0;
        end

        function validate(self)
            % validate(self)
            % Throws epsych:Subject:InvalidSubject if the subject is not valid.
            if ~self.isValid()
                missing = {};
                if isempty(self.BoxID) || ~isnumeric(self.BoxID) || self.BoxID < 1
                    missing{end+1} = 'BoxID';
                end
                if isempty(self.Name) || strlength(string(self.Name)) == 0
                    missing{end+1} = 'Name';
                end
                if isempty(self.Sex) || strlength(string(self.Sex)) == 0
                    missing{end+1} = 'Sex';
                end
                if isempty(self.Species) || strlength(string(self.Species)) == 0
                    missing{end+1} = 'Species';
                end
                error('epsych:Subject:InvalidSubject', ...
                    'Subject is missing required field(s): %s', strjoin(missing, ', '));
            end
        end

    end

    % ---------------------------------------------------------------------------
    % Static helpers
    % ---------------------------------------------------------------------------
    methods (Static)

        function obj = fromStruct(S)
            % obj = epsych.Subject.fromStruct(S)
            % Construct an epsych.DefaultSubject from a plain struct S.
            % Parameters:
            %   S - struct with at least fields Name, BoxID, Sex, Species
            % Returns:
            %   obj - epsych.DefaultSubject instance populated from S
            obj = epsych.DefaultSubject(S);
        end

    end

end
