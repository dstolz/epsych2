function recent = GetRecentConfigs(self)
% recent = GetRecentConfigs(self)
% Return persisted recent config paths loaded within the past seven days.
% Inputs
%   self (epsych.RunExpt) - Scalar RunExpt instance.
% Outputs
%   recent (1,:) cell - Row cell array of existing config file paths.
% Notes
%   Reads ep_RunExpt_Setup.RecentConfigs and matching load-time metadata,
%   then normalizes and persists cleaned preference values.

if ~isscalar(self)
    recent = {};
    return
end

recent = getpref('ep_RunExpt_Setup','RecentConfigs',{});

if isstring(recent)
    recent = cellstr(recent(:));
elseif ischar(recent)
    recent = {recent};
elseif ~iscell(recent)
    recent = {};
end

recent = recent(:)';
recent = recent(~cellfun(@isempty, recent));

if isempty(recent)
    setpref('ep_RunExpt_Setup','RecentConfigs',{})
    setpref('ep_RunExpt_Setup','RecentConfigLoadedOn',struct('path',{},'loadedOn',{}))
    return
end

keep = cellfun(@(p) exist(p,'file') == 2, recent);
recent = recent(keep);

meta = getpref('ep_RunExpt_Setup','RecentConfigLoadedOn',struct('path',{},'loadedOn',{}));
if ~isstruct(meta) || ~all(isfield(meta,{'path','loadedOn'}))
    meta = struct('path',{},'loadedOn',{});
end

if isempty(recent)
    recent = {};
else
    loadedOn = nan(1,numel(recent));
    for i = 1:numel(recent)
        idx = find(strcmpi({meta.path}, recent{i}), 1, 'first');
        if ~isempty(idx)
            loadedVal = meta(idx).loadedOn;
            if isnumeric(loadedVal) && isscalar(loadedVal) && isfinite(loadedVal)
                loadedOn(i) = loadedVal;
            end
        end
    end

    keep = loadedOn >= (now - 7);
    recent = recent(keep);
    loadedOn = loadedOn(keep);

    if isempty(recent)
        meta = struct('path',{},'loadedOn',{});
    else
        meta = struct('path', recent, 'loadedOn', num2cell(loadedOn));
    end
end

stored = getpref('ep_RunExpt_Setup','RecentConfigs',{});
if ~isequal(stored, recent)
    setpref('ep_RunExpt_Setup','RecentConfigs',recent)
end

storedMeta = getpref('ep_RunExpt_Setup','RecentConfigLoadedOn',struct('path',{},'loadedOn',{}));
if ~isequal(storedMeta, meta)
    setpref('ep_RunExpt_Setup','RecentConfigLoadedOn',meta)
end