function deletePlotGraphics_(obj)
% deletePlotGraphics_(obj)
% Delete plot graphics handles if they exist.
%
% Parameters:
%   obj — psychophysics.Staircase instance

if ~isempty(obj.h_line) && isvalid(obj.h_line), delete(obj.h_line); end
if ~isempty(obj.h_points) && isvalid(obj.h_points), delete(obj.h_points); end
if ~isempty(obj.h_thrreg) && isvalid(obj.h_thrreg), delete(obj.h_thrreg); end
if ~isempty(obj.h_thrline) && isvalid(obj.h_thrline), delete(obj.h_thrline); end
if ~isempty(obj.StepH) && isvalid(obj.StepH), delete(obj.StepH); end
if ~isempty(obj.ReversalUpH) && isvalid(obj.ReversalUpH), delete(obj.ReversalUpH); end
if ~isempty(obj.ReversalDownH) && isvalid(obj.ReversalDownH), delete(obj.ReversalDownH); end

obj.h_line = [];
obj.h_points = [];
obj.h_thrreg = [];
obj.h_thrline = [];
obj.StepH = [];
obj.ReversalUpH = [];
obj.ReversalDownH = [];
