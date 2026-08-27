function subdirs = epsych_startup(rootdir,showsplash)
% epsych_startup;
% epsych_startup(rootdir [,showsplash])
% subdirs = epsych_startup(...)
%
% Put an EPsych checkout and all of its subdirectories on the Matlab path.
%
% Typically, it is a good idea to call this function in the startup.m file
% which should be located somewhere along the default Matlab path.
% ex: ..\My Documents\MATLAB\startup.m
%
% Here's an example of what to include in startup.m:
%    addpath('C:\gits\epsych');
%    epsych_startup;
%
% Use a period '.' as the first character in a directory name to hide it
% from being added to the Matlab path.  Ex: C:\MATLAB\work\epsych\.RPvds
% Only the portion of a folder below ROOTDIR is examined, so the checkout
% itself may live anywhere -- including under a dotted directory.
%
% Exactly one EPsych checkout is left on the path.  Any other one -- a second
% clone, or a "git worktree" of this repository -- is removed first, because
% two trees on the path shadow each other class for class and the winner is
% then decided by path order.  Note that Matlab keeps class definitions and
% live objects from the evicted tree in memory: run "clear classes", or
% restart Matlab, before starting a session from the new one.
%
% Default rootdir is the folder holding the copy of this file that was called.
%
% Inputs:
%   rootdir    - EPsych checkout to activate.  Default: this file's folder.
%   showsplash - Print the startup banner.  Default: true.
%
% Return:
%   subdirs - Folders added to the path, as a pathsep-delimited char vector.
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

if nargin < 1 || isempty(rootdir)
    % Deliberately not which('epsych_startup'): in a worktree another checkout
    % may already own that name on the path, and this function has to set up
    % the tree it was actually invoked from, not whichever one answers first.
    rootdir = fileparts(mfilename('fullpath'));
end

assert(isfolder(rootdir),'Default directory "%s" not found. See help epsych_startup',rootdir)

rootdir = canonicalFolder(rootdir);

% Clear every EPsych tree off the path before adding this one: the current tree,
% so folders that have since been renamed or deleted stop lingering, and any
% other tree, which would otherwise shadow this checkout.
evicted = {};
for r = epsychRootsOnPath()
    removePathTree(r{1});
    if ~samePath(r{1},rootdir), evicted{end+1} = r{1}; end
end
removePathTree(rootdir); % subdirs of a tree whose root was not itself on the path

subdirs = visibleSubdirs(rootdir);

assert(~isempty(subdirs),'epsych_startup:noFolders', ...
    'No folders under "%s" could be added to the Matlab path.',rootdir)

addpath(subdirs);
path(path)
fprintf(' done\n')

% Find and configure the logging package, then rebuild the session logger now
% that the path is set. A file sink captures its directory when it is
% constructed, so a logger created against an older root -- or created before
% this repository was on the path at all, when granary.defaultLogDir falls back
% to tempdir -- would keep writing there for the rest of the session.
setup_granary(rootdir);
granary.Logger.instance('-reset');

% stimgen logs through its own front door. Give it somewhere to send the
% messages, so a StimPlayer or calibration failure lands in .error_logs with
% everything else instead of in a second file under tempdir.
install_stimgen_log_bridge();

report_evictions(evicted,rootdir);

check_submodules(rootdir);

vprintf(-1,'EPsych Toolbox version %s',EPsychInfo.Version);

if showsplash, epsych_printBanner; end


if nargout == 0, clear subdirs; end




function p = canonicalFolder(p)
% Absolute, fully resolved folder path.
%
% Matlab has no realpath, and the path bookkeeping here compares folders as
% strings: a relative segment, a trailing separator, or a mixed-case drive
% letter would each defeat the comparison.  cd resolves all of them and pwd
% reports the result.  This also dereferences a directory junction, which is
% wanted for the incoming root -- one spelling of a tree, chosen once -- but
% not for folders already on the path.  See epsychRootsOnPath.

old = cd(p);
p = pwd;
cd(old);


function p = normalisePath(p)
% Strip the cosmetic differences that string comparison would treat as real.

if ispc, p = strrep(p,'/',filesep); end
while ~isempty(p) && p(end) == filesep, p(end) = []; end


function tf = samePath(a,b)

a = normalisePath(a);
b = normalisePath(b);
if ispc, tf = strcmpi(a,b); else, tf = strcmp(a,b); end


function tf = pathIsUnder(p,root)
% True when P is ROOT or lives inside it.
%
% Both sides get a trailing separator so that a sibling worktree named
% "epsych2-async" is not mistaken for a subfolder of "epsych2".

if isempty(p), tf = false; return; end

p    = [normalisePath(p)    filesep];
root = [normalisePath(root) filesep];

if ispc
    tf = strncmpi(p,root,numel(root));
else
    tf = strncmp(p,root,numel(root));
end


function entries = pathEntries()

entries = strsplit(path,pathsep);
entries = entries(~cellfun(@isempty,entries));


function roots = epsychRootsOnPath()
% Root folder of every EPsych checkout currently on the Matlab path.
%
% A tree is recognised by its copy of this file.  epsych_startup always adds
% the root itself, so a tree it set up always exposes exactly one folder
% carrying the marker; everything else in that tree is found by prefix.
%
% Entries are deliberately NOT run through canonicalFolder: pwd dereferences a
% directory junction, so a tree reachable both directly and through a link
% would collapse to one root and the link-spelled folders would then survive
% the prefix match.  Removal has to work on the spellings the path actually
% holds, whatever they point at.

entries = pathEntries();
isroot  = cellfun(@(e) isfile(fullfile(e,'epsych_startup.m')),entries);
roots   = cellfun(@normalisePath,entries(isroot),'UniformOutput',false);

if isempty(roots), roots = {}; return; end

if ispc, [~,first] = unique(lower(roots),'stable');
else,    [~,first] = unique(roots,'stable');
end
roots = roots(first);


function removePathTree(root)
% Remove ROOT and everything below it from the Matlab path.
%
% Prefix matching rather than rmpath(genpath(root)): genpath only reports
% folders that still exist, so a renamed or deleted subdirectory -- a deleted
% worktree, for instance -- would otherwise stay on the path forever.

entries = pathEntries();
under = cellfun(@(e) pathIsUnder(e,root),entries);

if ~any(under), return; end

ws = warning('off','MATLAB:rmpath:DirNotFound');
rmpath(strjoin(entries(under),pathsep));
warning(ws);


function subdirs = visibleSubdirs(rootdir)
% Folders below ROOTDIR that belong on the Matlab path, pathsep-delimited.
%
% genpath skips +package, @class and private folders but descends happily into
% hidden ones (.git, .github, .error_logs), so those are filtered here.  The
% test runs on the portion of each folder BELOW rootdir: testing the whole
% absolute path drops the entire tree whenever the checkout itself sits under
% a dotted directory, which is exactly where a git worktree tends to land.

entries = strsplit(genpath(rootdir),pathsep);
entries = entries(~cellfun(@isempty,entries));

rel = cellfun(@(e) e(numel(rootdir)+1:end),entries,'UniformOutput',false);
subdirs = strjoin(entries(~contains(rel,[filesep '.'])),pathsep);


function report_evictions(evicted,rootdir)
% Say so when another checkout was taken off the path.
%
% Silence here is dangerous: the path is now consistent, but any class already
% loaded from the old tree stays loaded, so the session can be running a mix of
% both until the definitions are cleared.

for i = 1:numel(evicted)
    vprintf(0,['EPsych: removed another checkout from the Matlab path: %s\n' ...
        '    Now running from: %s\n' ...
        '    Class definitions and objects from the other tree are still in ' ...
        'memory -- run "clear classes" or restart Matlab before starting a session.'], ...
        evicted{i},rootdir);
end


function setup_granary(rootdir)
% Put the granary logging package on the path and configure it for this tree.
%
% granary is a separate repository: vprintf is a thin facade over it, so
% nothing in the toolbox can log until it is found.  That makes this the one
% dependency worth failing loudly about -- left to itself it would surface as
% "Undefined variable granary" from whichever call site happened to log first,
% which is never the code that is actually wrong.
%
% Searched in order: already on the path, an explicit preference, obj/granary
% inside this checkout (where a submodule would sit), a sibling beside this
% checkout, then a sibling one level up -- which is where a "git worktree"
% finds it, since a worktree lives a directory deeper than the checkout it was
% made from.

if isempty(which('granary.printf'))
    candidates = {};

    % An explicit override wins, so a rig that keeps its checkouts somewhere
    % unusual sets this once instead of editing startup.
    try
        if ispref('EPsych','GranaryPath')
            candidates{end+1} = char(getpref('EPsych','GranaryPath'));
        end
    catch
        % Preferences unreadable; fall through to the search.
    end

    up1 = fileparts(rootdir);
    candidates = [candidates, { ...
        fullfile(rootdir,'obj','granary'), ...
        fullfile(up1,'granary'), ...
        fullfile(fileparts(up1),'granary')}];

    for i = 1:numel(candidates)
        if isfolder(fullfile(candidates{i},'+granary'))
            addpath(candidates{i});
            break
        end
    end
end

assert(~isempty(which('granary.printf')),'epsych_startup:granaryMissing', ...
    ['The granary logging package was not found, so EPsych cannot log and ' ...
     'will not start.\n' ...
     '    Clone it beside this checkout:\n' ...
     '        git clone https://github.com/dstolz/granary "%s"\n' ...
     '    or point at an existing copy:\n' ...
     '        setpref(''EPsych'',''GranaryPath'',''<folder holding +granary>'')\n' ...
     '    or add it to the Matlab path before calling epsych_startup.'], ...
    fullfile(fileparts(rootdir),'granary'));

% LogRoot puts .error_logs inside this checkout, which is where EPsych has
% always written.  FacadeFiles names the two files that stand between a call
% site and the logger, so records keep naming the code that logged rather than
% the wrapper: vprintf for EPsych's own calls, and stimbridge.LogBridge for
% stimgen's, which adds two frames of its own.
%
% PrefGroup is 'eplog' rather than the package default: that preference
% predates this extraction, and moving the group would silently orphan every
% rig's configured Error Log Path.
granary.config( ...
    'LogRoot',     rootdir, ...
    'PrefGroup',   'eplog', ...
    'FacadeFiles', {'vprintf.m','LogBridge.m'});


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
% -- worse -- silently degrading any saved .eprot that contains a
% stimgen.StimType parameter, because MATLAB substitutes a placeholder
% struct for a class it cannot resolve instead of raising an error.
%
% The probe has to resolve inside ROOTDIR, not merely resolve.  "git worktree
% add" does not populate submodules, so a fresh worktree has an empty
% obj/stimgen while some other copy of stimgen on the path answers for the
% class -- the session would then run against stimuli from the wrong tree.

submodules = { ...
    'obj/stimgen', 'stimgen.StimType', 'https://github.com/dstolz/stimgen'};

for i = 1:size(submodules,1)
    relpath = submodules{i,1};
    probe   = submodules{i,2};
    url     = submodules{i,3};

    resolved = which(probe);
    if exist(probe,'class') == 8 && pathIsUnder(resolved,rootdir), continue; end

    d = fullfile(rootdir, strrep(relpath,'/',filesep));
    entries = dir(d);
    entries = entries(~ismember({entries.name}, {'.','..'}));
    if ~isempty(resolved)
        reason = sprintf('"%s" resolves outside this checkout, to "%s"', probe, resolved);
    elseif isfolder(d) && ~isempty(entries)
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
