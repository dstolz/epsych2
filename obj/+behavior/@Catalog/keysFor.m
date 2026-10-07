function keys = keysFor(obj, options)
% keys = keysFor(obj, Subject = s, Project = p, Tag = t, Position = k)
% Keys of the sessions matching every filter given, in Sessions order.
%
% Parameters:
%   Subject  - Subject name(s); any matches. Default: every subject.
%   Project  - Project name(s); any matches. Default: every project.
%   Tag      - Tag(s); a session matches when it carries any of them.
%   Position - Only look at the tag in this position (1 = the first tag after
%              the timestamp). Default 0: any position.
%
% Names and tags compare as keys do: case is ignored on Windows.
%
% Returns:
%   keys - (:,1) string.
%
% See also: behavior.Catalog.session, behavior.Catalog.keyEquals

arguments
    obj
    options.Subject (1,:) string = strings(1,0)
    options.Project (1,:) string = strings(1,0)
    options.Tag (1,:) string = strings(1,0)
    options.Position (1,1) double {mustBeInteger, mustBeNonnegative} = 0
end

T = obj.Sessions;
keep = true(height(T), 1);

if ~isempty(options.Subject)
    keep = keep & localAny(T.Subject, options.Subject);
end
if ~isempty(options.Project)
    keep = keep & localAny(T.Project, options.Project);
end
if ~isempty(options.Tag)
    for i = find(keep)'
        tags = T.Tags{i};
        if options.Position > 0
            if numel(tags) < options.Position
                keep(i) = false;
                continue
            end
            tags = tags(options.Position);
        end
        keep(i) = any(localAny(reshape(tags, [], 1), options.Tag));
    end
end

keys = T.Key(keep);

end




function tf = localAny(values, wanted)
% Which of values equal any of wanted, under the key comparison rule.
tf = false(numel(values), 1);
for w = wanted
    tf = tf | behavior.Catalog.keyEquals(values, w);
end
end
