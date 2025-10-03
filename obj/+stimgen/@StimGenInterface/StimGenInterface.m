classdef StimGenInterface < handle% & gui.Helper
    
    properties
        StimPlayObjs (:,1) stimgen.StimPlay
        DataPath = fullfile('C:\Users\',getenv('USERNAME'));
        DataFilename = '';
    end
    
    properties (Hidden)
        isiAdjustment = 0.0405; % seconds
    end
    
    properties (SetAccess = protected, SetObservable = true)
        parent
        handles
        sgTypes
        sgObjs
        
        Calibration (1,1) stimgen.StimCalibration
        
        FileLoaded (1,1) string
        
        Timer
        
        lastTrigTic = tic;
        
        TrigBufferID
        
        
        nextSPOIdx
        currentISI
        
        Fs
    end
    
    properties (Access = private)
        RUNTIME
        TDTActiveX % TO DO: REMOVE AND UPGRADE
        els
        elsnsspi
    end
    
    properties (Constant)
        TrigParamStr = {'!Trigger_0','!Trigger_1'};
        BufferSize = {'BufferSize_0','BufferSize_1'};
        BufferData = {'BufferData_0','BufferData_1'};
    end
    
    properties (Dependent)
        currentTrialNumber
        CurrentSGObj % stimgen obj
        CurrentSPObj % stimplay obj
    end
    
    methods
        
        idx = stimselect_Serial(obj);
        idx = stimselect_Shuffle(obj);
        
        function obj = StimGenInterface(RUNTIME,parent,ffn)
            obj.RUNTIME = RUNTIME;
            obj.TDTActiveX = RUNTIME.TRIALS.MODULES; % TO DO: REMOVE AND REPLACE

            if nargin > 1, obj.parent = parent; end
            
            
            % get a list of available stimgen objects
            obj.sgTypes = stimgen.StimType.list;
            
            obj.sgObjs = cellfun(@(a) stimgen.(a),obj.sgTypes,'uni',0);
            
            obj.create;
            
            if nargin > 1 && ~isempty(ffn)
                obj.load_config(ffn);
            end
            
            
            if nargout == 0, clear obj; end
        end
        
        
        function delete(obj)
            
        end
        
        
        
        
        function set.Calibration(obj,calObj)
            
            obj.Calibration = calObj;
            
            for i = 1:length(obj.StimPlayObjs)
                obj.StimPlayObjs(i).StimObj.Calibration = calObj;
            end
            
        end
        
        
        function trigger_stim_playback(obj)
            if obj.nextSPOIdx < 1, return; end % flag to finish playback
            
            % TO DO: CHANGE TO PARAMETER
            s(1) = obj.TDTActiveX.SetTagVal(obj.TrigParamStr{obj.TrigBufferID+1},1);
            
            
            lastToc = toc(obj.lastTrigTic);
            obj.lastTrigTic = tic;
            
            pause(0.001);
            
            % TO DO: CHANGE TO PARAMETER
            s(2) = obj.TDTActiveX.SetTagVal(obj.TrigParamStr{obj.TrigBufferID+1},0);
            
            tdiff = lastToc-obj.currentISI;
            if isempty(tdiff), tdiff = 0; end
            vprintf(3,'trigger_stim_playback: TrigBufferID = %d; nextSPOidx = %d; ITI diff = %.4f sec', ...
                obj.TrigBufferID,obj.nextSPOIdx,tdiff)
            
            
            
            if ~all(s)
                warning('StimGenInterface:trigger_stim_playback:RPvdsFail','Failed to trigger Stim buffer')
            end
            
            obj.currentISI = obj.CurrentSPObj.get_isi - tdiff;
            
            vprintf(3,'trigger_stim_playback: obj.currentISI = %.3f s',obj.currentISI)
        end
        
        function update_buffer(obj)            
            obj.TrigBufferID = mod(obj.currentTrialNumber,2);  
            
            vprintf(3,'update_buffer START: TrigBufferID = %d; nextSPOidx = %d', ...
                obj.TrigBufferID,obj.nextSPOIdx)
            
            t = tic;
            
            % make first and last samples 0 since RPvds circuit uses SerSource
            % components
            buffer = [0, obj.CurrentSPObj.Signal, 0]; 
            
            % write constructed Stim to RPvds circuit buffer
            nSamps = length(buffer);
                    
            bid = obj.TrigBufferID + 1;
            
            % TO DO: CHANGE TO PARAMETER
            obj.TDTActiveX.SetTagVal(obj.BufferSize{bid},nSamps);
            s = obj.TDTActiveX.WriteTagV(obj.BufferData{bid},0,buffer);
            if ~s
                warning('StimGenInterface:update_buffer:RPvdsFail','Failed to write Stim buffer')
            end
            
            vprintf(3,'update_buffer END:   TrigBufferID = %d; nextSPOidx = %d; took %.2f seconds',obj.TrigBufferID,obj.nextSPOIdx, toc(t))
        end
        
        
        
        
        function write_trial_data(obj)
            ffn = fullfile(obj.DataPath,obj.DataFilename);
            
            
%             TrialNumber = obj.currentTrialNumber
            
            % save(ffn,var{:},'-append','-nocompression');
            
            
        end
        
        
        
        
        
        
        
        
        function timer_startfcn(obj,src,event)
            % reset reps for all StimPlay objects
            set(obj.StimPlayObjs,'RepsPresented',0);
            
            obj.select_next_spo_idx; % select the first idx

            obj.update_buffer; % update the buffer with the first stimulus
            
            obj.lastTrigTic = tic;
        end
        
        
        function timer_runtimefcn(obj,src,event)
            
            if obj.nextSPOIdx < 1, return; end % flag to finish playback
                                    
            isi = obj.currentISI;
            
            % wait until ISI has elapsed 
            if toc(obj.lastTrigTic) - isi < src.Period - obj.isiAdjustment
                return
            end            
            
            % hold the computer hostage until ISI has expired
            
            while toc(obj.lastTrigTic)+obj.isiAdjustment < isi, end
            
            obj.trigger_stim_playback; % trigger playback of the obj.nextSPIdx buffer
            
            obj.CurrentSPObj.increment; % increment the StimPlay object
            
            obj.select_next_spo_idx; % select the obj.nextSPOIdx 
            
            if obj.nextSPOIdx < 1, return; end % flag less than 1 means session is complete
            
            obj.update_buffer; % update the non-triggered buffer with the nextSPOIdx stimulus
        end
        
        function timer_stopfcn(obj,src,event)
            h = obj.handles;
            h.RunStopButton.Text = 'Run';
        end
        
        function playback_control(obj,src,event)
            
            c = src.Text;
            
            switch lower(c)
                
                case 'run'
                   
                    obj.Fs = obj.TDTActiveX.GetSFreq;
                    % obj.Fs = obj.RUNTIME.TRIALS.MODULES.Fs;
                    set(obj.StimPlayObjs,'Fs',obj.Fs);
                    vprintf(3,'Module sampling rate = %.3f Hz',obj.Fs);
                    arrayfun(@update_signal,obj.StimPlayObjs);
                    
                    delete(obj.elsnsspi);
                    
                    obj.elsnsspi = addlistener(obj,'nextSPOIdx','PostSet',@obj.stim_list_item_selected);
                    
                    
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
                    
                    src.Text = 'Run';
                    
                case 'pause'
                    
            end
            
        end
        
        function select_next_spo_idx(obj)
            h = obj.handles;
            fnc = h.SelectionTypeList.Value;
            obj.nextSPOIdx = fnc(obj);
            
            if obj.nextSPOIdx < 1 % flag to finish playback
                stop(obj.Timer);
            end
        end
        
        function n = get.currentTrialNumber(obj)
            % TO DO: CHANGE TO PARAMETER
            n = obj.TDTActiveX.GetTagVal('TrialNumber');
            % n = obj.RUNTIME.TRIALS.MODULES.Parameters
        end
        
        function stimtype_changed(obj,src,event)
            warning('off','stimgen:StimType:apply_calibration:NoCalibration');
            obj.update_signal_plot;
            warning('on','stimgen:StimType:apply_calibration:NoCalibration');
        end
        
        function add_stim_to_list(obj,src,event)
            h = obj.handles;
            
            n = h.Reps.Value;
            
            sn = h.StimName.Value;
            
            v = h.ISI.Value;
            v = str2num(v);
            
            obj.StimPlayObjs(end+1).StimObj = copy(obj.CurrentSGObj);
            obj.StimPlayObjs(end).StimObj.Calibration = obj.Calibration;
            obj.StimPlayObjs(end).Reps = n;
            obj.StimPlayObjs(end).Name = sn;
            obj.StimPlayObjs(end).ISI  = v;
                        
            
            h.StimObjList.Items     = [obj.StimPlayObjs.DisplayName];
            h.StimObjList.ItemsData = 1:length(h.StimObjList.Items);
        end
        
        function rem_stim_from_list(obj,src,event)
            h = obj.handles;
            
            ind = h.StimObjList.ItemsData == h.StimObjList.Value;
            
            
            if isempty(obj.StimPlayObjs), return; end
            obj.StimPlayObjs(ind) = [];
            
            if isempty(obj.StimPlayObjs)
                h.StimObjList.Items = "";
                h.StimObjList.ItemsData = 1;
            else
                h.StimObjList.Items     = [obj.StimPlayObjs.DisplayName];
                h.StimObjList.ItemsData = 1:length(obj.StimPlayObjs);
            end
        end
        
        function stim_list_item_selected(obj,src,event)
            h = obj.handles;
            
            if isprop(src,'Name') && isequal(src.Name,'nextSPOIdx')
                value = obj.nextSPOIdx;
            elseif isempty(event.Value)
                return
            else
                value = event.Value;
            end
            
            if value == -1, return; end
            
            spo = obj.StimPlayObjs(value);
                        
            ind = ismember(obj.sgTypes,spo.Type);
            
            co = copy(spo.StimObj);
            
            obj.sgObjs{ind} = co;
                        
            h.TabGroup.SelectedTab = h.Tabs.(spo.Type);
            
            tg = h.TabGroup;
            
            st = tg.SelectedTab;
            
            delete(st.Children);
            
            co.create_gui(st);
                        
            addlistener(co,'Signal','PostSet',@obj.update_signal_plot);

            obj.update_signal_plot;
        end
        
        function update_playmode(obj,src,event)
            
        end
        
        function update_isi(obj,src,event)
            h = obj.handles;
            v = h.ISI.Value;
            v = str2num(v);
            v = sort(v(:)');
            try
                src.Value = mat2str(v);
            catch me
                uialert(obj.parent,me.message,'InvalidEntry','modal',true)
                h.ISI.Value = vent.Previous;
            end
        end
        
        function play_current_stim_audio(obj,src,event)
            h = obj.handles.PlayStimAudio;
            
            c = h.BackgroundColor;
            h.BackgroundColor = [.2 1 .2];
            drawnow
            play(obj.CurrentSGObj);
            h.BackgroundColor = c;
        end
        
        function update_signal_plot(obj,src,event)
            obj.CurrentSGObj.update_signal;
            h = obj.handles.SignalPlotLine;
            h.XData = obj.CurrentSGObj.Time;
            h.YData = obj.CurrentSGObj.Signal;
        end
                
        function sobj = get.CurrentSGObj(obj)
            st = obj.handles.TabGroup.SelectedTab;
            ind = ismember(obj.sgTypes,st.Title);
            sobj = obj.sgObjs{ind};
        end
        
        function sp = get.CurrentSPObj(obj)
            sp = obj.StimPlayObjs(obj.nextSPOIdx);
        end
        
        function update_samplerate(obj,src,event)
            for i = 1:length(obj.sgObjs)
                obj.sgObjs{i}.Fs = event.Value;
            end
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
            load(ffn,'SGI','-mat');
            warning('on','MATLAB:class:LoadInvalidDefaultElement');

            obj.StimPlayObjs = SGI.StimPlayObjs;
            obj.Calibration  = SGI.Calibration;
            
            h = obj.handles;
            
            h.StimObjList.Items = [obj.StimPlayObjs.DisplayName];
            h.StimObjList.ItemsData = 1:length(h.StimObjList.Items);
            
            event.Value = 1;
            obj.stim_list_item_selected(h.StimObjList,event);
        end
        
        
        function save_config(obj,ffn)
            
            if nargin < 2 || isempty(ffn)
                pn = getpref('StimGenInterface','path',cd);
                [fn,pn] = uiputfile({'*.sgi','StimGenInterface Config (*.sgi)'},pn);
                if isequal(fn,0), return; end
                
                ffn = fullfile(pn,fn);
                
                setpref('StimGenInterface','path',pn);
            end
            
            SGI.StimPlayObjs = obj.StimPlayObjs;
            SGI.Calibration  = obj.Calibration;
            
            [~,~,ext] = fileparts(ffn);
            if ~isequal(ext,'.sgi')
                ffn = [ffn '.sgi'];
            end
            
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
            
            x = load(ffn,'-mat');
            obj.Calibration = x.obj;
            
            f = ancestor(obj.parent,'figure');
            
            figure(f);
            
            uialert(f, ...
                sprintf('Updated Calibration: "%s"',ffn), ...
                'StimGenInterface','Icon','success','Modal',true);
            
        end
        
        
    end % methods (Access = public)
    
    methods (Access = private)
        function delete_main_figure(obj,src,event)
            
            pos = obj.parent.Position;
            setpref('StimGenInterface','parent_pos',pos);
            
            delete(obj.els);
            
            delete(src);
        end
        
        function create(obj)
            if isempty(obj.parent), obj.parent = uifigure('Name','StimGen'); end
            
            f = obj.parent;
            
            pos = f.Position;
            
            pos = getpref('StimGenInterface','parent_pos',pos);
            
            f.Position = pos;
            f.Scrollable = 'on';
            f.DeleteFcn = @obj.delete_main_figure;
            %movegui(f,'onscreen'); % do this after all gui components have loaded
            
            
            
            g = uigridlayout(f);
            g.ColumnWidth = {250,'1x',250};
            g.RowHeight   = {150,'1x',25};
            
            
            % signal plot
            ax = uiaxes(g);
            ax.Layout.Column = [1 2];
            ax.Layout.Row = 1;
            grid(ax,'on');
            box(ax,'on');
            xlabel(ax,'time (s)');
            obj.handles.SignalPlotAx = ax;
            
            h = line(ax,nan,nan);
            obj.handles.SignalPlotLine = h;
            
            % stimgen interface
            tg = uitabgroup(g);
            tg.Layout.Column = [1 2];
            tg.Layout.Row    = 2;
            tg.Tag = 'StimGenTabs';
            tg.TabLocation = 'left';
            tg.SelectionChangedFcn = @obj.stimtype_changed;
            obj.handles.TabGroup = tg;
            
            flag = 1;
            for i = 1:length(obj.sgTypes)
                try
                    sgt = obj.sgTypes{i};
                    sgo = obj.sgObjs{i};
                    fnc = @sgo.create_gui;
                    t = uitab(tg,'Title',sgt,'CreateFcn',fnc);
                    t.Scrollable = 'on';
                    obj.handles.Tabs.(sgt) = t;
                    addlistener(sgo,'Signal','PostSet',@obj.update_signal_plot);
                    if flag, obj.update_signal_plot; flag = 0; end
                catch me
                    t.Title = sprintf('%s ERROR',sgt);
                    disp(me)
                end
            end
            
%             % sample rate
%             h = uieditfield(g,'numeric','Tag','SampleRate');
%             h.Layout.Row = 3;
%             h.Layout.Column = 1;
%             h.Limits = [1 1e6];
%             h.ValueDisplayFormat = '%.3f Hz';
%             h.Value = 48828.125;
%             h.ValueChangedFcn = @obj.update_samplerate;
            
            % play stim
            h = uibutton(g,'Tag','Play');
            h.Layout.Row = 3;
            h.Layout.Column = 2;
            h.Text = 'Play Stim';
            h.ButtonPushedFcn = @obj.play_current_stim_audio;
            obj.handles.PlayStimAudio = h;
            
            
            
            % side-bar grid
            sbg = uigridlayout(g);
            sbg.Layout.Column = 3;
            sbg.Layout.Row = [1 3];
            sbg.ColumnWidth = {'1x', '1x'};
            sbg.RowHeight = repmat({30},1,9);
            
            R = 1;
            
            % stimulus counter
            h = uilabel(sbg);
            h.Layout.Column = [1 2];
            h.Layout.Row = R;
            h.Text = '---';
            h.FontSize = 18;
            h.FontWeight = 'bold';
            obj.handles.StimulusCounter = h;
            
            R = R + 1;
            
            % stim name field
            h = uilabel(sbg);
            h.Layout.Column = 1;
            h.Layout.Row = R;
            h.Text = 'Stim Name:';
            h.HorizontalAlignment = 'right';
            h.FontSize = 16;
            obj.handles.StimulusCounter = h;
            
            h = uieditfield(sbg,'Tag','StimName');
            h.Layout.Column = 2;
            h.Layout.Row = R;
            h.Value = '';
            obj.handles.StimName = h;
            
            R = R + 1;            
            
            % inter-stimulus interval
            h = uilabel(sbg,'Text','ISI');
            h.Layout.Column = 1;
            h.Layout.Row = R;
            h.HorizontalAlignment = 'right';
            obj.handles.ISILabel = h;
            
            h = uieditfield(sbg,'Tag','ISI');
            h.Layout.Column = 2;
            h.Layout.Row = R;
            h.Value = '1.00';
            h.ValueChangedFcn = @obj.update_isi;
            obj.handles.ISI = h;
            
            R = R + 1;
            
            % rep field
            h = uieditfield(sbg,'numeric','Tag','Reps');
            h.Layout.Column = 1;
            h.Layout.Row = R;
            h.Limits = [1 1e6];
            h.RoundFractionalValues = 'on';
            h.ValueDisplayFormat = '%d reps';
            h.Value = 20;
            obj.handles.Reps = h;
                        

            % add stim button
            h = uibutton(sbg,'Tag','AddStimToList');
            h.Layout.Column = 2;
            h.Layout.Row = R;
            h.Text = 'Add';
            h.FontSize = 16;
            h.FontWeight = 'bold';
            h.ButtonPushedFcn = @obj.add_stim_to_list;
            obj.handles.AddStimToList = h;
            
            R = R + 1;
            
            % stimulus list
            h = uilistbox(sbg,'Tag','StimObjList');
            h.Layout.Column = [1 2];
            h.Layout.Row = [R R+2];
            h.Items = {};
            h.ValueChangedFcn = @obj.stim_list_item_selected;
            obj.handles.StimObjList = h;
            
            R = R + 3;            
            
%             % advance stim button
%             h = uibutton(sbg,'Tag','AdvanceStimFromList');
%             h.Layout.Column = 2;
%             h.Layout.Row = R;
%             h.Text = 'Remove';
%             h.FontSize = 16;
%             h.FontWeight = 'bold';
%             h.ButtonPushedFcn = @obj.advance_stim;
%             obj.handles.AdvanceStimFromList = h;
            
            % remove stim button
            h = uibutton(sbg,'Tag','RemStimFromList');
            h.Layout.Column = 2;
            h.Layout.Row = R;
            h.Text = 'Remove';
            h.FontSize = 16;
            h.FontWeight = 'bold';
            h.ButtonPushedFcn = @obj.rem_stim_from_list;
            obj.handles.RemStimFromList = h;
            
            R = R + 1;
            
            % playmode dropdown
            h = uidropdown(sbg,'Tag','PlayMode');
            h.Layout.Column = [1 2];
            h.Layout.Row = R;
            w = which('stimgen.StimGenInterface');
            p = fileparts(w);
            d = dir(fullfile(p,'stimselect_*.m'));
            itmr = cellfun(@(a) a(1:end-2),{d.name},'uni',0);
            itm  = cellfun(@(a) a(find(a=='_',1)+1:end),itmr,'uni',0);
            itmf = cellfun(@str2func,itmr,'uni',0);
            h.Items = itm;
            h.ItemsData = itmf;
            obj.handles.SelectionTypeList = h;
            
            
            R = R + 1;
            
            % run/stop/pause buttons
            h = uibutton(sbg);
            h.Layout.Column = 1;
            h.Layout.Row = R;
            h.Text = 'Run';
            h.FontSize = 18;
            h.FontWeight = 'bold';
            h.ButtonPushedFcn = @obj.playback_control;
            h.Enable = 'on';
            obj.handles.RunStopButton = h;
            
            h = uibutton(sbg);
            h.Layout.Column = 2;
            h.Layout.Row = R;
            h.Text = 'Pause';
            h.FontSize = 18;
            h.FontWeight = 'bold';
            h.ButtonPushedFcn = @obj.playback_control;
            h.Enable = 'off';
            obj.handles.PauseButton = h;
            
            
            
            % toolbar
            hf = uimenu(obj.parent,'Text','&File','Accelerator','F');
            
            h = uimenu(hf,'Tag','menu_Load','Text','&Load','Accelerator','L', ...
                'MenuSelectedFcn',@(~,~) obj.load_config);
            h = uimenu(hf,'Tag','menu_Save','Text','&Save','Accelerator','S', ...
                'MenuSelectedFcn',@(~,~) obj.save_config);

            h = uimenu(hf,'Tag','menu_Save','Text','&Calibration','Accelerator','C', ...
                'MenuSelectedFcn',@(~,~) obj.set_calibration);



            
            movegui(f,'onscreen');
        end
        
    end
end