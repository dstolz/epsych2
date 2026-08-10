function subdirs = epsych_startup(rootdir,showsplash)
% epsych_startup;
% epsych_startup(rootdir [,showsplash])
% newp = epsych_startup(...)
%
% Finds all subdirectories in a given root directory, removes any
% directories with 'svn', and adds them to the Matlab path.
%
% Typically, it is a good idea to call this function in the startup.m file 
% which should be located somewhere along the default Matlab path. 
% ex: ..\My Documents\MATLAB\startup.m
% 
% Here's an example of what to include in startup.m:
%    addpath('C:\gits\epsych');
%    epsych_startup;
% 
% Alternatively, call this function only after retrieving software updates
% using SVN.
%
% Use a period '.' as the first character in a directory name to hide it
% from being added to the Matlab path.  Ex: C:\MATLAB\work\epsych\.RPvds
% 
% Default rootdir is wherever this function lives.  
% 
% Daniel.Stolzberg@gmail.com 2014

%     EPsych  
%     Copyright (C) 2026  Daniel Stolzberg, PhD
% 
%     This program is free software: you can redistribute it and/or modify
%     it under the terms of the GNU General Public License as published by
%     the Free Software Foundation, either version 3 of the License, or
%     (at your option) any later version.
% 
%     This program is distributed in the hope that it will be useful,
%     but WITHOUT ANY WARRANTY; without even the implied warranty of
%     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%     GNU General Public License for more details.
% 
%     You should have received a copy of the GNU General Public License
%     along with this program.  If not, see <http://www.gnu.org/licenses/>.


warning('off','MATLAB:ui:javaframe:PropertyToBeRemoved');
warning('off','MATLAB:ui:actxcontrol:FunctionToBeRemoved');

if nargin < 2 || isempty(showsplash), showsplash = true; end


fprintf('\nSetting Paths for EPsych Toolbox ...')

if ~nargin || isempty(rootdir)
    [rootdir,~] = fileparts(which('epsych_startup'));
end

assert(isfolder(rootdir),'Default directory "%s" not found. See help epsych_startup',rootdir)

oldpath = genpath(rootdir);
c = textscan(oldpath,'%s','Delimiter',';');
warning('off','MATLAB:rmpath:DirNotFound');
cellfun(@rmpath,c{1});
warning('on','MATLAB:rmpath:DirNotFound');

addpath(rootdir);

p = genpath(rootdir);

t = textscan(p,'%s','delimiter',';');
i = cellfun(@(x) (strfind(x,'\.')),t{1},'UniformOutput',false);
ind = cell2mat(cellfun(@isempty,i,'UniformOutput',false));
subdirs = cellfun(@(x) ([x ';']),t{1}(ind),'UniformOutput',false);
subdirs = cell2mat(subdirs');

addpath(subdirs);
path(path)
fprintf(' done\n')

% Rebuild the session logger now that the path is set. A file sink captures
% its directory when it is constructed, so a logger created against an older
% root -- or created before this repository was on the path at all, when
% eplog.defaultLogDir falls back to tempdir -- would keep writing there for
% the rest of the session.
eplog.Logger.instance('-reset');

% stimgen logs through its own front door. Give it somewhere to send the
% messages, so a StimPlayer or calibration failure lands in .error_logs with
% everything else instead of in a second file under tempdir.
install_stimgen_log_bridge();

check_submodules(rootdir);

vprintf(-1,'EPsych Toolbox version %s',EPsychInfo.Version);

if showsplash, epsych_printBanner; end


if nargout == 0, clear subdirs; end




function install_stimgen_log_bridge()
% Route stimgen's logging into the EPsych session log.
%
% Guarded rather than assumed: pinning a stimgen that predates the logging seam
% is a supported configuration, and it must degrade to "stimgen keeps its own
% log" rather than to an error during startup.
%
% The probe order is load-bearing. It has to ask about stimgen.LogSink, NOT
% about stimbridge.LogBridge: LogBridge derives from stimgen.LogSink, so under
% an older pin MATLAB cannot resolve its superclass and merely naming the class
% raises. "which" is used rather than exist(...,'file') because it is
% unambiguous for package members, and is what SelfTest check A2 already uses.
try
    if isempty(which('stimgen.LogSink')) || isempty(which('stimgen.util.logSink'))
        return
    end

    % Idempotent: epsych_startup is routinely re-run, and re-installing would
    % otherwise discard a bridge that is working perfectly well.
    current = stimgen.util.logSink();
    if ~isempty(current) && isa(current,'stimbridge.LogBridge') && isvalid(current)
        return
    end

    stimgen.util.logSink(stimbridge.LogBridge());
    vprintf(2,'stimgen logging routed into the EPsych session log');
catch ME
    % Losing the bridge costs a unified log, not a working session.
    vprintf(0,1,'EPsych: could not install the stimgen log bridge: %s',ME.message);
end


function check_submodules(rootdir)
% Warn when a required submodule has not been checked out.
%
% Without this, a clone made without --recurse-submodules fails in two
% confusing ways: "Undefined variable stimgen" at unrelated call sites, and
% -- worse -- silently degrading any saved .eprot/.ecfg that contains a
% stimgen.StimType parameter, because MATLAB substitutes a placeholder
% struct for a class it cannot resolve instead of raising an error.

submodules = { ...
    'obj/stimgen', 'stimgen.StimType', 'https://github.com/dstolz/stimgen'};

for i = 1:size(submodules,1)
    relpath = submodules{i,1};
    probe   = submodules{i,2};
    url     = submodules{i,3};

    if exist(probe,'class') == 8, continue; end

    d = fullfile(rootdir, strrep(relpath,'/',filesep));
    entries = dir(d);
    entries = entries(~ismember({entries.name}, {'.','..'}));
    if isfolder(d) && ~isempty(entries)
        reason = sprintf('"%s" is present but "%s" did not resolve', relpath, probe);
    else
        reason = sprintf('"%s" is empty or missing', relpath);
    end

    vprintf(0,1,['EPsych: required submodule not available -- %s.\n' ...
        '    Run:  git submodule update --init --recursive\n' ...
        '    Source: %s\n' ...
        '    Until this is fixed, protocols containing stimulus objects ' ...
        'will not load correctly.'], reason, url);
end
