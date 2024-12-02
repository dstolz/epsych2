classdef Helper < handle

    properties
        AX  % COM.RPco_X || SynapseAPI
        RUNTIME
    end

    properties (SetAccess = private)

    end

    methods
        % Constructor
        function obj = Helper(AX)
            if nargin < 1, AX = []; end
            if ~isempty(AX)
                obj.AX = AX;
            end
        end

        function set.AX(obj,AX)
            assert(isempty(AX)||gui.Helper.isRPcox(AX)||gui.Helper.isSynapse(AX), ...
                'epsych:epGenericHelper:AX','AX must be COM.RPco_X or SynapseAPI')
            obj.AX = AX;
        end

        function v = readparamTags(obj,paramTags)

        end




        % function v = getParamVals(obj,params)
        %
        %     assert(obj.TDTactiveXisvalid(obj.AX), ...
        %         'gui.Helper:getParamVals','Invalid TDT control!');
        %     params = cellstr(params);
        %     N = numel(params);
        %     v = zeros(size(params),'single');
        %     for i = 1:N
        %         if obj.isSynapse(obj.AX)
        %             v(i) = single(obj.AX.getParameterValue(obj.RUNTIME.TDT.Module_{1},params{i}));
        %
        %         elseif gui.Helper.isRPcox(obj.AX)
        %             v(i) = single(obj.AX.GetTagVal(params{i}));
        %         end
        %     end
        % end

    end


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
                options.postColor (1,:)
            end

            if isempty(options.postColor)
                options.postColor = obj.BackgroundColor;
            end

            obj.BackgroundColor = newColor;

            t = timer('StartDelay', options.duration, 'TimerFcn', @(~,~) resetColor());
            start(t);

            function resetColor()
                obj.BackgroundColor = options.postColor;
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

