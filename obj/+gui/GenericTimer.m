classdef GenericTimer < handle
    
    properties
        Period (1,1) double {mustBeFinite,mustBePositive} = 0.5;
        
        StartFcn    (1,1) %function_handle
        TimerFcn    (1,1) %function_handle
        ErrorFcn    (1,1) %function_handle
        StopFcn     (1,1) %function_handle
        
        Timer   (1,1)   %Timer
    end
    
    properties (SetAccess = private)
        HFig    (1,1)   %matlab.ui.Figure
        Name    (1,:)   char
    end
    
    methods
        % Constructor
        function obj = GenericTimer(hFig,timerName)
            narginchk(1,2);
            
            if nargin < 2 || isempty(timerName), timerName = hFig.Tag; end

            obj.Name = timerName;
            obj.HFig = hFig;
            
            T = timerfind('Name',timerName);
            if isempty(T)
                obj.Timer = timer('name',timerName);
                obj.Timer.Tag = 'GUIGenericTimer';
                obj.Timer.BusyMode = 'drop';
                obj.Timer.ExecutionMode = 'fixedRate';
                obj.Timer.TasksToExecute = inf;
            else
                obj.Timer = T;
            end
        end
        
        % Destructor
        function delete(obj)
            try
                stop(obj);
                delete(obj.Timer);
            end
            clear obj
        end
        
        % % overload start function to make sure the timer gets updated
        % % values and then actually started
        function start(obj)
            start(obj.Timer);
        end
        %     f = obj.HFig;
        %     % T = timerfind('Name',obj.Name);
        %     % if ~isempty(T)
        %     %     try delete(T); end
        %     % end
        %     % T = timer('Name',obj.Name);
        %     T.Tag = 'GUIGenericTimer';
        %     T.BusyMode = 'drop';
        %     T.ExecutionMode = 'fixedRate';
        %     T.TasksToExecute = inf;
        %     T.Period = obj.Period;
        % 
        %     if isempty(obj.TimerFcn)
        %         me = MException('EPsych:ep_GenericGUITimer:invalidFunctionHandle', ...
        %             'TimerFcn must not be empty!');
        %         throw(me)
        %     end
        % 
        %     T.TimerFcn = {obj.TimerFcn,f};
        % 
        %     if isequal(obj.StartFcn,0)
        %         T.StartFcn = '';
        %     else
        %         T.StartFcn = {obj.StartFcn,f};
        %     end
        % 
        %     if isequal(obj.StopFcn,0)
        %         T.StopFcn = '';
        %     else
        %         T.StopFcn  = {obj.StopFcn,f};
        %     end
        % 
        %     if isequal(obj.ErrorFcn,0)
        %         T.ErrorFcn = '';
        %     else
        %         T.ErrorFcn = {obj.ErrorFcn,f};
        %     end
        % 
        %     if isequal(T.Running,'off'), start(T); end
        % 
        %     obj.Timer = T;
        % end
        
        function stop(obj)
            if ~isempty(obj.Timer) && isvalid(obj.Timer) && isequal(obj.Timer.Running,'on')
                stop(obj.Timer); 
            end
        end
        
    end
    
    
end