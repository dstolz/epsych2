classdef ProgressEventData < event.EventData
    % evt = util.ProgressEventData(s)
    % Event data for util.VideoConverter's Progress event (and the
    % ProgressFcn callback, which receives the same object). Fields carry
    % both batch-level and (when JobIndex is set) per-job progress.
    %
    % PROPERTIES
    %   Stage          string  "scanned"|"started"|"progress"|"jobdone"|
    %                          "finished"|"cancelled"
    %   JobIndex       double  Row index into Results, or NaN for batch-level stages.
    %   NumJobs/NumDone/NumFailed/NumRunning   double
    %   SourceFile / OutputFile   string  (job-level only)
    %   Percent        double  0..100 for this job; NaN when duration is unknown.
    %   OverallPercent double  0..100, duration-weighted across all jobs.
    %   Fps, Speed     double  ffmpeg's fps=/speed= for this job (NaN until known).
    %   ElapsedSeconds double  Batch elapsed time since convert() started.
    %   EtaSeconds     double  Batch ETA estimated from OverallPercent.
    %   Status, Message   string  (job-level only)
    %
    % See also: util.VideoConverter

    properties
        Stage (1,1) string = ""
        JobIndex (1,1) double = NaN
        NumJobs (1,1) double = 0
        NumDone (1,1) double = 0
        NumFailed (1,1) double = 0
        NumRunning (1,1) double = 0
        SourceFile (1,1) string = ""
        OutputFile (1,1) string = ""
        Percent (1,1) double = NaN
        OverallPercent (1,1) double = NaN
        Fps (1,1) double = NaN
        Speed (1,1) double = NaN
        ElapsedSeconds (1,1) double = NaN
        EtaSeconds (1,1) double = NaN
        Status (1,1) string = ""
        Message (1,1) string = ""
    end

    methods
        function obj = ProgressEventData(s)
            arguments
                s (1,1) struct = struct()
            end
            fn = fieldnames(s);
            for i = 1:numel(fn)
                if isprop(obj, fn{i})
                    obj.(fn{i}) = s.(fn{i});
                end
            end
        end
    end
end
