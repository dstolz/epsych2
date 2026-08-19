function ep_SaveDataFcn(RUNTIME)
% ep_SaveDataFcn(RUNTIME)
%
% Default function for saving behavioral data.
%
% Saves each subject's trial data to the filename the session is already
% carrying -- RUNTIME.TRIALS(i).DataFilename, which is what gui.FilenameValidator
% writes when the operator edits the name during a run -- without prompting.
% The name was chosen (or accepted) before the run; asking for it again at the
% end is a dialog with no decision in it.
%
% Where each file went is reported in the command window, with the path as a
% hyperlink that loads the file back into a base workspace variable named after
% the subject.
%
% Use the epsych.RunExpt GUI to specify a custom function.
%
% Parameters:
%   RUNTIME - epsych.Runtime for the finished session
%
% See also: gui.FilenameValidator, epsych.RunExpt.defaultFilename, cl_SaveDataFcn
%
% Daniel.Stolzberg@gmail.com 2014

% Copyright (C) 2025  Daniel Stolzberg, PhD

% A Preview run promises no data file -- gui.FilenameValidator says so on the
% field itself -- and saving without a dialog would quietly break that promise.
% The trials are still in the runtime and in the crash-recovery .mat.
if RUNTIME.isTest
    vprintf(0,'Preview (test) run: no data file written')
    return
end

for i = 1:RUNTIME.NSubjects
    S = RUNTIME.TRIALS(i).Subject;

    Data = RUNTIME.TRIALS(i).DATA;

    if isempty(Data)
        vprintf(0,1,'No trials to save for ''%s'' in Box ID %d',S.Name,S.BoxID)
        continue
    end

    fileloc = localTargetFile(RUNTIME,i,S);

    try
        pn = fileparts(fileloc);
        if ~isempty(pn) && ~isfolder(pn), mkdir(pn); end
        save(fileloc,'Data')

    catch me
        vprintf(0,1,me)
        vprintf(0,1,sprintf(['FAILED to save data for ''%s'' in Box ID %d to "%s". ' ...
            'The crash-recovery file is still on disk: %s'], ...
            S.Name,S.BoxID,fileloc,localRecoveryFile(RUNTIME,i)))
        continue
    end

    localReport(fileloc,S,numel(Data))
end

end





function ffn = localTargetFile(RUNTIME,i,S)
% ffn = localTargetFile(RUNTIME, i, S)
%
% The file this subject's data is going to: the name the session already holds,
% which ep_TimerFcn_Start seeds and gui.FilenameValidator updates. A run that
% never had one -- a scripted session that filled TRIALS itself -- gets the same
% timestamped default the timer function would have made.

ffn = char(strtrim(string(RUNTIME.TRIALS(i).DataFilename)));

if isempty(ffn)
    ffn = epsych.RunExpt.defaultFilename( ...
        fullfile(char(RUNTIME.DefaultDataPath),S.Name),S.Name);
    vprintf(1,sprintf('No data filename set for ''%s''; using "%s"',S.Name,ffn))
end

if ~endsWith(ffn,'.mat','IgnoreCase',true)
    ffn = [ffn '.mat'];
end

% Saving twice (the operator clicks Save Data again) rewrites the session's own
% file, which is the intent; say so rather than let the timestamp mislead.
if isfile(ffn)
    vprintf(1,sprintf('Overwriting existing file "%s"',ffn))
end

end





function localReport(fileloc,S,nTrials)
% localReport(fileloc, S, nTrials)
%
% Report the save in the command window with the path as a link that loads the
% file. It is the one thing the operator can act on directly from a save
% message: no path to copy out of the log, no load() to type.

varName = matlab.lang.makeValidName(sprintf('Data_%s',S.Name));

% The link runs in the base workspace, so the variable it makes is the one the
% operator sees. Assigning through itself avoids leaving a temporary behind,
% and a file saved by another function (Data nested differently) still lands as
% the loaded struct rather than failing.
cmd = sprintf(['%s = load(''%s''); if isfield(%s,''Data''), %s = %s.Data; end, ' ...
    'disp([''Loaded '' num2str(numel(%s)) '' trials into %s''])'], ...
    varName,strrep(fileloc,'''',''''''),varName,varName,varName,varName,varName);

% Hotlinks only where they render: in a -batch run or a piped console the raw
% anchor would bury the path it is supposed to be showing.
if feature('hotlinks')
    loc = sprintf('<a href="matlab: %s">%s</a> (click to load as %s)',cmd,fileloc,varName);
else
    loc = fileloc;
end

% Built here and passed as one literal: a data path may contain '%' or a
% backslash escape that vprintf's format pass would otherwise consume.
vprintf(0,sprintf('Saved %d trials for ''%s'' (Box %d) to %s',nTrials,S.Name,S.BoxID,loc))

end





function fn = localRecoveryFile(RUNTIME,i)
% fn = localRecoveryFile(RUNTIME, i)
%
% The per-subject crash-recovery .mat in the temporary data directory, which
% already holds every completed trial (ep_TimerFcn_Stop merged the journal into
% it). Named only when a save fails, where it is the way out.

fn = '(none)';
if numel(RUNTIME.DataFile) >= i && strlength(RUNTIME.DataFile(i)) > 0
    fn = char(RUNTIME.DataFile(i));
end

end
