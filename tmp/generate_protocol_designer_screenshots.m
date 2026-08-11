function generate_protocol_designer_screenshots()
% generate_protocol_designer_screenshots()
% Regenerate the Protocol Designer documentation images from the expression/pairs
% fixture, so the guides show the current toolbar layout.
%
% Writes documentation/design/images/ProtocolDesigner.png (main window) and
% ProtocolDesigner_Interfaces.png (the Interfaces dialog).
%
%   matlab -batch "run('tmp/generate_protocol_designer_screenshots.m')"

here = fileparts(mfilename('fullpath'));
repoRoot = fileparts(here);
run(fullfile(repoRoot, 'epsych_startup.m'));

imageDir = fullfile(repoRoot, 'documentation', 'design', 'images');

fixture = fullfile(here, 'protocol_designer_expression_pairs_test.eprot');
if ~isfile(fixture)
    fixture = generate_protocol_designer_test_fixture(fixture);
end

% The column view is a saved user preference; pin it for a reproducible image.
prefGroup = 'ProtocolDesigner';
savedView = [];
if ispref(prefGroup, 'TableViewMode')
    savedView = getpref(prefGroup, 'TableViewMode');
end
restorePref = onCleanup(@() localRestorePref_(prefGroup, savedView));
setpref(prefGroup, 'TableViewMode', 'Detailed');

pd = epsych.ProtocolDesigner.openFromFile(fixture);
pd.onOpenInterfaceDialog();
drawnow

handles = struct(pd);
cleanupPd = onCleanup(@() localCloseAll_(handles));

exportapp(handles.Figure, fullfile(imageDir, 'ProtocolDesigner.png'));
exportapp(handles.InterfaceFigure, fullfile(imageDir, 'ProtocolDesigner_Interfaces.png'));

fprintf('Wrote screenshots to %s\n', imageDir);
end

function localRestorePref_(prefGroup, savedView)
if isempty(savedView)
    if ispref(prefGroup, 'TableViewMode')
        rmpref(prefGroup, 'TableViewMode');
    end
else
    setpref(prefGroup, 'TableViewMode', savedView);
end
end

function localCloseAll_(handles)
figs = {handles.Figure, handles.InterfaceFigure, handles.OptionsFigure, ...
    handles.PreviewFigure, handles.CheckCalcFigure};
for idx = 1:numel(figs)
    if ~isempty(figs{idx}) && isvalid(figs{idx})
        delete(figs{idx});
    end
end
end
