function create_listeners(obj)
% create_listeners(obj)
% Attach PostSet listeners to all public SetObservable properties.
% Listener handles are stored in obj.els.

m = metaclass(obj);
p = m.PropertyList;
ind = [p.SetObservable] & string({p.SetAccess}) == "public";
p(~ind) = [];

for i = 1:length(p)
    e(i) = addlistener(obj,p(i).Name,'PostSet',@obj.onPropertyChanged);
end
obj.els = e;
