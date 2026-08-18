classdef ScreenCapture < handle
    % gui.ScreenCapture(parent, options)
    % Camera button that puts a picture of the whole window on the clipboard.
    %
    % One click captures the entire figure — controls, plots, panels and all —
    % and copies it to the system clipboard, ready to paste into an electronic
    % lab notebook, a slide, or a message to whoever is asking what the rig is
    % doing. Nothing is written to disk that outlives the click.
    %
    % The capture goes through exportapp because it is the only one that
    % includes UI components: print and copygraphics render the axes alone,
    % which is not what an operator means by a picture of the window. exportapp
    % renders offscreen, so an obscured or partly offscreen window still copies
    % correctly, and MATLAB's own clipboard() is text-only, so the image reaches
    % the clipboard through .NET. That last step is Windows-only; elsewhere the
    % button falls back to copygraphics and says so in the log.
    %
    % Properties (settable):
    %   Target        - Figure captured on click (default: the button's own figure).
    %   FlashDuration - Seconds the confirmation icon stays up (default: 1.5).
    %
    % Properties (read-only):
    %   Button        - The underlying uibutton handle.
    %
    % Methods:
    %   copyToClipboard - Capture Target and copy it; also callable without a click.
    %   delete          - Stop the confirmation timer and remove the button.
    %
    % Usage:
    %   gui.ScreenCapture(fig);                        % icon-only button
    %   gui.ScreenCapture(g, Text='Screenshot');       % in a grid cell, labeled
    %   sc = gui.ScreenCapture(fig, Target=otherFig);  % capture a different window
    %   sc.copyToClipboard();                          % from a script or a menu
    %
    % In a gui.BehaviorGUI subclass use obj.addScreenCapture(parent), which
    % registers the component for teardown.
    %
    % Documentation: documentation/gui/gui_ScreenCapture.md
    % See also: gui.BehaviorGUI, gui.toolbarIcon, exportapp

    properties
        Target                  % Figure captured on click
        FlashDuration (1,1) double {mustBePositive, mustBeFinite} = 1.5  % Confirmation icon dwell (s)
    end

    properties (SetAccess = private)
        Button                  % uibutton handle
    end

    properties (Access = private)
        Flash_    timer         % One-shot timer restoring the camera icon
        Icon_                   % Camera glyph, kept for the restore
        Tooltip_  (1,:) char    % Tooltip, kept for the restore
    end

    methods

        function obj = ScreenCapture(parent, options)
            % gui.ScreenCapture(parent, options)
            % Create the capture button in any UI container.
            %
            % Parameters:
            %   parent        - UI container (uifigure, uipanel, uigridlayout cell, ...).
            %   Target        - Figure to capture (default: parent's figure).
            %   Text          - Button label (default: '', an icon-only button).
            %   Tooltip       - Hover text (default: 'Copy this window to the clipboard').
            %   FontSize      - Label font size in points (default: 12).
            %   FlashDuration - Seconds the confirmation icon stays up (default: 1.5).
            arguments
                parent (1,1)
                options.Target = []
                options.Text          (1,:) char = ''
                options.Tooltip       (1,:) char = 'Copy this window to the clipboard'
                options.FontSize      (1,1) double {mustBePositive, mustBeFinite} = 12
                options.FlashDuration (1,1) double {mustBePositive, mustBeFinite} = 1.5
            end

            obj.Target = options.Target;
            if isempty(obj.Target)
                obj.Target = ancestor(parent, 'figure');
            end
            obj.FlashDuration = options.FlashDuration;
            obj.Tooltip_ = options.Tooltip;

            % gui.toolbarIcon rather than a built-in name: uibutton offers only
            % success, error, warning and info, none of which reads as a camera.
            obj.Icon_ = gui.toolbarIcon("camera");

            obj.Button = uibutton(parent, ...
                'Text',            options.Text, ...
                'Icon',            obj.Icon_, ...
                'Tooltip',         obj.Tooltip_, ...
                'FontSize',        options.FontSize, ...
                'ButtonPushedFcn', @(~,~) obj.copyToClipboard());
        end

        % -----------------------------------------------------------------------

        function tf = copyToClipboard(obj)
            % tf = obj.copyToClipboard()
            % Capture Target and put the image on the system clipboard. Returns
            % true on success. Never throws: a failed screenshot must not take
            % the experiment GUI with it, so the exception is logged and the
            % button flashes an error instead.
            tf = false;

            if isempty(obj.Target) || ~all(isvalid(obj.Target))
                vprintf(0, 1, 'gui.ScreenCapture: no figure to capture')
                obj.flash_('error', 'Nothing to capture')
                return
            end

            % A temporary PNG is the handoff between the two halves: exportapp
            % only writes files, and .NET only reads images.
            tmp = [tempname '.png'];
            cleaner = onCleanup(@() gui.ScreenCapture.deleteQuietly_(tmp));

            try
                if ispc
                    exportapp(obj.Target, tmp);
                    gui.ScreenCapture.loadAssemblies_();
                    bmp = System.Drawing.Bitmap(tmp);
                    err = [];
                    try
                        % SetImage copies the pixels into the clipboard, so the
                        % bitmap -- which holds the PNG open -- can be released
                        % as soon as it returns, and must be before the temp
                        % file can be deleted.
                        System.Windows.Forms.Clipboard.SetImage(bmp);
                    catch err
                    end
                    bmp.Dispose();
                    if ~isempty(err), rethrow(err); end
                else
                    copygraphics(obj.Target, ContentType = 'image');
                    vprintf(1, ['gui.ScreenCapture: copied the plots only; the ' ...
                        'full window, controls included, is a Windows-only copy'])
                end

                tf = true;
                vprintf(1, sprintf('gui.ScreenCapture: copied "%s" to the clipboard', ...
                    obj.Target.Name))
                obj.flash_('success', 'Copied to the clipboard')

            catch ME
                vprintf(0, 1, ME)
                obj.flash_('error', sprintf('Copy failed: %s', ME.message))
            end
        end

        % -----------------------------------------------------------------------

        function delete(obj)
            % Destructor: stop the confirmation timer before removing the
            % button, or a pending restore would fire at a dead handle.
            obj.stopFlash_();
            try
                if ~isempty(obj.Button) && isvalid(obj.Button)
                    delete(obj.Button);
                end
            catch
            end
        end

    end

    methods (Access = private)

        function flash_(obj, state, tooltip)
            % flash_(obj, state, tooltip)
            % Swap the camera for a built-in success/error glyph long enough to
            % be seen, then put it back. The clipboard gives no feedback of its
            % own, so without this a click looks like nothing happened.
            if isempty(obj.Button) || ~isvalid(obj.Button), return, end

            obj.stopFlash_();
            obj.Button.Icon = state;
            obj.Button.Tooltip = tooltip;

            obj.Flash_ = timer( ...
                'Name',          'ScreenCaptureFlash', ...
                'ExecutionMode', 'singleShot', ...
                'StartDelay',    obj.FlashDuration, ...
                'TimerFcn',      @(~,~) obj.restore_());
            start(obj.Flash_);
        end

        function restore_(obj)
            % Put the camera icon and the original tooltip back.
            if ~isvalid(obj) || isempty(obj.Button) || ~isvalid(obj.Button), return, end
            obj.Button.Icon = obj.Icon_;
            obj.Button.Tooltip = obj.Tooltip_;
        end

        function stopFlash_(obj)
            try
                if ~isempty(obj.Flash_) && isvalid(obj.Flash_)
                    stop(obj.Flash_);
                    delete(obj.Flash_);
                end
            catch
            end
            obj.Flash_ = timer.empty;
        end

    end

    methods (Static, Access = private)

        function loadAssemblies_()
            % Load the .NET assemblies once per session; NET.addAssembly is
            % slow enough to be worth not repeating on every click.
            persistent loaded
            if ~isempty(loaded), return, end
            NET.addAssembly('System.Windows.Forms');
            NET.addAssembly('System.Drawing');
            loaded = true;
        end

        function deleteQuietly_(ffn)
            % Remove the handoff file; a leftover in tempdir is not worth an
            % error message on a path that has already reported its outcome.
            try
                if isfile(ffn), delete(ffn); end
            catch
            end
        end

    end

end
