classdef PsychPlot < handle
    
    properties
        ax       (1,1)
        
        ParameterName (1,:) char
        
        PsychophysicsObj % psychophysics...
        
        % must jive with obj.ValidPlotTypes
        PlotType    (1,:) char {mustBeMember(PlotType,{'DPrime','Hit_Rate','FA_Rate','Bias'})} = 'DPrime';
        
        LineColor   (:,:) double {mustBeNonnegative,mustBeLessThanOrEqual(LineColor,1)}   = [.2 .6 1; 1 .6 .2];
        MarkerColor (:,:) double {mustBeNonnegative,mustBeLessThanOrEqual(MarkerColor,1)} = [0 .4 .8; .8 .4 0];
    end
    
    properties (SetAccess = private)
        LineH
        ScatterH
        TextH

        hl_NewData
    end
    
    
    properties (Constant)
        ValidPlotTypes = {'DPrime','Hit_Rate','FA_Rate','Bias'};
    end
    
    

    
    methods
        function obj = PsychPlot(pObj,ax)
            % obj = PsychPlot(pObj,ax)
            %
            % pObj      psychophysics object (ex: psychophysics.Detection)
            % ax        Target axes (default = gca)

            if nargin < 2 || isempty(ax), ax = gca; end
            
            obj.ax = ax;
            
            obj.PsychophysicsObj = pObj;
            obj.setup_xaxis_label;
            obj.setup_yaxis_label;

            obj.hl_NewData = listener(pObj.Helper,'NewData',@obj.update_plot);

        end

        function delete(obj)
            try
                delete(obj.hl_NewData);
            end
        end
        
        

        function set.ParameterName(obj,name)
            ind = ismember(obj.ValidParameters,name);
            assert(any(ind),'gui.PsychPlot:set.ParameterName','Invalid parameter name: %s',name);
            obj.ParameterName = name;
            obj.update_plot;
        end
        



        function h = get.LineH(obj)
            h = findobj(obj.ax,'type','line');
        end

       
        
        function update_plot(obj,src,event)
            % although data is updated in src and event, just use the obj.PsychophysicsObj
            lh = obj.LineH;
            sh = obj.ScatterH;
            if isempty(lh) || isempty(sh) || ~isvalid(lh) || ~isvalid(sh)
                sh = scatter(nan,nan,100,'filled','Parent',obj.ax,'Marker','s');
%                     'MarkerFaceColor','flat');
                
                lh = line(obj.ax,nan,nan,'Marker','none', ...
                    'AlignVertexCenters','on', ...
                    'LineWidth',2,'Color',obj.LineColor(1,:));
                
                obj.LineH = lh;
                obj.ScatterH = sh;

                grid(obj.ax,'on');
            end

            try
                X = obj.PsychophysicsObj.ParameterValues;
                Y = obj.PsychophysicsObj.(obj.PlotType);
                %C = obj.PsychophysicsObj.Trial_Count;
                nStim = obj.PsychophysicsObj.Stim_Count;
                nCatch = sum(obj.PsychophysicsObj.Catch_Count);
            catch me
                return
            end

            set(lh,'XData',X,'YData',Y);            
            set(sh,'XData',X,'YData',Y);

            ya = min(0,Y);
            ylim_ = [min(ya) 0.5+max(Y,[],'omitnan')];
            if isnan(ylim_(2)), ylim_(2) = 1; end
            set(obj.ax,'ylim',ylim_)
            

            sh.SizeData = nStim*10+1;
            c = repmat(obj.MarkerColor(1,:),length(X),1);
            sh.CData = c;
            
            uistack(sh,'top');
            
            % for i = 1:length(X)
            %     if i > size(C,1), break; end
            %     if nnz(C(i,:)) == 0, continue; end
            %     obj.TextH(i) = text(obj.ax,X(i),Y(i),num2str(C(i,:),'%d/%d'), ...
            %         'HorizontalAlignment','center','VerticalAlignment','middle', ...
            %         'Color',[0 0 0],'FontSize',9);
            % end
            
            obj.setup_xaxis_label;
            obj.setup_yaxis_label;
            

            tstr = sprintf('%s [%d] - Trial %d', ...
                obj.PsychophysicsObj.SUBJECT.Name, ...
                obj.PsychophysicsObj.BoxID, ...
                obj.PsychophysicsObj.Trial_Index);
            
            title(obj.ax,tstr);
        end
        
        function update_parameter(obj,hObj,event)
            % TO DO: support multiple parameters at a time
            switch hObj.Tag
                case 'abscissa'
                    i = find(ismember(obj.PsychophysicsObj.ValidParameters,obj.PsychophysicsObj.ParameterName));
                    [sel,ok] = listdlg('ListString',obj.PsychophysicsObj.ValidParameters, ...
                        'SelectionMode','single', ...
                        'InitialValue',i,'Name','Plot', ...
                        'PromptString','Select Independent Variable:', ...
                        'ListSize',[180 150]);
                    if ~ok, return; end
                    obj.PsychophysicsObj.ParameterName = obj.PsychophysicsObj.ValidParameters{sel};
                    try
                        delete(obj.TextH(length(obj.PsychophysicsObj.ParameterValues)+1:end));
                    end
                    
                case 'ordinate'
                    i = find(ismember(obj.ValidPlotTypes,obj.PlotType));
                    [sel,ok] = listdlg('ListString',obj.ValidPlotTypes, ...
                        'SelectionMode','single', ...
                        'InitialValue',i,'Name','Plot', ...
                        'PromptString','Select Plot Type:', ...
                        'ListSize',[180 150]);
                    if ~ok, return; end
                    obj.PlotType = obj.ValidPlotTypes{sel};
                    
            end
            obj.update_plot;
        end
        
        
        function setup_xaxis_label(obj)
            x = xlabel(obj.ax,obj.PsychophysicsObj.ParameterName,'Tag','abscissa','Interpreter','none');
            x.ButtonDownFcn = @obj.update_parameter;
        end
        
        function setup_yaxis_label(obj)
            y = ylabel(obj.ax,obj.PlotType,'Tag','ordinate','Interpreter','none');
            y.ButtonDownFcn = @obj.update_parameter;
        end
        
        function set.PsychophysicsObj(obj,pobj)
            assert(epsych.Helper.valid_psych_obj(pobj), ...
                'gui.History:set.PsychophysiccsObj', ...
                'PsychophysicsObj must be from the toolbox "psychophysics"');
            obj.PsychophysicsObj = pobj;
            obj.update_plot;
        end
    end
    
end