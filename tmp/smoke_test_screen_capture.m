% smoke_test_screen_capture.m
% Headless check of gui.ScreenCapture and gui.BehaviorGUI.addScreenCapture.
%
% Asserts the camera glyph exists and reaches the uibutton's Icon property, a
% click puts a bitmap of the whole window on the Windows clipboard at the
% window's own size, the button confirms and then restores itself, and the
% BehaviorGUI helper registers the component so teardown takes its timer with
% it. No hardware required.
%
% NOTE: this test writes to the system clipboard, which is what the component
% does; whatever was on it is replaced.
%
% Run headless, from the repository root:
%   matlab -batch "run('tmp/smoke_test_screen_capture.m')"

% Bootstrap: `matlab -batch` starts with whatever path the user profile leaves
% behind, and this file lives in tmp/, which is only on the path once
% epsych_startup has run.
if exist('gui.ScreenCapture', 'class') ~= 8
    run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'epsych_startup.m'));
end

fprintf('\n=== ScreenCapture Smoke Test ===\n\n');
results = {};

fig = [];
behaviorGUI = [];

%% 1. The camera glyph is a well-formed toolbar icon
try
    icon = gui.toolbarIcon("camera");
    results(end+1,:) = check('Camera icon is 16x16x3', isequal(size(icon), [16 16 3]));
    results(end+1,:) = check('Camera icon has transparent pixels', any(isnan(icon(:))));
    opaque = icon(:,:,1);
    results(end+1,:) = check('Camera icon has opaque pixels', any(~isnan(opaque(:))));
    results(end+1,:) = check('Camera icon values are in [0,1]', ...
        all(icon(~isnan(icon)) >= 0 & icon(~isnan(icon)) <= 1));
catch ME
    results(end+1,:) = check(['Camera icon: ' ME.message], false);
end

%% 2. Standalone: the button carries the icon and copies the window
try
    fig = uifigure('Visible', 'off', 'Name', 'ScreenCapture Smoke', ...
        'Position', [100 100 420 260]);
    uilabel(fig, 'Position', [20 200 380 30], 'Text', 'Window content', 'FontSize', 18);

    sc = gui.ScreenCapture(fig, Tooltip = 'Copy me', FlashDuration = 0.4);

    results(end+1,:) = check('Button is a uibutton', ...
        isa(sc.Button, 'matlab.ui.control.Button'));
    results(end+1,:) = check('Icon property holds the camera array', ...
        isequal(size(sc.Button.Icon), [16 16 3]));
    results(end+1,:) = check('Button is icon-only by default', isempty(sc.Button.Text));
    results(end+1,:) = check('Target defaults to the parent figure', isequal(sc.Target, fig));

    % Click it exactly as an operator would.
    ok = sc.Button.ButtonPushedFcn;
    ok(sc.Button, []);

    results(end+1,:) = check('Clipboard holds an image', ...
        System.Windows.Forms.Clipboard.ContainsImage());

    img = System.Windows.Forms.Clipboard.GetImage();
    w = double(img.Width);
    h = double(img.Height);
    img.Dispose();
    fprintf('  clipboard image: %dx%d px (figure %dx%d)\n', ...
        w, h, fig.Position(3), fig.Position(4));
    results(end+1,:) = check('Clipboard image is at least the figure size', ...
        w >= fig.Position(3) && h >= fig.Position(4));

    % The confirmation: a built-in glyph now, the camera again shortly.
    results(end+1,:) = check('Button flashes a confirmation icon', ...
        ischar(sc.Button.Icon) && strcmp(sc.Button.Icon, 'success'));
    results(end+1,:) = check('Tooltip reports the copy', ...
        contains(sc.Button.Tooltip, 'Copied'));

    t0 = tic;
    while toc(t0) < 5 && ~isnumeric(sc.Button.Icon)
        pause(0.1)   % let the one-shot restore timer fire
    end
    results(end+1,:) = check('Camera icon is restored', isequal(size(sc.Button.Icon), [16 16 3]));
    results(end+1,:) = check('Tooltip is restored', strcmp(sc.Button.Tooltip, 'Copy me'));

    % A dead target must be reported, not thrown.
    sc.Target = [];
    results(end+1,:) = check('Missing target returns false instead of throwing', ...
        ~sc.copyToClipboard());

    % Capture the handle first: delete(sc) invalidates sc itself.
    btn = sc.Button;
    delete(sc)
    results(end+1,:) = check('delete removes the button', ~isvalid(btn));
    results(end+1,:) = check('delete leaves no flash timer behind', ...
        isempty(timerfindall('Name', 'ScreenCaptureFlash')));
    delete(fig)
catch ME
    results(end+1,:) = check(['Standalone: ' ME.message], false);
end

%% 3. In a BehaviorGUI: registered, so teardown takes it along
try
    RUNTIME = epsych.Runtime;
    behaviorGUI = ScreenCaptureSmokeGUI(RUNTIME);

    btn = findall(behaviorGUI.h_figure, 'Type', 'uibutton', '-and', 'Text', 'Screenshot');
    results(end+1,:) = check('addScreenCapture made a labeled button', isscalar(btn));
    results(end+1,:) = check('Helper button carries the camera icon', ...
        isequal(size(btn(1).Icon), [16 16 3]));
    results(end+1,:) = check('Helper targets the GUI figure', ...
        isequal(behaviorGUI.Capture.Target, behaviorGUI.h_figure));

    capture = behaviorGUI.Capture;
    results(end+1,:) = check('Capture through the helper succeeds', capture.copyToClipboard());

    delete(behaviorGUI)
    results(end+1,:) = check('Component registered for teardown', ~isvalid(capture));
    results(end+1,:) = check('No flash timer survives teardown', ...
        isempty(timerfindall('Name', 'ScreenCaptureFlash')));
    delete(RUNTIME)
catch ME
    results(end+1,:) = check(['BehaviorGUI: ' ME.message], false);
end

%% Summary
if ~isempty(behaviorGUI) && isvalid(behaviorGUI), delete(behaviorGUI); end
if ~isempty(fig) && isvalid(fig), delete(fig); end

labels = results(:,1);
passed = cell2mat(results(:,2));
fprintf('\n--- Results ---\n');
for i = 1:numel(labels)
    if passed(i)
        fprintf('  PASS  %s\n', labels{i});
    else
        fprintf('  FAIL  %s\n', labels{i});
    end
end
fprintf('\n%d passed, %d failed, %d total\n\n', ...
    sum(passed), sum(~passed), numel(passed));

if any(~passed)
    error('smoke_test_screen_capture:Failed', '%d smoke test(s) failed.', sum(~passed));
end


function row = check(label, tf)
% row = check(label, tf)
% Record one assertion as a {label, logical} row.
row = {label, logical(tf)};
end
