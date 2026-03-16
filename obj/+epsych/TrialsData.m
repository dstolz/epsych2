classdef (ConstructOnLoad) TrialsData < event.EventData
   % ev = epsych.TrialsData(trials)
   % Event data wrapper for per-trial runtime updates.
   %
   % Properties:
   %   Data    - Trial data structure (protocol-specific).
   %   Subject - Subject identifier from the incoming trials struct.
   %   BoxID   - Box identifier from the incoming trials struct.
   properties
      Data
      Subject
      BoxID
   end
   
   methods
      function data = TrialsData(trials)
         data.Data    = trials;
         data.Subject = trials.Subject;
         data.BoxID   = trials.BoxID;
      end
   end
end