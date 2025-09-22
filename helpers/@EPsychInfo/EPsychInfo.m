classdef EPsychInfo < handle
    % class contains general inormation for the EPsych software
    
    properties (SetAccess = private)
        iconPath
        chksum
        commitTimestamp
        meta
    end
    
    properties (Constant)
        Version  = '2.0';
        DataVersion = '1.1';        
        Author = 'Daniel Stolzberg';
        AuthorEmail = 'daniel.stolzberg@gmail.com';
        License = 'GNU General Public License v3.0';
        LicenseURL = 'https://www.gnu.org/licenses/gpl-3.0.en.html';
        Copyright = '(C) 2016-2025  Daniel Stolzberg, PhD';
        RepositoryURL = 'https://github.com/dstolz/epsych2';
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
        
        function img = icon_img(obj,type)
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