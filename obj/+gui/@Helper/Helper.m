classdef Helper < handle
    
    properties
        TDTActiveX  % COM.RPco_X || COM.TDevAcc_X
    end
    
    properties (SetAccess = private)
        
    end
    
    methods
        % Constructor
        function obj = Helper(TDTActiveX)
            if nargin < 1, TDTActiveX = []; end
            if ~isempty(TDTActiveX)
                obj.TDTActiveX = TDTActiveX;
            end
        end
        
        function set.TDTActiveX(obj,TDTActiveX)
            assert(isempty(TDTActiveX)||gui.Helper.isRPcox(TDTActiveX)||gui.Helper.isOpenEx(TDTActiveX), ...
                'epsych:epGenericHelper:TDTActiveX','TDTActiveX must be COM.RPco_X or COM.TDevAcc_X')
            obj.TDTActiveX = TDTActiveX;
        end
        
        function v = readparamTags(obj,paramTags)
            
        end
    end
    
    
    methods (Static)
        function r = isRPcox(TDTActiveX)
            r = isa(TDTActiveX,'COM.RPco_x');
        end
        function x = isOpenEx(TDTActiveX)
            x = isa(TDTActiveX,'COM.TDevAcc_X');
        end
        function v = TDTactiveXisvalid(TDTActiveX)
            v = gui.Helper.isRPcox(TDTActiveX) || gui.Helper.isOpenEx(TDTActiveX);
        end
        
        function v = getParamVals(TDTActiveX,params)
            assert(gui.Helper.TDTactiveXisvalid(TDTActiveX), ...
                'gui.Helper:getParamVals','Invalid TDT ActiveX control!');
            params = cellstr(params);
            N = numel(params);
            v = zeros(size(params),'single');
            for i = 1:N
                if gui.Helper.isOpenEx(TDTActiveX)
                    v(i) = single(TDTActiveX.GetTargetVal(params{i}));
                    
                elseif gui.Helper.isRPcox(TDTActiveX)
                    v(i) = single(TDTActiveX.GetTagVal(params{i}));
                end
            end
        end
        
        
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
        
        
        function v = get_current_trial_parameter_value(parameter)
            global RUNTIME
            
            ntidx = RUNTIME.TRIALS.NextTrialID;
            pind = ismember(RUNTIME.TRIALS.writeparams,parameter);
            
            v = nan;
            if any(pind) 
                v = RUNTIME.TRIALS.trials{ntidx,pind};
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

