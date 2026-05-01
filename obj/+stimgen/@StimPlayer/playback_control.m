function playback_control(obj, src, ~)
% playback_control(obj, src) - Handle Run/Pause/Stop button presses.
%
% Parameters:
%   src - uibutton that was pressed (Text is 'Run', 'Stop', or 'Pause')

h = obj.handles;

switch lower(src.Text)

    case 'run'
        if isempty(obj.StimPlayObjs)
            uialert(obj.hFig, 'Add at least one stimulus to the bank before running.', ...
                'No Stimuli', 'Icon', 'warning');
            return
        end

        % Resolve hardware parameters from Runtime
        obj.resolve_params_;

        if ~obj.HardwareAvailable
            vprintf(1, 'StimPlayer: hardware parameters not found — timer will run without hardware output.');
        end

        % Update Fs on all bank items from hardware if available
        if obj.HardwareAvailable && isfield(obj.PARAMS, 'BufferData_0')
            % Fs is not stored in a parameter; leave StimType defaults in place
        end

        % Regenerate signals on all bank items
        for i = 1:numel(obj.StimPlayObjs)
            obj.StimPlayObjs(i).update_signal;
        end

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

        start(t);

    case 'stop'
        if ~isempty(obj.Timer) && isvalid(obj.Timer)
            stop(obj.Timer);
            delete(obj.Timer);
        end
        h.RunBtn.Text     = 'Run';
        h.PauseBtn.Enable = 'off';

    case 'pause'
        if ~isempty(obj.Timer) && isvalid(obj.Timer)
            if strcmp(obj.Timer.Running, 'on')
                stop(obj.Timer);
                src.Text = 'Resume';
            else
                start(obj.Timer);
                src.Text = 'Pause';
            end
        end

end
end
