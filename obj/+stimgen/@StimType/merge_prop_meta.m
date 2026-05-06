function m = merge_prop_meta(a, b)
% merge_prop_meta(a, b)
% Append all fields from struct b into struct a.
bf = fieldnames(b);
for i = 1:numel(bf)
    a.(bf{i}) = b.(bf{i});
end
m = a;
end
