classdef StimGenInterface_Simple < handle% & gui.Helper

    properties
        StimPlayObj (1,1) stimgen.StimPlay
        DataPath = getpref('StimGenInterface','dataPath',fullfile('C:\Users\',getenv('USERNAME')));
        DataFilename = '';
    end

    properties (Hidden)
        isiAdjustment = 0.0405; % seconds; adjust ISI timing so that we're not between timer calls just before a trigger
    end

    properties (SetAccess = protected, SetObservable = true)
        parent
        handles
        sgTypes
        sgObj

        Calibration (1,1) stimgen.StimCalibration

        FileLoaded (1,1) string

        Timer

        firstTrigTime (1,1) double = 0; % time right before first stim
        lastTrigTime (1,1) double = 0; % time right after each stim

        TrigBufferID (1,1) double = 0; % alternates between 0 and 1 to indicate which buffer to trigger

        currentISI (1,1) double = 1; % current inter-stimulus interval (seconds)

        Fs (1,1) double {mustBePositive,mustBeFinite,mustBeNonNan} = 1

        % New: log of stimuli in order they were presented
        StimOrder (:,1) double = double.empty(0,1);      % index into StimPlayObj
        StimOrderTime (:,1) double = double.empty(0,1);  % timeSinceStart at trigger
        StimOrderTrial (:,1) double = double.empty(0,1); % TDT trial number at trigger
    end

    properties (Access = private)
        RUNTIME % espsych.Runtime
        PARAMS struct = struct() % struct of hw.Parameter objects, field names are valid parameter names
        els % event listeners
    end


    properties (Dependent)
        currentTrialNumber (1,1) double % current trial number from TDT
    end

    methods
        create(obj);


        function obj = StimGenInterface_Simple(RUNTIME,parent,ffn)

            if nargin > 0
                obj.RUNTIME = RUNTIME;

                p = RUNTIME.HW.all_parameters;
                for ip = p
                    obj.PARAMS.(ip.validName) = ip;
                end

                obj.Fs = RUNTIME.HW.HW.FS;
            end

            if nargin > 1, obj.parent = parent; end


            % get a list of available stimgen objects
            obj.sgTypes = stimgen.StimType.list;

            obj.sgObj = cellfun(@(a) stimgen.(a),obj.sgTypes,'uni',0);

            obj.create;

            if nargin > 1 && ~isempty(ffn)
                obj.load_config(ffn);
            end


            if nargout == 0, clear obj; end
        end





        function set.Calibration(obj,calObj)

            obj.Calibration = calObj;

            for i = 1:obj.StimPlayObj.NStimObj
                obj.StimPlayObj.StimObj(i).Calibration = calObj;
            end

        end


        function trigger_stim_playback(obj)
            if obj.StimPlayObj.Complete, return; end % flag to finish playback

            trigStr = sprintf('x_Trigger_%d',obj.TrigBufferID);

            obj.PARAMS.(trigStr).Value = 1; % trigger the buffer
            obj.lastTrigTime = obj.timeSinceStart; % time right after triggering stim playback
            % Note: Do not use the parameter `lastUpdated` time since we switch between them during playback

            obj.PARAMS.(trigStr).Value = 0;

            tdiff = obj.lastTrigTime - obj.currentISI;
            if isempty(tdiff), tdiff = 0; end
            vprintf(3,'trigger_stim_playback: TrigBufferID = %d; ITI diff = %.4f sec', ...
                obj.TrigBufferID,tdiff)

            %{
            if ~all(s)
                warning('StimGenInterface:trigger_stim_playback:RPvdsFail','Failed to trigger Stim buffer')
            end
            %}

            obj.currentISI = obj.StimPlayObj.get_isi;
            % obj.currentISI = obj.StimPlayObj.get_isi - tdiff;

            vprintf(3,'trigger_stim_playback: currentISI = %.3f s',obj.currentISI)
        end

        function update_buffer(obj)
            obj.TrigBufferID = mod(obj.currentTrialNumber,2);

            vprintf(3,'update_buffer START: TrigBufferID = %d', ...
                obj.TrigBufferID)

            t = tic;

            % make first and last samples 0 since RPvds circuit uses SerSource components
            buffer = [0, obj.StimPlayObj.Signal, 0];

            % write constructed Stim to RPvds circuit buffer
            nSamps = length(buffer);

            bid = obj.TrigBufferID;

            try
                obj.PARAMS.("BufferSize_"+string(bid)).Value = nSamps;
                obj.PARAMS.("BufferData_"+string(bid)).Value = buffer;
            catch me
                vprintf(0,1,'StimGenInterface:update_buffer:RPvdsFail','Failed to write Stim buffer')
                rethrow(me)
            end

            vprintf(4,'update_buffer END:   TrigBufferID = %d; took %.2f seconds',obj.TrigBufferID, toc(t))
        end







        function timer_startfcn(obj,src,event)
            % reset reps for StimPlay objects
            obj.StimPlayObj.reset;

            obj.update_isi;


            obj.StimPlayObj.increment; % select the first idx

            obj.update_buffer; % update the buffer with the first stimulus

            obj.firstTrigTime = now;
            obj.lastTrigTime = 0; % initialize time right before triggering stim playback
        end


        function timer_runtimefcn(obj,src,event)

            if obj.StimPlayObj.Complete, return; end % flag to finish playback

            isi = obj.currentISI;

            % wait until ISI has elapsed
            if obj.timeSinceStart - obj.lastTrigTime - isi < src.Period - obj.isiAdjustment
                return
            end


            % hold the computer hostage until ISI has expired
            %while obj.timeSinceStart - obj.lastTrigTime + obj.isiAdjustment < isi, end
            while obj.timeSinceStart - obj.lastTrigTime < isi, end


            obj.trigger_stim_playback; % trigger playback of the obj.nextSPIdx buffer

            obj.StimPlayObj.increment; % increment the StimPlay object

            if obj.StimPlayObj.Complete, return; end % flag indicating session is complete

            obj.update_buffer; % update the non-triggered buffer
        end

        function timer_stopfcn(obj,src,event)
            % save stimulus order log when playback stops
            try
                obj.save_stim_order();
            catch me
                vprintf(0,'StimGenInterface:timer_stopfcn','Failed to save stimulus order: %s',me.message);
            end

            h = obj.handles;
            h.RunStopButton.Text = 'Run';
        end

        function playback_control(obj,src,event)

            c = src.Text;

            switch lower(c)

                case 'run'
                    vprintf(3,'Module sampling rate = %.3f Hz',obj.Fs);
                    
                    obj.StimPlayObj.Fs = obj.Fs;
                    obj.StimPlayObj.update_signal;




                    if isempty(obj.DataFilename)
                        obj.DataFilename = sprintf('SGIData_%s.mat',datestr(now,30));
                    end



                    t = timerfindall('Tag','StimGenInterfaceTimer');
                    if ~isempty(t)
                        stop(t);
                        delete(t);
                    end
                    t = timer('Tag','StimGenInterfaceTimer', ...
                        'Period',0.005, ...
                        'ExecutionMode', 'fixedRate',...
                        'BusyMode', 'drop', ...
                        'StartFcn',@obj.timer_startfcn, ...
                        'TimerFcn',@obj.timer_runtimefcn, ...
                        'StopFcn', @obj.timer_stopfcn);

                    obj.Timer = t;

                    src.Text = 'Stop';

                    start(t);

                case 'stop'

                    stop(obj.Timer);
                    delete(obj.Timer);

                    src.Text = 'Run';

                case 'pause'

            end

        end


        function n = get.currentTrialNumber(obj)
            n = obj.PARAMS.TrialNumber.Value;
        end

        function stimtype_changed(obj,src,event)
            vprintf(4,'Stim Type Changed')
            t = src.SelectedTab.Tag;
            i = ismember(obj.sgTypes,t);
            so = obj.sgObj{i};

            obj.StimPlayObj.StimObj = so;
            so.update_signal();

        end



        function update_isi(obj,src,event)
            h = obj.handles;
            v = h.ISI.Value;
            v = str2num(v);
            v = sort(v(:)');
            try
                assert(numel(v) <= 2 & numel(v) >= 1, 'Invalid entry for ISI. Must be a scalar value or a 1x2 range for randomization.')
                src.Value = mat2str(v);
                h.StimPlayObj.ISI = v;
            catch me
                uialert(obj.parent,me.message,'InvalidEntry','modal',true)
                src.Value = event.PreviousValue;
            end
        end

        function play_current_stim_audio(obj,src,event)
            h = obj.handles.PlayStimAudio;

            vprintf(1,'Playing current stimulus audio...');
            c = h.BackgroundColor;
            h.BackgroundColor = [.2 1 .2];
            drawnow
            play(obj.StimPlayObj.CurrentStimObj);
            h.BackgroundColor = c;
        end

        function update_signal_plot(obj,src,event)
            % TO DO: add in inter trial interval period
            vprintf(4,'Updating signal plot...');

            so = obj.StimPlayObj.CurrentStimObj;

            h = obj.handles.SignalPlotLine;
            h.XData = so.Time;
            h.YData = so.Signal;

            yline(obj.handles.SignalPlotAx,0,'-k');
            ylim(obj.handles.SignalPlotAx,[-1.05 1.05]*max(abs(so.Signal)))
        end





        function update_samplerate(obj,src,event)
            vprintf(3,'Updating sample rate to %.3f Hz',event.Value);
            obj.StimPlayObj.Fs = event.Value;
        end

        function load_config(obj,ffn)

            if nargin < 2 || isempty(ffn)
                pn = getpref('StimGenInterface','path',cd);
                [fn,pn] = uigetfile({'*.sgi','StimGenInterface Config (*.sgi)'},pn);
                if isequal(fn,0), return; end

                ffn = fullfile(pn,fn);

                setpref('StimGenInterface','path',pn);
            end

            f = ancestor(obj.parent,'figure');

            figure(f);

            warning('off','MATLAB:class:LoadInvalidDefaultElement');
            vprintf(2,'Loading StimGenInterface configuration from: "%s"',ffn);
            load(ffn,'SGI','-mat');
            warning('on','MATLAB:class:LoadInvalidDefaultElement');

            obj.StimPlayObj = SGI.StimPlayObj;
            obj.Calibration = SGI.Calibration;


            % TO DO: Select correct loaded stim object

            vprintf(2,'Loaded configuration successfully.');

        end


        function save_config(obj,ffn)

            if nargin < 2 || isempty(ffn)
                pn = getpref('StimGenInterface','path',cd);
                [fn,pn] = uiputfile({'*.sgi','StimGenInterface Config (*.sgi)'},pn);
                if isequal(fn,0), return; end

                ffn = fullfile(pn,fn);

                setpref('StimGenInterface','path',pn);
            end

            SGI.StimPlayObj = obj.StimPlayObj;
            SGI.Calibration = obj.Calibration;

            [~,~,ext] = fileparts(ffn);
            if ~isequal(ext,'.sgi')
                ffn = [ffn '.sgi'];
            end

            vprintf(1,'Saving StimGenInterface configuration to: "%s"',ffn);
            save(ffn,'SGI','-mat');

            f = ancestor(obj.parent,'figure');

            figure(f);

            uialert(f, ...
                sprintf('Saved curent configuration to: "%s"',ffn), ...
                'StimGenInterface','Icon','success','Modal',true);

            obj.FileLoaded = string(ffn);
        end


        function set_calibration(obj,ffn)

            if nargin < 2 || isempty(ffn)
                pn = getpref('StimGenInterface','calpath',cd);
                [fn,pn] = uigetfile({'*.sgc','StimGenInterface Calibration (*.sgc)'},pn);
                if isequal(fn,0), return; end

                ffn = fullfile(pn,fn);

                setpref('StimGenInterface','calpath',pn);
            end
            vprintf(1,'Loading Calibration from: "%s"',ffn);
            x = load(ffn,'-mat');
            obj.Calibration = x.obj;

            f = ancestor(obj.parent,'figure');

            figure(f);

            uialert(f, ...
                sprintf('Updated Calibration: "%s"',ffn), ...
                'StimGenInterface','Icon','success','Modal',true);

        end

        % save stimulus order to disk
        function save_stim_order(obj,ffn)
            if nargin < 2 || isempty(ffn)
                fn = sprintf('SGIData_%s.mat',datestr(now,30));

                ffn = fullfile(obj.DataPath,fn);
                [fn,pn] = uiputfile({'*.mat','MAT-file (*.mat)'}, 'Save Stim Order As', ffn);
                if isequal(fn,0) || isequal(pn,0), return; end

                [~,~,ext] = fileparts(fn);
                if isempty(ext), fn = [fn '.mat']; end

                obj.DataFilename = fn;
                obj.DataPath = pn;
                ffn = fullfile(pn,fn);
                setpref('StimGenInterface','dataPath',pn);
            end

            SG.StimObjs = obj.StimPlayObj;
            SG.StimOrder      = obj.StimOrder;
            SG.StimOrderTime  = obj.StimOrderTime;
            SG.StimOrderTrial = obj.StimOrderTrial;
            SG.StimOrderNames = [obj.StimPlayObj.DisplayName]';

            SG.timestamp = datetime('now');

            vprintf(1,'Saving stimulus order to: "%s"',ffn);

            save(ffn,'SG','-mat');

        end

    end % methods (Access = public)



    methods (Access = private)
        function delete_main_figure(obj,src,event)

            pos = obj.parent.Position;
            setpref('StimGenInterface','parent_pos',pos);

            delete(obj.els);

            delete(src);
        end


        function s = timeSinceStart(obj)
            a = (now - 719529) * 86400;
            b = (obj.firstTrigTime - 719529) * 86400;
            s = a - b;
        end
    end

end
