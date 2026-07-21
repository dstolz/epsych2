function playback_control(obj, src, ~)
% playback_control(obj, src) - Handle Run/Pause/Stop button presses.
%
% Parameters:
%   src - uibutton that was pressed (Text is 'Run', 'Stop', or 'Pause')

h = obj.handles;

switch lower(src.Text)

    case 'run'
        try
            if isempty(obj.StimPlayObjs)
                obj.show_gui_message_("Add at least one stimulus to the bank before running.", ...
                    "No Stimuli", "warning");
                return
            end

            % Prepare runtime and hardware from the currently loaded protocol.
            obj.initialize_runtime_from_protocol_;

            % Resolve hardware parameters from Runtime
            obj.resolve_params_;

            if ~obj.HardwareAvailable
                stimgen.util.vprintf(1, 'StimPlayer: hardware parameters not found — timer will run without hardware output.');
            end

            % Update Fs on all bank items from hardware if available
            if obj.HardwareAvailable && isfield(obj.PARAMS, 'BufferData_0')
                % Fs is not stored in a parameter; leave StimType defaults in place
            end

            % Prime each bank item to combination #1 so playback stepping is deterministic
            obj.initialize_variants_;

            % Kill any stale timer
            t = timerfindall('Tag', 'StimPlayerTimer');
            if ~isempty(t)
                stop(t);
                delete(t);
            end

            t = timer( ...
                'Tag',           'StimPlayerTimer', ...
                'Period',        0.005, ...
                'ExecutionMode', 'fixedRate', ...
                'BusyMode',      'drop', ...
                'StartFcn',      @obj.timer_startfcn, ...
                'TimerFcn',      @obj.timer_runtimefcn, ...
                'StopFcn',       @obj.timer_stopfcn);

            obj.Timer = t;

            h.RunBtn.Text   = 'Stop';
            h.PauseBtn.Enable = 'on';
            obj.lock_bank_controls_(true);
            obj.refresh_combo_controls_;

            start(t);
            obj.set_status_("Playback started.");
            obj.update_protocol_status_;
        catch ME
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer);
                delete(obj.Timer);
            end
            obj.disconnect_interfaces_;
            obj.lock_bank_controls_(false);
            h.RunBtn.Text = 'Run';
            h.PauseBtn.Enable = 'off';
            h.PauseBtn.Text = 'Pause';
            obj.report_gui_error_(ME, "Playback Error", ...
                "StimPlayer could not start playback.");
            obj.update_protocol_status_;
        end

    case 'stop'
        try
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                stop(obj.Timer);
                delete(obj.Timer);
            end
            h.RunBtn.Text     = 'Run';
            h.PauseBtn.Enable = 'off';
            obj.set_status_("Playback stopped.");
            obj.disconnect_interfaces_;
            obj.lock_bank_controls_(false);
            obj.update_protocol_status_;
        catch ME
            obj.report_gui_error_(ME, "Stop Error", ...
                "StimPlayer could not stop playback cleanly.");
        end

    case 'pause'
        try
            if ~isempty(obj.Timer) && isvalid(obj.Timer)
                if strcmp(obj.Timer.Running, 'on')
                    stop(obj.Timer);
                    src.Text = 'Resume';
                    obj.set_status_("Playback paused.");
                else
                    start(obj.Timer);
                    src.Text = 'Pause';
                    obj.set_status_("Playback resumed.");
                end
            end
        catch ME
            obj.report_gui_error_(ME, "Pause Error", ...
                "StimPlayer could not change the playback pause state.");
        end

end
end
