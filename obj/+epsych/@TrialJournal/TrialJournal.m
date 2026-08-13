classdef TrialJournal < handle
    % epsych.TrialJournal
    % Append-only, crash-safe on-disk journal for per-trial runtime data.
    %
    % Replaces the per-trial save('-append') in ep_TimerFcn_RunTime, whose cost
    % grows with file size because every call rewrites the MAT variable index
    % (measured 4.9 -> 19.7 ms over 300 trials). A journal append is a flat
    % ~2 ms: open for append, write one length-prefixed byte-stream record,
    % close. The write is synchronous and the file is closed after every
    % record, so a completed trial is durable the moment append() returns —
    % the same crash guarantee as the save it replaces. Because earlier bytes
    % are never rewritten, a crash can tear at most the trailing record, which
    % read() detects and skips; save('-append') by contrast rewrites its index
    % in place and can lose the whole file to a mid-rewrite crash.
    %
    % Each record is one named variable (e.g. 'info', 'data_0004'). At session
    % end ep_TimerFcn_Stop merges the journal into the seed .mat named by
    % RUNTIME.DataFile, so the on-disk recovery artifact keeps the layout
    % downstream tools expect. After a crash, epsych.TrialJournal.recover
    % rebuilds the same artifact from the orphaned journal.
    %
    % Properties:
    %   FilePath        - Journal file path (.epj). Empty in a default-constructed
    %                     element (array preallocation only).
    %   FallbackMatFile - save('-append') target used after a journal write fails.
    %   Faulted         - Latched true by the first failed journal write.
    %
    % Methods:
    %   TrialJournal    - Create/truncate the journal file and write its signature.
    %   append          - Durably write one named record (synchronous).
    %
    % Static methods:
    %   read            - Return all complete records as a struct + torn-tail flag.
    %   mergeToMat      - Merge journal records into a MAT-file (-v6).
    %   recover         - Crash-recovery convenience wrapper over mergeToMat.
    %
    % Usage:
    %   J = epsych.TrialJournal('RUNTIME_DATA_x.epj', FallbackMatFile='RUNTIME_DATA_x.mat');
    %   J.append('info', info);
    %   J.append('data_0001', data);
    %   [S, torn] = epsych.TrialJournal.read('RUNTIME_DATA_x.epj');
    %
    % See also: documentation/epsych/epsych_TrialJournal.md

    % Daniel Stolzberg, PhD (c) 2026

    properties (SetAccess = private)
        FilePath (1,1) string = ""
        FallbackMatFile (1,1) string = ""
        Faulted (1,1) logical = false
    end

    properties (Constant, Hidden)
        MAGIC = uint8('EPJ1') % file signature; bump the digit on format changes
    end

    methods
        function obj = TrialJournal(filepath, options)
            % obj = TrialJournal(filepath, FallbackMatFile=matpath)
            % Create (or truncate) the journal file and write its signature.
            % With no arguments, constructs an unopened placeholder so object
            % arrays can grow; append on a placeholder is an error.
            arguments
                filepath (1,1) string = ""
                options.FallbackMatFile (1,1) string = ""
            end

            if strlength(filepath) == 0, return, end

            obj.FilePath = filepath;
            if strlength(options.FallbackMatFile) > 0
                obj.FallbackMatFile = options.FallbackMatFile;
            else
                [pth, fn] = fileparts(filepath);
                obj.FallbackMatFile = fullfile(pth, fn + ".mat");
            end

            fid = fopen(filepath, 'w');
            if fid < 0
                error('epsych:TrialJournal:CannotCreate', ...
                    'Could not create trial journal "%s".', filepath);
            end
            cleaner = onCleanup(@() fclose(fid));
            fwrite(fid, epsych.TrialJournal.MAGIC, 'uint8');
            vprintf(3, 'Trial journal created: %s', filepath)
        end

        function ok = append(obj, name, data)
            % ok = append(obj, name, data)
            % Durably write one named record. Synchronous: the record is on
            % disk (file closed) when this returns. On the first write
            % failure the journal latches Faulted and this and all later
            % records fall back to save('-append') on FallbackMatFile;
            % losing the recovery channel must never abort a run, so this
            % method never throws once construction has succeeded.
            arguments
                obj (1,1) epsych.TrialJournal
                name (1,:) char
                data
            end

            if strlength(obj.FilePath) == 0
                error('epsych:TrialJournal:NotOpen', ...
                    'This TrialJournal was default-constructed and has no file.');
            end

            if obj.Faulted
                obj.appendFallback_(name, data);
                ok = false;
                return
            end

            try
                rec = struct('name', name, 'data', {data});
                bytes = getByteStreamFromArray(rec);
                fid = fopen(obj.FilePath, 'a');
                assert(fid >= 0, 'epsych:TrialJournal:OpenFailed', ...
                    'Could not open "%s" for append.', obj.FilePath);
                cleaner = onCleanup(@() fclose(fid));
                fwrite(fid, uint64(numel(bytes)), 'uint64');
                fwrite(fid, bytes, 'uint8');
                ok = true;
            catch me
                obj.Faulted = true;
                vprintf(0,1,me)
                vprintf(0,1,'Trial journal write failed; falling back to save(''-append'') on "%s" for the rest of the run.', char(obj.FallbackMatFile))
                obj.appendFallback_(name, data);
                ok = false;
            end
        end
    end

    methods (Access = private)
        function appendFallback_(obj, name, data)
            % Legacy-path fallback: one uniquely named variable per record,
            % same layout as the pre-journal save('-append') code.
            try
                S = struct();
                S.(name) = data;
                if isfile(obj.FallbackMatFile)
                    save(obj.FallbackMatFile, '-struct', 'S', '-append', '-v6');
                else
                    save(obj.FallbackMatFile, '-struct', 'S', '-v6');
                end
            catch me
                vprintf(0,1,me)
            end
        end
    end

    methods (Static)
        function [S, torn] = read(filepath)
            % [S, torn] = epsych.TrialJournal.read(filepath)
            % Return all complete records as a struct keyed by record name.
            % torn is true when the file ends in a partial record (crash
            % mid-write); every record before the tear is returned intact.
            arguments
                filepath (1,1) string
            end

            S = struct();
            torn = false;

            fid = fopen(filepath, 'r');
            if fid < 0
                error('epsych:TrialJournal:CannotRead', ...
                    'Could not open trial journal "%s".', filepath);
            end
            cleaner = onCleanup(@() fclose(fid));

            fseek(fid, 0, 'eof');
            fileSize = ftell(fid);
            fseek(fid, 0, 'bof');

            magic = fread(fid, 4, 'uint8=>uint8')';
            if numel(magic) < 4
                torn = fileSize > 0; % created but killed before/inside the signature write
                return
            end
            if ~isequal(magic, epsych.TrialJournal.MAGIC)
                error('epsych:TrialJournal:BadSignature', ...
                    '"%s" is not an EPsych trial journal.', filepath);
            end

            while true
                pos = ftell(fid);
                len = fread(fid, 1, 'uint64');
                if isempty(len)
                    torn = torn || (fileSize > pos); % 1-7 stray bytes = torn prefix
                    break
                end
                if pos + 8 + len > fileSize
                    torn = true; % length prefix promises more bytes than exist
                    break
                end
                bytes = fread(fid, len, 'uint8=>uint8');
                try
                    rec = getArrayFromByteStream(bytes);
                    S.(rec.name) = rec.data;
                catch
                    torn = true; % undeserializable tail
                    break
                end
            end
        end

        function matpath = mergeToMat(filepath, matpath)
            % matpath = epsych.TrialJournal.mergeToMat(filepath, matpath)
            % Merge every complete journal record into a MAT-file (default
            % format), creating it if needed. One save call, so the MAT
            % index is rewritten once per session instead of once per trial;
            % this is off the hot path, so the default format's compression
            % is worth having.
            arguments
                filepath (1,1) string
                matpath (1,1) string = ""
            end

            if strlength(matpath) == 0
                [pth, fn] = fileparts(filepath);
                matpath = fullfile(pth, fn + ".mat");
            end

            [S, torn] = epsych.TrialJournal.read(filepath);
            if torn
                vprintf(0,1,'Trial journal "%s" ends in a torn record (crash mid-write); the partial record was skipped.', char(filepath))
            end
            if isempty(fieldnames(S))
                vprintf(0,1,'Trial journal "%s" holds no complete records; "%s" was not modified.', char(filepath), char(matpath))
                return
            end

            if isfile(matpath)
                save(matpath, '-struct', 'S', '-append');
            else
                save(matpath, '-struct', 'S');
            end
            vprintf(2, 'Merged %d journal record(s) into %s', numel(fieldnames(S)), matpath)
        end

        function matpath = recover(filepath)
            % matpath = epsych.TrialJournal.recover(filepath)
            % Crash recovery: rebuild the .mat recovery artifact from an
            % orphaned journal and report what was recovered.
            arguments
                filepath (1,1) string
            end

            [S, torn] = epsych.TrialJournal.read(filepath);
            names = fieldnames(S);
            nTrials = nnz(startsWith(names, 'data_'));
            matpath = epsych.TrialJournal.mergeToMat(filepath);
            vprintf(0, 'Recovered %d trial record(s) from %s -> %s', nTrials, char(filepath), char(matpath))
            if torn
                vprintf(0, 'The final record was torn by the crash and could not be recovered.')
            end
        end
    end
end
