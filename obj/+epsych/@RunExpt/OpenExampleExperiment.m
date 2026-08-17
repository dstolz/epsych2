function OpenExampleExperiment(self, exampleName)
% OpenExampleExperiment(self, exampleName)
% Open the wiki page for one of the examples/ walkthroughs in the default
% web browser, the same way Help > Documentation opens a doc page.
%
% Parameters:
%	exampleName	- Example folder under examples/: "first_experiment" or
%                 "two_afc".
%
% See also: epsych.RunExpt.LaunchUtility
arguments
    self
    exampleName (1,1) string {mustBeMember(exampleName, ...
        ["first_experiment","two_afc"])}
end

switch exampleName
    case "first_experiment"
        label = 'Your First Experiment';
        page  = 'Your-First-Experiment';
    case "two_afc"
        label = 'Two-AFC Task';
        page  = 'Two-AFC-Task';
end

web([EPsychInfo.WikiURL '/' page],'-browser');

self.setStatus(sprintf('Opened "%s" wiki page.',label), ...
    'Follow the Quick Start commands in the wiki to run it in MATLAB.');
end
