function epsych_printBanner()
% ep_printBanner
%
% Print text EPsych banner and a link to the online manual
%
% daniel.stolzberg@gmail.com 2023 (c)


m = ['  ___  ___                _      ___     __  '; ...
     ' | __|| _ \ ___ _  _  __ | |_   |_  )   /  \ '; ...
     ' | _| |  _/(_-<| || |/ _|| '' \   / /  _| () |'; ...
     ' |___||_|  /__/ \_, |\__||_||_| /___|(_)\__/ '; ...
     '                |__/                         '];

E = EPsychInfo;

cm = cellstr(m);
cm{end} = sprintf('%s\nv%s <a href="%s">%s</a>',cm{end},E.Version,E.LicenseURL,E.Copyright);
lnk = E.RepositoryURL;
cm{end+1} = sprintf('Repository: <a href="%s">%s</a>',lnk,lnk);
%cm{end+1} = '-> <a href="matlab: ep_LaunchPad">ep_LaunchPad</a>  ... Launch panel for EPsych utilities';
cm{end+1} = '--> <a href="matlab: ep_ExperimentDesign">ep_ExperimentDesign</a>  ... Define parameters for experiments';
%cm{end+1} = '--> <a href="matlab: ep_BitmaskGen">ep_BitmaskGen</a>        ... Bitmask table generator for behavioral experiments';
cm{end+1} = '--> <a href="matlab: ep_CalibrationUtil">ep_CalibrationUtil</a>   ... Sound calibration utility';
%cm{end+1} = '--> <a href="matlab: ep_EPhys">ep_EPhys</a>             ... Electrophysiology experiments with OpenEx';
cm{end+1} = '--> <a href="matlab: ep_RunExpt">ep_RunExpt</a>           ... Behavioral/Electrophysiology with or without OpenEx';

fprintf('\n')
for i = 1:length(cm), fprintf('%s\n',cm{i}); end







