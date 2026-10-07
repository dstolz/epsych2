function s = describeFile_(~, file)
% s = describeFile_(obj, file)
%
% One file's description from ONE load: epsych.SessionFiles.summarize's row,
% with extra_ run on the Data and snapshot that load already holds. The
% summarize cache is bypassed (it is keyed without the callback); this class
% caches on disk instead.
%
% See also: epsych.SessionFiles.summarize, behavior.Catalog.extra_

s = epsych.SessionFiles.summarize(file, UseCache = false, ...
    Extra = @behavior.Catalog.extra_);

end
