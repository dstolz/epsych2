function c = list
% c = stimgen.StimType.list
% Enumerate available concrete stimgen stimulus class names.
r = which('stimgen.StimType');
pth = fileparts(fileparts(r)); % up from @StimType to +stimgen
d = dir(fullfile(pth,'*.m'));
f = {d.name};
f(ismember(f,{'StimType.m','StimPlay.m','donotsavedatafcn.m','multiTone.m'})) = [];
f(contains(f,'Calib')) = [];
c = cellfun(@(a) a(1:end-2),f,'uni',0);
end
