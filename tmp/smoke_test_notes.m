function smoke_test_notes()
% smoke_test_notes()
% Standing check for session notes: the epsych.SessionNotes store, the fold
% into the Info variable a saving function writes, the journal record that
% survives a crash, the gui.components.Notes component in both its forms (panel and
% button) plus its review-mode stand-down, and the epsych.SessionNotes.log
% entry point the GUI commit paths use for automatic session-record entries.
%
%   matlab -batch "run('tmp/smoke_test_notes.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

figs = [];
cleanupObj = onCleanup(@() closeAll(figs));

% 1. The store ------------------------------------------------------------
N = epsych.SessionNotes();
assert(isempty(N.Records), 'a new store starts empty');
assert(~N.IsEdited, 'a new store is not edited');

N.add('first note');
N.add('  second note  ');
assert(numel(N.Records) == 2, 'two notes stored');
assert(strcmp(N.Records(2).Text, 'second note'), 'text is trimmed');
assert(N.Records(1).Trial == 0, 'no runtime means trial 0');
fprintf('PASS: notes are stored, trimmed, and stamped trial 0 before a run\n');

n0 = numel(N.Records);
N.add('   ');
N.add(sprintf('\t\n '));
assert(numel(N.Records) == n0, 'blank notes are ignored');
fprintf('PASS: a blank note commits nothing\n');

N.add(sprintf('multi\nline paste'));
assert(strcmp(N.Records(end).Text, 'multi line paste'), 'newlines flatten to spaces');
fprintf('PASS: multi-line text becomes one record\n');

% 2. Stamp formats --------------------------------------------------------
lines = N.render(TimeStamp = "none");
assert(startsWith(lines{1}, '[T000] first note'), 'stamp "none" is the trial alone');
lines = N.render(TimeStamp = "elapsed");
assert(startsWith(lines{1}, '[T000 --:--:--]'), 'no session start means an unknown elapsed time');
lines = N.render(TimeStamp = "clock");
assert(~isempty(regexp(lines{1}, '^\[T000 \d\d:\d\d:\d\d\] first note$', 'once')), ...
    'stamp "clock" is HH:MM:SS');
fprintf('PASS: the three stamp formats render as documented\n');

% 3. Subject scoping ------------------------------------------------------
S = epsych.SessionNotes();
S.add('everyone');
S.add('box two only', Subject = 2);
assert(numel(S.forSubject(1)) == 1, 'subject 1 gets only the session-wide note');
assert(numel(S.forSubject(2)) == 2, 'subject 2 gets its own note as well');
assert(numel(S.forSubject()) == 2, 'no index means every record');
fprintf('PASS: a tagged note reaches only its own subject\n');

% 4. Edited text wins -----------------------------------------------------
E = epsych.SessionNotes();
E.add('typo hree');
E.setText({'[T000 --:--:--] typo here', 'a line with no stamp at all'});
assert(E.IsEdited, 'hand-edited text marks the log edited');
assert(numel(E.Records) == 2, 'both edited lines survive as records');
assert(strcmp(E.Records(1).Text, 'typo here'), 'the stamp is parsed off');
assert(E.Records(1).Trial == 0, 'the parsed trial number is kept');
assert(isnan(E.Records(2).Trial), 'an unstamped line keeps its text with Trial NaN');
assert(strcmp(E.Records(2).Text, 'a line with no stamp at all'), 'and keeps its text');
E.add('added after the edit');
assert(contains(E.Text, 'added after the edit'), 'a later note appends to the edited text');
assert(numel(E.Records) == 3, 'and is a record too');
fprintf('PASS: hand-edited text is authoritative and later notes append to it\n');

% 5. Live runtime: trial stamps, journal, and the saved Info ---------------
outDir = fullfile(tempdir, 'epsych_notes_smoke');
if ~isfolder(outDir), mkdir(outDir); end
if isfolder(outDir), delete(fullfile(outDir, '*')); end

RUNTIME = epsych.Runtime;
assert(~isempty(RUNTIME.NOTES) && isvalid(RUNTIME.NOTES), 'a runtime always has a note store');
RUNTIME.StartTime = datetime('now') - seconds(3725);
RUNTIME.ReviewMode = true;   % suppress the trial dispatch set.TRIALS would do

T = struct();
T.Subject = struct('Name','SMOKE','BoxID',1);
T.BoxID = 1;
T.DataFilename = fullfile(outDir,'smoke_notes.mat');
T.protocol = epsych.Protocol(Name = "NotesSmoke");
T.selector = [];
T.parameters = hw.Parameter.empty(1,0);
T.trials = {};
T.writeparams = {};
T.writeParamIdx = struct();
T.DATA = struct('TrialIndex', {1 2 3 4 5});   % five completed trials
T.TrialIndex = 6;
T.NextTrialID = 1;
RUNTIME.TRIALS = T;
RUNTIME.ReviewMode = false;   % from here on it behaves as a live session

journalFile = fullfile(outDir, 'smoke_notes.epj');
RUNTIME.Journal = epsych.TrialJournal(journalFile);

RUNTIME.NOTES.add('typed mid-session');
assert(RUNTIME.NOTES.Records(1).Trial == 5, 'the stamp is the completed trial count');
assert(abs(RUNTIME.NOTES.Records(1).Elapsed - 3725) < 10, 'elapsed runs from StartTime');
lines = RUNTIME.NOTES.render();
assert(startsWith(lines{1}, '[T005 01:02:0'), 'elapsed renders as HH:MM:SS');
fprintf('PASS: a note in a live session is stamped with the trial and the elapsed clock\n');

J = epsych.TrialJournal.read(journalFile);
assert(isfield(J, 'notes'), 'the note reached the journal');
assert(numel(J.notes.Records) == 1, 'the journal record holds the log');
RUNTIME.NOTES.add('a second one');
J = epsych.TrialJournal.read(journalFile);
assert(numel(J.notes.Records) == 2, 'the journal record is the WHOLE log, rewritten');
fprintf('PASS: every note is journaled, and the record is the whole log\n');

Info = epsych.SessionSnapshot.forSubject(RUNTIME, 1);
assert(isfield(Info,'Notes') && numel(Info.Notes) == 2, 'Info carries the notes');
assert(isfield(Info,'NotesText') && contains(Info.NotesText, 'typed mid-session'), ...
    'Info carries the rendered text');
assert(isfield(Info,'NotesEdited') && ~Info.NotesEdited, 'and says they were not hand-edited');
fprintf('PASS: notes are folded into the Info a saving function writes\n');

blank = epsych.SessionSnapshot.fromInfo([]);
assert(isfield(blank,'Notes') && isempty(blank.Notes), 'a legacy file reads back with no notes');
back = epsych.SessionSnapshot.fromInfo(Info);
assert(numel(back.Notes) == 2, 'a snapshot round trips its notes');
R = epsych.SessionNotes.fromSnapshot(back);
assert(numel(R.Records) == 2 && isempty(R.RUNTIME), ...
    'a review store holds the saved notes and no runtime');
fprintf('PASS: notes round trip through fromInfo and back into a review store\n');

% 6. The component: panel form -------------------------------------------
fig = uifigure('Visible','off','Name','NotesSmoke','Tag','NotesSmoke');
figs(end+1) = fig;
g = uigridlayout(fig,[1 1]);
C = gui.components.Notes(RUNTIME, g);
assert(isvalid(C.LogH) && isvalid(C.EntryH) && isvalid(C.CommitH), 'the panel builds');
assert(strcmp(C.LogH.Editable,'off'), 'the log is read-only by default');
assert(numel(C.LogH.Value) == 2, 'it opens showing the notes already taken');

C.EntryH.Value = 'typed into the field';
C.commit();
assert(isempty(C.EntryH.Value), 'committing clears the entry field');
assert(numel(RUNTIME.NOTES.Records) == 3, 'the note went to the session store');
assert(numel(C.LogH.Value) == 3, 'and the log redrew');
fprintf('PASS: the panel commits into the session store and redraws\n');

C.EntryH.Value = '   ';
C.commit();
assert(numel(RUNTIME.NOTES.Records) == 3, 'an empty field commits nothing');

C.setEditable(true);
assert(strcmp(C.LogH.Editable,'on'), 'Editable turns the box on');
C.setEditable(false);
fprintf('PASS: Editable toggles the log box\n');

% 7. Two components over one store stay in step ---------------------------
fig2 = uifigure('Visible','off','Name','NotesSmoke2','Tag','NotesSmoke2');
figs(end+1) = fig2;
C2 = gui.components.Notes(RUNTIME.NOTES, uigridlayout(fig2,[1 1]));
C2.addNote('from the second view');
assert(numel(C.LogH.Value) == 4, 'the first view saw it too');
assert(numel(C2.LogH.Value) == 4, 'and so did the second');
fprintf('PASS: two views over one store update together\n');

% 8. Button form ----------------------------------------------------------
fig3 = uifigure('Visible','off','Name','NotesSmoke3','Tag','NotesSmoke3');
figs(end+1) = fig3;
B = gui.components.Notes(RUNTIME, uigridlayout(fig3,[1 1]), ButtonOnly = true);
assert(B.IsButtonOnly && isvalid(B.OpenH), 'the button form builds a button');
assert(isempty(B.LogH), 'and no log of its own');

P = B.popOut();
figs(end+1) = B.PopOutFigure;
assert(~isempty(P) && isvalid(P), 'the button opens a pop-out');
assert(P.Store == RUNTIME.NOTES, 'the pop-out shares the session store');
assert(numel(P.LogH.Value) == 4, 'and opens showing every note so far');
P.EntryH.Value = 'typed in the pop-out window';
P.commit();
assert(numel(RUNTIME.NOTES.Records) == 5, 'a note typed there is a session note');
assert(numel(C.LogH.Value) == 5, 'the embedded panel elsewhere saw it');
B.closePopOut();
assert(~B.hasPopOut(), 'the window closes');
fprintf('PASS: the button form opens a pop-out that reads and writes the session notes\n');

% 9. Review mode stands down ---------------------------------------------
RV = epsych.Runtime;
RV.ReviewMode = true;
RV.NOTES = epsych.SessionNotes.fromSnapshot(back);
fig4 = uifigure('Visible','off','Name','NotesSmoke4','Tag','NotesSmoke4');
figs(end+1) = fig4;
CR = gui.components.Notes(RV, uigridlayout(fig4,[1 1]));
assert(numel(CR.LogH.Value) == 2, 'a review shows the notes the file was saved with');
assert(strcmp(CR.EntryH.Enable,'off'), 'and refuses new ones');
assert(strcmp(CR.CommitH.Enable,'off'), 'button included');
CR.setEditable(true);
assert(~CR.Editable, 'and refuses to be made editable');
fprintf('PASS: a reviewed session''s notes are a read-only record\n');

% 10. The gui.BehaviorGUI helpers ----------------------------------------
addpath(here);
G = NotesBehaviorGUI(RUNTIME);
assert(isa(G.NotesPanel,'gui.components.Notes') && ~G.NotesPanel.IsButtonOnly, 'addNotes builds a panel');
assert(isa(G.NotesButton,'gui.components.Notes') && G.NotesButton.IsButtonOnly, 'addNotesButton builds a button');
assert(G.NotesPanel.Store == RUNTIME.NOTES && G.NotesButton.Store == RUNTIME.NOTES, ...
    'both helpers bind to the session store');

W = G.NotesButton.popOut();
assert(isvalid(W) && isvalid(G.NotesButton.PopOutFigure), 'the button opens its window');
W.addNote('typed from the behavior GUI''s notes window');
assert(numel(G.NotesPanel.LogH.Value) == numel(RUNTIME.NOTES.Records), ...
    'the panel in the same GUI shows it');

popFig = G.NotesButton.PopOutFigure;
delete(G);
assert(~isvalid(popFig), 'closing the GUI takes the notes window with it');
fprintf('PASS: addNotes and addNotesButton wire both forms to the session store\n');

% 11. epsych.SessionNotes.log: the automatic session-record entry ---------
L = epsych.SessionNotes();
epsych.SessionNotes.log(L, 'Updated %s: %g -> %g', 'StimDelay', 1000, 1500);
assert(numel(L.Records) == 1 && strcmp(L.Records(1).Text, 'Updated StimDelay: 1000 -> 1500'), ...
    'log formats and commits to a bare store');

n0 = numel(RUNTIME.NOTES.Records);
epsych.SessionNotes.log(RUNTIME, 'Loaded phase "%s"', 'Stage2');
assert(numel(RUNTIME.NOTES.Records) == n0 + 1, 'log through the runtime reaches its store');
assert(strcmp(RUNTIME.NOTES.Records(end).Text, 'Loaded phase "Stage2"'), 'with the formatted text');

nRV = numel(RV.NOTES.Records);
epsych.SessionNotes.log(RV, 'must not appear');
assert(numel(RV.NOTES.Records) == nRV, 'a review session records nothing');

epsych.SessionNotes.log([], 'nowhere to go');
epsych.SessionNotes.log(struct('TRIALS', []), 'no NOTES field');
epsych.SessionNotes.log(struct('NOTES', []), 'an empty NOTES field');
fprintf('PASS: SessionNotes.log records live sessions, refuses reviews, and never throws\n');

LG = epsych.SessionNotes();
epsych.SessionNotes.log(struct('NOTES', LG), 'legacy struct runtime');
assert(numel(LG.Records) == 1, 'a legacy RUNTIME struct with a NOTES field still records');
fprintf('PASS: SessionNotes.log tolerates a legacy struct RUNTIME\n');

fprintf('\nALL NOTES SMOKE TESTS PASSED\n');

end


function closeAll(figs)
for i = 1:numel(figs)
    try
        if isvalid(figs(i)), delete(figs(i)); end
    catch
    end
end
end
