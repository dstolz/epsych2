classdef EPsychInfo < handle
    % obj = EPsychInfo()
    % EPsych repository and release metadata helper.
    %
    % EPsychInfo centralizes version strings, license information, and git
    % metadata used by startup banners, saved protocol metadata, and runtime
    % version dialogs.
    %
    % Properties:
    %   Version, DataVersion, Author, AuthorEmail, License, LicenseURL
    %   Copyright, RepositoryURL, CommitHistoryURL, WikiURL
    %   iconPath - Path to the EPsych icon directory.
    %   chksum - Latest commit checksum from the local git checkout.
    %   stimgenChksum - Latest commit checksum of the obj/stimgen submodule.
    %   commitTimestamp - Timestamp of the latest local commit log entry.
    %   latestTag - Latest reachable git tag in the local repository.
    %   worktree - Name of the git worktree backing this checkout, if any.
    %   meta - Struct snapshot of the current metadata.
    %   diagnostics - Struct of host computer and software environment info.
    %
    % Methods:
    %   icon_img - Load an icon image from the EPsych install.
    %   getLatestTag - Query git for the latest reachable repository tag.
    %
    % Example:
    %   info = EPsychInfo();
    %   disp(info.latestTag)
    %
    % See also documentation/epsych/EPsychInfo.md
    
    properties (SetAccess = private)
        iconPath % Path to the EPsych icon assets.
        chksum % Latest commit checksum from the local checkout.
        stimgenChksum % Latest commit checksum of the obj/stimgen submodule.
        commitTimestamp % Timestamp of the latest local commit log entry.
        latestTag % Latest reachable git tag for the local checkout.
        worktree % Name of the git worktree backing this checkout; '' for the main one.
        meta % Struct snapshot of version and repository metadata.
        diagnostics % Struct of host machine and software environment details.
    end
    
    properties (Constant)
        Version  = '2';
        DataVersion = '1.2';   
        Author = 'Daniel Stolzberg';
        AuthorEmail = 'daniel.stolzberg@gmail.com';
        License = 'GNU General Public License v3.0';
        LicenseURL = 'https://www.gnu.org/licenses/gpl-3.0.en.html';
        Copyright = '(C) 2016-2026  Daniel Stolzberg, PhD';
        RepositoryURL = 'https://github.com/dstolz/epsych2';
        CommitHistoryURL = 'https://github.com/dstolz/epsych2/blob/master/documentation/overviews/CommitHistoryOverview.md';
        WikiURL = 'https://github.com/dstolz/epsych2/wiki';
        DocumentationURL = 'https://github.com/dstolz/epsych2/wiki';
    end
    
    methods
        % Constructor
        function obj = EPsychInfo()
            
        end
        
        
        function m = get.meta(obj)
            m.Author      = obj.Author;
            m.AuthorEmail = obj.AuthorEmail;
            m.Copyright   = obj.Copyright;
            m.License     = obj.License;
            m.Version     = obj.Version;
            m.DataVersion = obj.DataVersion;
            m.Checksum    = obj.chksum;
            % stimgen lives in its own repository and releases on its own
            % cadence, so the parent checksum alone no longer identifies the
            % code that generated a session's stimuli.
            m.StimgenChecksum = obj.stimgenChksum;
            m.commitTimestamp = obj.commitTimestamp;
            m.LatestTag = obj.latestTag;
            % Two checkouts of the same commit can differ in uncommitted work,
            % so a session run from a worktree records which one it came from.
            m.Worktree = obj.worktree;
            m.RepositoryURL = obj.RepositoryURL;
            m.WikiURL = obj.WikiURL;
            m.CurrentTimestamp = datetime("now");
        end
        
        function p = get.iconPath(obj)
            p = fullfile(obj.root,'icons');
        end
        
            
        function chksum = get.chksum(obj)
            chksum = EPsychInfo.commitFromGitLog_(EPsychInfo.headLogFile_(obj.root));
        end

        function chksum = get.stimgenChksum(obj)
            % Resolved through the submodule's own gitfile rather than a
            % hardcoded .git/modules path: a worktree keeps its submodule
            % gitdirs under .git/worktrees/<name>/modules instead.
            chksum = EPsychInfo.commitFromGitLog_( ...
                EPsychInfo.headLogFile_(fullfile(obj.root,'obj','stimgen')));
        end

        function c = get.commitTimestamp(obj)
            d = dir(EPsychInfo.headLogFile_(obj.root));
            if isempty(d)
                warning('EPsychInfo:get:commitTimestamp','Not using the git version!')
                c = datetime(0);
                return
            end
            c = d(1).date;
        end

        function w = get.worktree(obj)
            [~,w] = EPsychInfo.gitDir_(obj.root);
        end

        function tag = get.latestTag(obj)
            tag = obj.getLatestTag();
        end

        function d = get.diagnostics(~)
            % d = get.diagnostics(obj)
            % Return a struct of host computer and software environment details
            % for diagnostic and logging purposes.
            %
            % Return:
            %   d - Struct with fields:
            %       matlabVersion    - Full MATLAB version string.
            %       matlabRelease    - MATLAB release name (e.g. 'R2024b').
            %       javaVersion      - Java runtime version string.
            %       platform         - Platform/architecture identifier from `computer`.
            %       hostname         - Network hostname of the current machine.
            %       numLogicalCores  - Number of logical CPU cores available to MATLAB.
            %       physicalMemoryGB - Total physical RAM in GB (NaN on non-Windows).
            %       availableMemoryGB- Available physical RAM in GB (NaN on non-Windows).
            %       screenSize       - Root display size in pixels [left bottom width height].
            %       toolboxes        - Cell array of installed MathWorks toolbox names.
            %       timestamp        - datetime when diagnostics were collected.

            d.matlabVersion   = version;
            d.matlabRelease   = version('-release');
            d.javaVersion     = version('-java');
            d.platform        = computer;

            try
                d.hostname = char(java.net.InetAddress.getLocalHost.getHostName);
            catch
                d.hostname = '';
            end

            d.numLogicalCores = double(java.lang.Runtime.getRuntime().availableProcessors());

            try
                [~, mem]            = memory;
                d.physicalMemoryGB  = mem.PhysicalMemory.Total  / 1024^3;
                d.availableMemoryGB = mem.PhysicalMemory.Available / 1024^3;
            catch
                d.physicalMemoryGB  = nan;
                d.availableMemoryGB = nan;
            end

            d.screenSize = get(0, 'ScreenSize');

            tbx = ver;
            d.toolboxes = {tbx.Name};

            d.timestamp = datetime('now');
        end

        function tag = getLatestTag(obj)
            % tag = getLatestTag(obj)
            % Return the latest reachable git tag for the local EPsych checkout.
            %
            % Input:
            %   obj - EPsychInfo scalar.
            %
            % Return:
            %   tag - Tag name as a character vector. Returns '' when git is
            %       unavailable or no reachable tag exists.
            %
            % Cached for the life of the MATLAB session, keyed by checkout
            % root. A repository tag changes only when someone runs `git tag`
            % in another process, which no consumer of this value (metadata
            % strings, startup banner) can distinguish -- but the subprocess it
            % replaces costs 50-300 ms on Windows and runs on EVERY
            % epsych.Protocol construction, which then discards the result
            % (see Protocol/fromStruct.m). `clear functions` re-queries.

            persistent cachedRoot cachedTag

            rootPath = obj.root;
            if isempty(rootPath) || ~isfolder(rootPath)
                tag = '';
                return
            end

            if ~isempty(cachedRoot) && strcmp(cachedRoot, rootPath)
                tag = cachedTag;
                return
            end

            tag = '';
            gitCommand = sprintf('git -C "%s" describe --tags --abbrev=0 2> NUL',rootPath);
            [status,cmdout] = system(gitCommand);
            if status == 0
                tag = strtrim(cmdout);
            end

            % Cache the empty result too: a machine without git otherwise pays
            % a failing process spawn on every call.
            cachedRoot = rootPath;
            cachedTag = tag;
        end
        
        function img = icon_img(obj,type)
            % img = icon_img(obj, type)
            % Load an icon image from the EPsych icon directory.
            %
            % Input:
            %   type - Icon filename stem within the icons directory.
            %
            % Return:
            %   img - RGB image with zero-valued pixels mapped to NaN.

            d = dir(obj.iconPath);
            d(ismember({d.name},{'.','..'})) = [];
            
            mustBeMember(type,{d.name})
            
            ffn = fullfile(obj.iconPath,type);
            y = dir([ffn '*']);
            ffn = fullfile(y(1).folder,y(1).name);
            [img,map] = imread(ffn);
            if isempty(map)
                img = im2double(img);
            else
                img = ind2rgb(img,map);
            end
            img(img == 0) = nan;
        end
        
    end
    
    methods (Static)
        function r = root
            % r = root
            % Return the EPsych installation root directory.

            r = fileparts(which('epsych_startup'));
        end
        
        function s = last_modified_str(datens)
            % s = last_modified_str(datens)
            %
            % Accepts filename, date string, or datenum and returns:
            % 'File last modifed on Sun, May 05, 2019 at 12:19 PM'
            
            narginchk(1,1);
            
            if ischar(datens)
                if exist(datens,'file') == 2
                    d = dir(datens);
                    datens = d(1).date;
                end
                datens = datenum(datens);
            end
                
            s = sprintf('File last modifed on %s at %s', ...
                datestr(datens,'ddd, mmm dd, yyyy'),datestr(datens,'HH:MM PM'));
        end


    end

    methods (Static, Access = private)
        function [gitdir,wtname] = gitDir_(checkoutPath)
            % [gitdir, wtname] = gitDir_(checkoutPath)
            % Resolve the git directory backing a working tree.
            %
            % A plain checkout keeps its git directory in ".git". A linked
            % worktree -- like a submodule -- keeps a one-line ".git" *file*
            % holding "gitdir: <path>" instead, so the folder with HEAD and
            % the reflog is elsewhere entirely. Reading ".git/logs/HEAD"
            % directly therefore finds nothing at all in a worktree.
            %
            % Input:
            %   checkoutPath - Working tree folder.
            %
            % Return:
            %   gitdir - Folder holding HEAD and logs, or '' when there is
            %       none (zip download, submodule not checked out).
            %   wtname - Worktree name as git records it under
            %       ".git/worktrees", or '' for a repository's main working
            %       tree.

            gitdir = '';
            wtname = '';

            p = fullfile(checkoutPath,'.git');

            if isfolder(p)
                gitdir = p;
                return
            end

            fid = fopen(p,'r');
            if fid < 3, return; end
            g = fgetl(fid);
            fclose(fid);

            if ~ischar(g), return; end

            g = strtrim(g);
            if ~strncmpi(g,'gitdir:',7), return; end

            g = strtrim(g(8:end));
            if isempty(g), return; end

            % The pointer is relative to the working tree holding the gitfile
            % whenever git can write it that way, absolute otherwise.
            if ~isfolder(g), g = fullfile(checkoutPath,g); end
            if ~isfolder(g), return; end

            gitdir = g;

            % ".git/worktrees/<name>" is git's own identifier for a linked
            % worktree; a submodule resolves under "modules" instead.
            [parent,name] = fileparts(gitdir);
            [~,parentName] = fileparts(parent);
            if strcmpi(parentName,'worktrees')
                wtname = name;
            end
        end

        function ffn = headLogFile_(checkoutPath)
            % ffn = headLogFile_(checkoutPath)
            % Path to a working tree's "logs/HEAD" reflog.
            %
            % Input:
            %   checkoutPath - Working tree folder.
            %
            % Return:
            %   ffn - Full path to the reflog, or '' when the working tree
            %       has no git directory.

            ffn = '';

            gitdir = EPsychInfo.gitDir_(checkoutPath);
            if isempty(gitdir), return; end

            ffn = fullfile(gitdir,'logs','HEAD');
        end

        function chksum = commitFromGitLog_(logfile)
            % chksum = commitFromGitLog_(logfile)
            % Last commit hash recorded in a git "logs/HEAD" file.
            %
            % Input:
            %   logfile - Path to a git logs/HEAD file.
            %
            % Return:
            %   chksum - Commit hash as a character vector, or NaN when the
            %       file is missing or empty (zip download, submodule not
            %       checked out).

            chksum = nan;

            if isempty(logfile), return; end

            fid = fopen(logfile,'r');

            if fid < 3, return; end

            g = '';
            while ~feof(fid), g = fgetl(fid); end

            fclose(fid);

            a = find(g==' ');
            if numel(a) < 2, return; end

            chksum = g(a(1)+1:a(2)-1);
        end
    end
    
    
end
