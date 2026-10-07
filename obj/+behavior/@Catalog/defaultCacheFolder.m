function f = defaultCacheFolder()
% f = behavior.Catalog.defaultCacheFolder()
% Where scan caches go unless told otherwise: the user's local application
% data, which is per machine and never synced, so a cache never lands beside
% the data it describes.
%
% Returns:
%   f - %LOCALAPPDATA%\EPsych\AnalysisCache, else
%       fullfile(tempdir, 'EPsych', 'AnalysisCache').
%
% See also: behavior.Catalog

base = string(getenv('LOCALAPPDATA'));
if strlength(strtrim(base)) > 0
    f = string(fullfile(base, 'EPsych', 'AnalysisCache'));
else
    f = string(fullfile(tempdir, 'EPsych', 'AnalysisCache'));
end

end
