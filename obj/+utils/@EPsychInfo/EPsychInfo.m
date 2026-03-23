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
    %   Copyright, RepositoryURL, CommitHistoryURL
    %   iconPath - Path to the EPsych icon directory.
    %   chksum - Latest commit checksum from the local git checkout.
    %   commitTimestamp - Timestamp of the latest local commit log entry.
    %   latestTag - Latest reachable git tag in the local repository.
    %   meta - Struct snapshot of the current metadata.
    %
    % Methods:
    %   icon_img - Load an icon image from the EPsych install.
    %   getLatestTag - Query git for the latest reachable repository tag.
    %
    % Example:
    %   info = EPsychInfo();
    %   disp(info.latestTag)
    %
    % See also documentation/EPsychInfo.md
    %
    % [MIGRATED from helpers/@EPsychInfo to obj/+utils/@EPsychInfo]
    
    properties (SetAccess = private)
        iconPath % Path to the EPsych icon assets.
        chksum % Latest commit checksum from the local checkout.
        commitTimestamp % Timestamp of the latest local commit log entry.
        latestTag % Latest reachable git tag for the local checkout.
        meta % Struct snapshot of version and repository metadata.
    end
    
    properties (Constant)
        Version  = '2.0';
        DataVersion = '1.1';        
        Author = 'Daniel Stolzberg';
        AuthorEmail = 'daniel.stolzberg@gmail.com';
        License = 'GNU General Public License v3.0';
        LicenseURL = 'https://www.gnu.org/licenses/gpl-3.0.en.html';
        Copyright = '(C) 2016-2026  Daniel Stolzberg, PhD';
        RepositoryURL = 'https://github.com/dstolz/epsych2';
        CommitHistoryURL = 'https://github.com/dstolz/epsych2/blob/master/documentation/CommitHistoryOverview.md';
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
            m.commitTimestamp = obj.commitTimestamp;
            m.LatestTag = obj.latestTag;
            m.RepositoryURL = obj.RepositoryURL;
            m.CurrentTimestamp = datetime("now");
        end
        
        function p = get.iconPath(obj)
            p = fullfile(obj.root,'icons');
        end
        
            
        function chksum = get.chksum(obj)
                        
            chksum = nan;
            
            fid = fopen(fullfile(obj.root,'.git','logs','HEAD'),'r');
            
            if fid < 3, return; end
            
            while ~feof(fid), g = fgetl(fid); end
            
            fclose(fid);
            
            a = find(g==' ');
            chksum = g(a(1)+1:a(2)-1);
        end
        
        function c = get.commitTimestamp(obj)
            try
                fn = fullfile(obj.root,'.git','logs','HEAD');
                d  = dir(fn);
                c  = d.date;
            catch
                warning('EPsychInfo:get:commitTimestamp','Not using the git version!')
                c = datetime(0);
            end
        end

        function tag = get.latestTag(obj)
            tag = obj.getLatestTag();
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

            tag = '';
            rootPath = obj.root;
            if isempty(rootPath) || ~isfolder(rootPath)
                return
            end

            gitCommand = sprintf('git -C "%s" describe --tags --abbrev=0 2> NUL',rootPath);
            [status,cmdout] = system(gitCommand);
            if status ~= 0
                return
            end

            tag = strtrim(cmdout);
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
    
    
end