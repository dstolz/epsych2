classdef (Sealed) Helper < handle



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




        function d = dprime2AFC(HR)
            HR = max(min(HR,.99),.01);
            d = sqrt(2)*norminv(HR);
        end

        function c = criterion(HR,FR)
            HR = max(min(HR,.99),.01);
            FR = max(min(FR,.99),.01);
            c = -1*(norminv(HR)+norminv(FR))./2;
        end

        function pc = percent_correct(HR,FR)
            pc = 0.5+(HR-FR)./2;
        end


    end
end

