classdef (Sealed) Helper < handle
    % gui.Helper
    % Small static GUI utilities (highlighting, timed color changes, metrics).
    %
    % Methods (static):
    %   update_highlight     - Update alternating row colors + highlight rows.
    %   timed_color_change   - Temporarily set a color-like property then reset.
    %   dprime2AFC, criterion, percent_correct - Common SDT helpers.



    methods (Static)
    
        function update_highlight(tableH,row,highlightColor)
            if nargin < 3 || isempty(highlightColor), highlightColor = [0.2 0.6 1]; end
            n = size(tableH.Data,1);
            c = repmat([1 1 1; 0.9 0.9 0.9],ceil(n/2),1);
            c(n+1:end,:) = [];
            if ~isempty(row)
                c(row,:) = repmat(highlightColor,numel(row),1);
            end
            tableH.BackgroundColor = c;
        end




        function timed_color_change(obj, newColor, options)
            arguments
                obj
                newColor
                options.duration (1,1) double = 1 % second
                options.postColor (1,:) = 'default'
            end

            if isprop(obj,'BackgroundColor')
                SF = 'BackgroundColor';
            elseif isprop(obj,'Color')
                SF = 'Color';
            elseif isprop(obj,'FontColor')
                SF = 'FontColor';
            else
                %????
                return
            end

            if isequal(options.postColor,'default')
                options.postColor = obj.(SF);
            end

            obj.(SF) = newColor;

            t = timer('StartDelay', options.duration, 'TimerFcn', @(~,~) resetColor());
            start(t);

            function resetColor()
                if ~isvarname('SF'), return; end %????
                obj.(SF) = options.postColor;
                stop(t);
                delete(t);
            end
        end




        % The three below forward to psychophysics.Metrics, which owns the
        % signal-detection arithmetic. They stay because gui.Helper is a
        % mixin that lab BehaviorGUIs outside this repository inherit, and
        % removing a superclass method breaks those silently; the hard-coded
        % [0.01 0.99] bounds are preserved for the same reason. New code
        % should call psychophysics.Metrics directly, where the correction is
        % named rather than implied.

        function d = dprime2AFC(HR)
            d = psychophysics.Metrics.dprime2AFC(HR, Correction="clamp", Bounds=[0.01 0.99]);
        end

        function c = criterion(HR,FR)
            c = psychophysics.Metrics.criterion(HR, FR, Correction="clamp", Bounds=[0.01 0.99]);
        end

        function pc = percent_correct(HR,FR)
            pc = psychophysics.Metrics.percentCorrect(HR, FR);
        end


    end
end

