classdef PsychPlot < handle
    
    properties
        ax       (1,1)
        
        
        psychObj % psychophysics...
        
        % must jive with obj.ValidPlotTypes
        PlotType    (1,:) char {mustBeMember(PlotType,{'DPrime','Hit_Rate','FA_Rate','Bias'})} = 'DPrime';
        
        LineColor   (:,:) double {mustBeNonnegative,mustBeLessThanOrEqual(LineColor,1)}   = [.2 .6 1; 1 .6 .2];
        MarkerColor (:,:) double {mustBeNonnegative,mustBeLessThanOrEqual(MarkerColor,1)} = [0 .4 .8; .8 .4 0];


        logx    (1,1) logical = false
    end
    
    properties (SetAccess = private)
        LineH
        ScatterH
        TextH

        hl_NewData
    end
    
    
    properties (Dependent)
        ParameterName
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
            
            obj.psychObj = pObj;
            obj.setup_xaxis_label;
            obj.setup_yaxis_label;

            obj.hl_NewData = listener(pObj.Helper,'NewData',@obj.update_plot);
        end

        function delete(obj)
            % Destructor: cleans up the listener.
            try
                delete(obj.hl_NewData);
            end
        end
        

        function n = get.ParameterName(obj)
            n = obj.psychObj.Parameter.Name;
        end
        



        function h = get.LineH(obj)
            h = findobj(obj.ax,'type','line');
        end

       
        
        function update_plot(obj,src,event)
            % although data is updated in src and event, just use the obj.psychObj
            vprintf(4,'Updating PsychPlot')
            if ~isvalid(obj.ax), return; end

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

                line(obj.ax,[-1 1]*1e6,[1 1],Color = 'k', ...
                    AffectAutoLimits = 'off', ...
                    HandleVisibility = 'off')

                grid(obj.ax,'on');
                box(obj.ax,'on');
            end

            try
                nStim = obj.psychObj.countUniqueValues;
                if isempty(nStim), return; end
                X = obj.psychObj.uniqueValues;
                Y = obj.psychObj.(obj.PlotType);
                %C = obj.psychObj.Trial_Count;
                
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


            if obj.logx
                obj.ax.XScale = 'log';
            end


            obj.setup_xaxis_label;
            obj.setup_yaxis_label;
            

            sstr = sprintf('# Stimulus Trials = %d',obj.psychObj.trialCount);
            subtitle(obj.ax,sstr);

            tstr = sprintf('%s [%d]', ...
                obj.psychObj.TRIALS.Subject.Name, ...
                obj.psychObj.TRIALS.BoxID);

            title(obj.ax,tstr);

            obj.ax.TitleHorizontalAlignment ='right';
        end
        
        function update_parameter(obj,hObj,event)
            % TO DO: support multiple parameters at a time
            switch hObj.Tag
                case 'abscissa'
                    i = find(ismember(obj.psychObj.ValidParameters,obj.psychObj.ParameterName));
                    [sel,ok] = listdlg('ListString',obj.psychObj.ValidParameters, ...
                        'SelectionMode','single', ...
                        'InitialValue',i,'Name','Plot', ...
                        'PromptString','Select Independent Variable:', ...
                        'ListSize',[180 150]);
                    if ~ok, return; end
                    obj.psychObj.ParameterName = obj.psychObj.ValidParameters{sel};
                    try
                        delete(obj.TextH(length(obj.psychObj.ParameterValues)+1:end));
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
            x = xlabel(obj.ax,obj.ParameterName,'Tag','abscissa','Interpreter','none');
            x.ButtonDownFcn = @obj.update_parameter;
        end
        
        function setup_yaxis_label(obj)
            y = ylabel(obj.ax,obj.PlotType,'Tag','ordinate','Interpreter','none');
            y.ButtonDownFcn = @obj.update_parameter;
        end
        
        function set.psychObj(obj,pobj)
            assert(epsych.Helper.valid_psych_obj(pobj), ...
                'gui.History:set.PsychophysiccsObj', ...
                'psychObj must be from the toolbox "psychophysics"');
            obj.psychObj = pobj;
            obj.update_plot;
        end
    end
    
end