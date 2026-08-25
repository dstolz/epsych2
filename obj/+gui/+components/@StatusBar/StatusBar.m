classdef StatusBar < handle
% gui.components.StatusBar(parent, Name=Value)
% Footer status-label component for uifigure-based GUIs.
% Displays color-coded messages: green for info/success, red for errors.
% Double-clicking the label copies its current text to the clipboard.
%
% Properties:
%   Label         - The underlying uilabel (read-only after construction).
%   ErrorPatterns - Cell array of substrings (case-insensitive) that trigger
%                   the error color scheme.  Extend to add domain-specific terms.
%
% Usage:
%   sb = gui.components.StatusBar(fig);
%   sb = gui.components.StatusBar(fig, Position=[20 14 1340 34]);
%   sb = gui.components.StatusBar(panel, InitialText='Loading...');
%   sb.setStatus('File saved.');
%   sb.setStatus('Error: file not found');
%   sb.setStatus('Saved protocol.', 'Load another file to continue.');

    properties
        % Substrings (case-insensitive) that trigger the error color scheme.
        % Add domain-specific terms to extend the default list.
        ErrorPatterns (1,:) cell = { ...
            'error', ...
            'failed', ...
            'not found', ...
            'invalid', ...
            'mismatch', ...
            'cannot', ...
            'must ', ...
            'not accessible', ...
            'fix the ', ...
            'resolve the ', ...
            'outside bounds', ...
            'read-only'}
    end

    properties (SetAccess = protected)
        Label matlab.ui.control.Label  % The underlying status label.
    end

    properties (Access = private)
        Figure_        matlab.ui.Figure  % Ancestor figure; used for click detection.
        PriorClickFcn_ = []              % WindowButtonDownFcn saved at construction.
    end

    % -----------------------------------------------------------------------
    methods (Static)
        function s = getComponentSpec()
            % s = gui.components.StatusBar.getComponentSpec()
            % See gui.ComponentSpec.
            s = gui.ComponentSpec();
            s.type        = 'StatusBar';
            s.label       = 'Status Bar';
            s.category    = 'Add-ons';
            s.description = 'Footer status line, green for messages and red for errors';
            s.shape       = "parent";
            s.options     = gui.ComponentSpecOption('name','InitialText','inputType','text');
        end
    end

    methods

        function obj = StatusBar(parent, options)
        % gui.components.StatusBar(parent, Name=Value)
        % Construct a StatusBar and attach it to a figure or container.
        %
        % Parameters:
        %   parent      - matlab.ui.Figure or any ui container (panel, grid, etc.).
        %   Position    - [x y w h] label position in pixels.
        %                 Defaults to spanning the bottom of the parent.
        %   InitialText - Text shown before the first setStatus call (default: 'Ready').
            % Position is deliberately UNSIZED here. Declaring it (1,4) makes
            % [] an invalid default, and MATLAB validates a default the
            % moment it is used -- so the documented gui.components.StatusBar(parent)
            % form threw instead of spanning the bottom of its parent, and
            % every caller passed a Position it did not want. The size is
            % checked below, where an empty can be told from a bad one.
            arguments
                parent
                options.Position    double = []
                options.InitialText (1,:) char   = 'Ready'
            end
            assert(isempty(options.Position) || numel(options.Position) == 4, ...
                'gui:StatusBar:badPosition', ...
                'Position must be [x y w h], or empty to span the parent.');

            fig = ancestor(parent, 'matlab.ui.Figure');
            if isempty(fig)
                error('gui:StatusBar:noFigure', ...
                    'Parent must be or descend from a matlab.ui.Figure.');
            end
            obj.Figure_ = fig;

            if isempty(options.Position)
                w = max(parent.Position(3) - 40, 100);
                options.Position = [20, 14, w, 34];
            end

            obj.Label = uilabel(parent, ...
                'Text',                options.InitialText, ...
                'Position',            options.Position, ...
                'FontWeight',          'bold', ...
                'HorizontalAlignment', 'left', ...
                'Tooltip',             'Double-click to copy this message to the clipboard');
            obj.applyColors_(options.InitialText, '');

            % Chain onto any existing WindowButtonDownFcn.
            obj.PriorClickFcn_         = fig.WindowButtonDownFcn;
            fig.WindowButtonDownFcn    = @(~, ~) obj.onFigureButtonDown_();
        end

        % -------------------------------------------------------------------

        function setStatus(obj, message, nextStep)
        % setStatus(obj, message, nextStep)
        % Update the status label text and apply color coding.
        %
        % Parameters:
        %   message  - Primary status text.  Defaults to 'Ready' when empty.
        %   nextStep - Optional hint appended as "  Next: <nextStep>".
            arguments
                obj
                message  (1,:) char = 'Ready'
                nextStep (1,:) char = ''
            end

            message  = strtrim(message);
            nextStep = strtrim(nextStep);

            if isempty(message)
                message = 'Ready';
            end

            if isempty(nextStep)
                obj.Label.Text = message;
            else
                obj.Label.Text = sprintf('%s  Next: %s', message, nextStep);
            end

            obj.applyColors_(message, nextStep);
        end

        % -------------------------------------------------------------------

        function delete(obj)
        % Restore the figure's original WindowButtonDownFcn when destroyed.
            if ~isempty(obj.Figure_) && isvalid(obj.Figure_)
                obj.Figure_.WindowButtonDownFcn = obj.PriorClickFcn_;
            end
        end

    end % public methods

    % -----------------------------------------------------------------------
    methods (Access = private)

        function onFigureButtonDown_(obj)
        % Handle figure click: forward to any prior callback, then check for
        % a double-click on the label and copy its text to the clipboard.

            % Forward to any previously registered callback.
            if ~isempty(obj.PriorClickFcn_) && isa(obj.PriorClickFcn_, 'function_handle')
                obj.PriorClickFcn_(obj.Figure_, []);
            end

            if ~strcmp(obj.Figure_.SelectionType, 'open')
                return
            end

            if ~isvalid(obj.Label)
                return
            end

            % Hit-test: verify the click landed inside the label bounds.
            pt  = obj.Figure_.CurrentPoint;   % [x y] pixels from figure bottom-left
            pos = obj.Label.Position;          % [x y w h]
            if pt(1) < pos(1) || pt(1) > pos(1) + pos(3) || ...
               pt(2) < pos(2) || pt(2) > pos(2) + pos(4)
                return
            end

            clipboard('copy', obj.Label.Text);

            savedBg    = obj.Label.BackgroundColor;
            savedColor = obj.Label.FontColor;
            savedText  = obj.Label.Text;

            obj.Label.BackgroundColor = [0.72 0.96 0.72];
            obj.Label.FontColor       = [0.05 0.40 0.05];
            obj.Label.Text            = sprintf('\x2713  Copied to clipboard');

            t = timer( ...
                'StartDelay', 1.5, ...
                'TimerFcn',   @(t, ~) localRestoreLabel_(t, obj, savedBg, savedColor, savedText));
            start(t);
        end

        % -------------------------------------------------------------------

        function applyColors_(obj, message, nextStep)
        % Apply green (info) or red (error) styling based on message content.
            combined = lower(strtrim(char(join(string({message, nextStep}), ' '))));
            isError  = any(cellfun(@(p) contains(combined, p), obj.ErrorPatterns));
            if isError
                obj.Label.BackgroundColor = [1.00 0.90 0.90];
                obj.Label.FontColor       = [0.56 0.10 0.10];
            else
                obj.Label.BackgroundColor = [0.90 0.97 0.90];
                obj.Label.FontColor       = [0.12 0.34 0.18];
            end
        end

    end % private methods

end % classdef

% ---------------------------------------------------------------------------
function localRestoreLabel_(t, obj, bg, fg, txt)
% Restore the label's saved state after the clipboard-copy flash.
    stop(t);
    delete(t);
    if isvalid(obj) && isvalid(obj.Label)
        obj.Label.BackgroundColor = bg;
        obj.Label.FontColor       = fg;
        obj.Label.Text            = txt;
    end
end
