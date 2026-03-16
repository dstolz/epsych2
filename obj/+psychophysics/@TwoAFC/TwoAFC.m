classdef TwoAFC < psychophysics.psychophysics

    % obj = psychophysics.TwoAFC(Runtime, BoxID)
    % Psychophysics metrics for 2-alternative forced-choice paradigms.
    %
    % This subclass sets ResponseBits/Type for 2AFC-style performance.


    properties (Constant)
        Type = '2AFC';
        ResponseBits = epsych.BitMask([3 4 5 8]) % [Hit Miss Abort NoResponse]
    end
    

    methods        
        function obj = TwoAFC(Runtime,BoxID)
            narginchk(1,2);

            if nargin < 2 || isempty(BoxID), BoxID = 1; end

            obj = obj@psychophysics.psychophysics(Runtime,BoxID);
        end

        
        
    end

end