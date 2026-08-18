function smoke_test_calibration_wiki_summary_tools()
% smoke_test_calibration_wiki_summary_tools()
% Verify the CalibrationGui toolbar's two documentation/record tools: the
% one that prints the calibration summary and the one that opens this
% window's wiki guide.
%
% Four things are checked:
%
%   1. stimgen.util.toolbar_icon draws the two new glyphs at the size and
%      in the form every other icon takes (24x24x3, NaN = transparent),
%      and neither is a duplicate of a glyph already on this toolbar --
%      two tools that look alike are the failure this guards.
%   2. Both tools carry a tooltip from the JSON catalog rather than the
%      empty string an unknown key returns.
%   3. The toolbar carries them, in the groups they belong to, and their
%      callbacks reach the handlers rather than a stale name.
%   4. The summary tool's handler prints the description Engine.describe
%      returns, so the button and the prompt say the same thing.
%
%   matlab -batch "cd('tmp'); smoke_test_calibration_wiki_summary_tools"

thisDir = fileparts(mfilename('fullpath'));
run(fullfile(thisDir, '..', 'epsych_startup.m'));

cleanupObj = onCleanup(@() delete(findall(groot, 'Type', 'figure')));

%% 1. The glyphs.
new = ["summary" "wiki"];
for n = new
    ic = stimgen.util.toolbar_icon(n);
    assert(isequal(size(ic), [24 24 3]), '%s is not 24x24x3', n);
    assert(any(isnan(ic(:))), '%s has no transparent background', n);
    assert(any(~isnan(ic(:))), '%s drew nothing', n);
end

% Distinct from each other and from every glyph already on this toolbar.
onToolbar = ["protocol" "connect" "disconnect" "open" "save" "camera" ...
             "help" "ghost" "voltage" "logx" new];
masks = arrayfun(@glyph_mask_, onToolbar, UniformOutput=false);
for i = 1:numel(onToolbar)
    for j = i+1:numel(onToolbar)
        assert(~isequal(masks{i}, masks{j}), ...
            'toolbar glyphs "%s" and "%s" are identical', onToolbar(i), onToolbar(j));
    end
end
fprintf('PASS: summary and wiki glyphs are drawn and distinct\n');

%% 2. Tooltips resolve.
for key = ["PrintSummary" "GuiGuideTool"]
    tt = stimgen.util.tooltip('CalibrationGui', key);
    assert(strlength(strtrim(tt)) > 0, 'tooltip %s is empty', key);
end
fprintf('PASS: both tools have tooltip text\n');

%% 3. The tools are on the toolbar, in order, wired to real handlers.
gui = stimgen.calibration.CalibrationGui();
fig = findall(groot, 'Type', 'figure', 'Name', 'Stim Calibration');
tools = findall(fig, 'Type', 'uipushtool');
tools = flip(tools);   % findall returns children in reverse creation order
tips = string(get(tools, 'Tooltip'));

iSummary = find(tips == stimgen.util.tooltip('CalibrationGui', 'PrintSummary'));
iCopy    = find(tips == stimgen.util.tooltip('CalibrationGui', 'CopyWindowTool'));
iQuick   = find(tips == stimgen.util.tooltip('CalibrationGui', 'QuickStartTool'));
iGuide   = find(tips == stimgen.util.tooltip('CalibrationGui', 'GuiGuideTool'));
assert(isscalar(iSummary) && isscalar(iGuide), 'new tools missing from toolbar');

% Grouping: summary opens the "take the session out of the window" group
% and the picture follows it; the book follows the question mark.
assert(iCopy == iSummary + 1, 'summary tool is not beside the camera tool');
assert(strcmp(tools(iSummary).Separator, 'on'), 'summary tool does not open a group');
assert(strcmp(tools(iCopy).Separator, 'off'), 'camera tool still opens its own group');
assert(iGuide == iQuick + 1, 'wiki tool is not beside the quick start tool');
assert(strcmp(tools(iGuide).Separator, 'off'), 'wiki tool is split from quick start');

% The URL the book opens is the walkthrough's tour of this window, not the
% page top the question mark already goes to.
G = stimgen.calibration.CalibrationGui.GuiGuideURL;
Q = stimgen.calibration.CalibrationGui.QuickStartURL;
assert(~strcmp(G, Q), 'both help tools open the same address');
assert(startsWith(G, Q) && contains(G, '#'), 'wiki tool does not open an anchor on the walkthrough');

% Callbacks are live handles rather than a name that no longer exists.
for t = [tools(iSummary) tools(iGuide)]
    assert(isa(t.ClickedCallback, 'function_handle'), 'tool has no callback');
end
fprintf('PASS: both tools are on the toolbar, grouped and wired\n');

%% 4. The summary tool prints what Engine.describe returns.
expected = gui.Engine.describe();
printed = evalc('tools(iSummary).ClickedCallback([], [])');
firstLine = extractBefore(expected + newline, newline);
assert(contains(printed, firstLine), ...
    'the summary tool did not print the calibration description');
assert(contains(printed, 'Microphone and scale'), ...
    'the summary tool printed a truncated description');
fprintf('PASS: summary tool prints Engine.describe\n');

fprintf('ALL PASS: smoke_test_calibration_wiki_summary_tools\n');
end

function m = glyph_mask_(name)
% The drawn pixels of one glyph, as a logical -- what two icons must not
% share if a toolbar is to be readable at a glance.
ic = stimgen.util.toolbar_icon(name);
m = ~isnan(ic(:,:,1));
end
