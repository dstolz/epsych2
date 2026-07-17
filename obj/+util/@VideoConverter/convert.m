function convert(obj)
% obj.convert()
% Start converting every 'pending' row in Results. ASYNCHRONOUS: this
% returns immediately; a timer drives the scheduler in the background,
% launching up to MaxParallel ffmpeg processes at once. A busy MATLAB
% main thread only stalls *reporting*, never the encodes themselves.
%
% Use waitUntilDone() to block in a script, or set ProgressFcn / listen to
% the Progress event for live updates. Call cancel() to stop early.
arguments
    obj (1,1) util.VideoConverter
end

if obj.IsRunning
    vprintf(0, 1, 'util.VideoConverter: convert() already running; ignoring.');
    return
end
if isempty(obj.Results) || height(obj.Results) == 0
    vprintf(1, 'util.VideoConverter: no files to convert; call scan() first.');
    return
end

obj.buildQueue_();
obj.cancelRequested_ = false;
obj.IsRunning = true;
obj.tStart_ = tic;
obj.emitProgress_('started', NaN);
obj.startTimer_();
end
