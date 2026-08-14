function r = normalize_(rec, template)
% r = epsych.SubjectRoster.normalize_(rec, template)
% Reshape a record array to exactly the template's field set and order.
%
% Fields a newer build added are filled from the template's defaults; fields an
% older build no longer knows are dropped. Doing this on every read is what
% lets two rigs on slightly different checkouts share a file without either one
% throwing on a field the other invented.
%
% Parameters:
%   rec      - struct array read from disk (may be empty or malformed).
%   template - scalar struct of defaults; its fieldnames define the shape.
%
% Returns:
%   r - (1,:) struct array with the template's fields, in the template's order.
%
% See also: epsych.SubjectRoster.reload
arguments
    rec
    template (1,1) struct
end

names = fieldnames(template);

if ~isstruct(rec) || isempty(rec)
    r = repmat(template, 1, 0);
    return
end

r = repmat(template, 1, numel(rec));
for i = 1:numel(rec)
    for k = 1:numel(names)
        f = names{k};
        if isfield(rec, f)
            r(i).(f) = rec(i).(f);
        end
    end
end
