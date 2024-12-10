classdef Software < hw.Interface


    properties (SetAccess = protected)
        HW
        % Trial (1,:) 

        Module

    end


    properties
        % TRIALS
    end

    properties (Constant)
        Type = 'Software'
    end

    properties (SetObservable,AbortSet)
        mode
    end

    


    methods (Access = protected)

        % setup hardware interface. this function must define obj.HW
        function setup_interface(obj,params,trial)
            obj.Module = hw.Module(0,'Software','Params',1);

            for i = 1:length(params)
                P = hw.Parameter(obj);
                P.Name = params{i};
                P.Value = trial{i};
                obj.Module.Parameters(end+1) = P;
                P.Module = obj.Module;
            end
        end

        % close interface
        function close_interface(obj)

        end

    end

    methods
        function obj = Software(params,trial)
            % obj.setup_interface(params,trial);
            obj.Module = hw.Module(obj,'Software','Params',1);
        end

        % trigger a hardware event
        function result = trigger(obj,name)

        end

        % set new value to one or more hardware parameters
        % returns TRUE if successful, FALSE otherwise
        function result = set_parameter(obj,name,value)
            % NOTE: ACTUAL VALUE IS UPDATED IN HW.PARAMETER
            if isa(name,'hw.Parameter')
                P = name;
            else
                P = obj.find_parameter(name);
            end


            for i = 1:length(P)
                % P(i).Value = value(i);
                vstr = P(i).ValueStr;
                vprintf(3,'Updated parameter: %s = %s',P(i).Name,vstr)
            end
            result = 1;
        end

        % read current value for one or more hardware parameters
        function value = get_parameter(obj,name,options)
            % CAN'T IMPLEMENT THIS FUNCTION SINCE IT LEADS TO INFINITE
            % RECURSION SINCE IT IS CALLED BY GET.VALUE() IN THE PARAMETER
            % CLASS. INSTEAD, THIS CLASS IS TREATED AS A SPECIAL CASE IN
            % GET.VALUE().
            % arguments
            %     obj
            %     name
            %     options.includeInvisible (1,1) logical = false
            %     options.silenceParamterNotFound (1,1) logical = false
            % end
            % 
            % if isa(name,'hw.Parameter')
            %     P = name;
            %     name = {P.Name};
            % else
            %     P = obj.find_parameter(name, ...
            %         includeInvisible = options.includeInvisible, ...
            %         silenceParamterNotFound=options.silenceParamterNotFound);
            % end
            
            % % **** LEADS TO INF RECURSTION ***
            % value = nan(size(P));
            % for i = 1:length(P)
            %     value(i) = P.Value;
            % end
            % 
            % 
            % % return in original order
            % [~,idx] = ismember(name,{P.Name});
            % value = value(idx);
            value = nan;
        end

        function mode_handler(obj,src,event)
            disp(event)
        end

    end


end