function icon = toolbarIcon(name)
% icon = gui.toolbarIcon(name)
% 16x16 truecolor icon for one uitoolbar tool.
%
% Icons are drawn here as pixel art rather than shipped as image files, so the
% toolbox carries no binary assets and a glyph can be read and edited in the
% same place it is named. Each row is a 16-character string, each character is
% a key into the palette below, and '.' is transparent.
%
% Transparent is NaN rather than white: uipushtool and uitoggletool render NaN
% as the toolbar background, while an opaque white would show as a card behind
% every glyph.
%
% Parameters:
%   name - glyph name (string or char). An unknown name raises rather than
%          returning a blank, so a typo is visible at build time.
%
% Returns:
%   icon - 16-by-16-by-3 double in [0,1], NaN where transparent. Assignable
%          straight to the Icon property of uipushtool/uitoggletool, and to
%          uibutton's, which is the only way to put a glyph other than the
%          four built-in names (success, error, warning, info) on a button.
%
% Example:
%   tb = uitoolbar(uifigure);
%   uipushtool(tb,'Icon',gui.toolbarIcon("refresh"),'Tooltip','Refresh');
%
% See also: epsych.RunExpt.buildUI, gui.SubjectManager.buildUI, gui.ScreenCapture

arguments
    name (1,1) string
end

% Drawing is cheap but happens once per tool per window; the cache makes
% opening a window with fifteen tools a single pass.
persistent cache
if isempty(cache), cache = struct(); end
key = char(name);
if isfield(cache, key)
    icon = cache.(key);
    return
end

C = struct( ...
    'k',[0.20 0.22 0.26], ...  % dark outline
    'w',[1.00 1.00 1.00], ...  % white
    's',[0.52 0.55 0.60], ...  % steel gray
    'y',[0.93 0.72 0.16], ...  % folder amber
    'Y',[0.98 0.85 0.42], ...  % folder highlight
    'b',[0.13 0.45 0.80], ...  % blue
    'g',[0.13 0.60 0.28], ...  % green
    'r',[0.83 0.16 0.16], ...  % red
    'R',[0.95 0.55 0.55], ...  % red highlight
    'o',[0.92 0.60 0.12], ...  % pencil orange
    't',[0.83 0.66 0.44]);     % pencil wood

switch name

    % ---- session window (epsych.RunExpt) -------------------------------

    case "browse"  % closed folder with a magnifying glass
        rows = [ ...
            "................"
            ".kkkkk.........."
            ".kyyyykkkkkkkk.."
            ".kyyyyyyyyyyyk.."
            ".kYYYYYYYYYYYk.."
            ".kYYYYYYYYYYYk.."
            ".kYYYYYkkkkYYk.."
            ".kYYYYkwwwwkYk.."
            ".kYYYYkwwwwkYk.."
            ".kYYYYkwwwwkYk.."
            ".kYYYYYkkkkYYk.."
            ".kkkkkkkkkkkkk.."
            "...........kk..."
            "............kk.."
            ".............k.."
            "................"];

    case "load"    % open folder
        rows = [ ...
            "................"
            "................"
            ".kkkkk.........."
            ".kyyyykkkkkkk..."
            ".kyyyyyyyyyyk..."
            ".kyyyyyyyyyyk..."
            ".kyyyyyyyyyyk..."
            ".kyyyyyyyyyyk..."
            ".kkkkkkkkkkkkkk."
            ".kYYYYYYYYYYYYk."
            "..kYYYYYYYYYYYk."
            "..kYYYYYYYYYYYk."
            "...kYYYYYYYYYYk."
            "...kkkkkkkkkkkk."
            "................"
            "................"];

    case "refresh" % circular arrow, clockwise
        rows = [ ...
            "................"
            "................"
            "....gggggg......"
            "...gggggggg....."
            "...gg....ggg...."
            "..gg....gggggg.."
            "..gg.....gggg..."
            "..gg......gg...."
            "..gg.......g...."
            "..gg............"
            "...gg..........."
            "...gggg........."
            "....gggggg......"
            "................"
            "................"
            "................"];

    case "save"    % floppy disk
        rows = [ ...
            "................"
            ".kkkkkkkkkkkkk.."
            ".kbbbwwwwwwbbk.."
            ".kbbbwwwwbwbbk.."
            ".kbbbwwwwbwbbk.."
            ".kbbbwwwwbwbbk.."
            ".kbbbbbbbbbbbk.."
            ".kbbbbbbbbbbbk.."
            ".kbwwwwwwwwwbk.."
            ".kbwssssssswbk.."
            ".kbwwwwwwwwwbk.."
            ".kbwssssssswbk.."
            ".kbwwwwwwwwwbk.."
            ".kkkkkkkkkkkkk.."
            "................"
            "................"];

    case "addsubject" % person with a green plus
        rows = [ ...
            "................"
            "...kkkk........."
            "..kssssk........"
            "..kssssk........"
            "..kssssk....gg.."
            "...kkkk.....gg.."
            "..kkkkkk..gggggg"
            ".kssssssk.gggggg"
            ".kssssssk...gg.."
            ".kssssssk...gg.."
            ".kssssssk......."
            ".kkkkkkkk......."
            "................"
            "................"
            "................"
            "................"];

    case "subjects" % person beside a roster list
        rows = [ ...
            "................"
            "...kkkk........."
            "..kssssk........"
            "..kssssk...bbbbb"
            "..kssssk........"
            "...kkkk....bbbbb"
            "..kkkkkk........"
            ".kssssssk..bbbbb"
            ".kssssssk......."
            ".kssssssk..bbbbb"
            ".kssssssk......."
            ".kkkkkkkk......."
            "................"
            "................"
            "................"
            "................"];

    case "removesubject" % person with a red minus
        rows = [ ...
            "................"
            "...kkkk........."
            "..kssssk........"
            "..kssssk........"
            "..kssssk........"
            "...kkkk........."
            "..kkkkkk..rrrrrr"
            ".kssssssk.rrrrrr"
            ".kssssssk......."
            ".kssssssk......."
            ".kssssssk......."
            ".kkkkkkkk......."
            "................"
            "................"
            "................"
            "................"];

    case "savedata" % green arrow down into a tray
        rows = [ ...
            "................"
            ".......gg......."
            ".......gg......."
            ".......gg......."
            ".......gg......."
            ".......gg......."
            ".....gggggg....."
            "......gggg......"
            ".......gg......."
            "................"
            ".ss..........ss."
            ".ss..........ss."
            ".ssssssssssssss."
            ".ssssssssssssss."
            "................"
            "................"];

    case "ontop"   % pushpin
        rows = [ ...
            "................"
            ".....kkkkkk....."
            ".....kbbbbk....."
            ".....kbbbbk....."
            ".....kbbbbk....."
            "....kkkkkkkk...."
            "....kbbbbbbk...."
            "....kkkkkkkk...."
            ".......kk......."
            ".......kk......."
            ".......kk......."
            ".......k........"
            "................"
            "................"
            "................"
            "................"];

    case "customize" % gear
        rows = [ ...
            "................"
            ".......ss......."
            "...ss.ssss.ss..."
            "...ssssssssss..."
            "....ssssssss...."
            "....ssssssss...."
            "...sss....sss..."
            ".sssss....sssss."
            ".sssss....sssss."
            "...sss....sss..."
            "....ssssssss...."
            "....ssssssss...."
            "...ssssssssss..."
            "...ss.ssss.ss..."
            ".......ss......."
            "................"];

    case "protocol" % document with a pencil
        rows = [ ...
            "................"
            "..kkkkkkkkk....."
            "..kwwwwwwwk..oo."
            "..kwssssswk.oo.."
            "..kwwwwwwwkoo..."
            "..kwssssswoo...."
            "..kwwwwwwoo....."
            "..kwssssook....."
            "..kwwwwoowk....."
            "..kwssoowwk....."
            "..kwwttwwwk....."
            "..kwkwwwwwk....."
            "..kkkkkkkkk....."
            "................"
            "................"
            "................"];

    case "liveview" % eye
        rows = [ ...
            "................"
            "................"
            "................"
            ".....kkkkkk....."
            "...kkwwwwwwkk..."
            "..kwwwwbbwwwwk.."
            ".kwwwwbkkbwwwwk."
            ".kwwwwbkkbwwwwk."
            "..kwwwwbbwwwwk.."
            "...kkwwwwwwkk..."
            ".....kkkkkk....."
            "................"
            "................"
            "................"
            "................"
            "................"];

    case "record"  % record dot
        rows = [ ...
            "................"
            "................"
            "......rrrr......"
            "....rrrrrrrr...."
            "...rrRRRrrrrr..."
            "...rRRrrrrrrr..."
            "..rrrrrrrrrrrr.."
            "..rrrrrrrrrrrr.."
            "..rrrrrrrrrrrr.."
            "..rrrrrrrrrrrr.."
            "...rrrrrrrrrr..."
            "...rrrrrrrrrr..."
            "....rrrrrrrr...."
            "......rrrr......"
            "................"
            "................"];

    case "wiki"    % open book
        rows = [ ...
            "................"
            "................"
            "................"
            ".bbbbb....bbbbb."
            ".bwwwwb..bwwwwb."
            ".bwwwwwbbwwwwwb."
            ".bwsswwbbwwsswb."
            ".bwwwwwbbwwwwwb."
            ".bwsswwbbwwsswb."
            ".bwwwwwbbwwwwwb."
            ".bbwwwwbbwwwwbb."
            "..bbbwwbbwwbbb.."
            "....bbbbbbbb...."
            "................"
            "................"
            "................"];

    % ---- roster window (gui.SubjectManager) ----------------------------

    case "rosterfile" % database cylinder -- the roster file itself
        rows = [ ...
            "................"
            "................"
            "...bbbbbbbbbb..."
            "..bbbbbbbbbbbb.."
            "...bbbbbbbbbb..."
            "..bb........bb.."
            "..bb........bb.."
            "...bbbbbbbbbb..."
            "..bbbbbbbbbbbb.."
            "...bbbbbbbbbb..."
            "..bb........bb.."
            "..bb........bb.."
            "...bbbbbbbbbb..."
            "..bbbbbbbbbbbb.."
            "...bbbbbbbbbb..."
            "................"];

    case "import"  % document with a green arrow leading out of it
        rows = [ ...
            "................"
            ".kkkkkkk........"
            ".kwwwwwk........"
            ".kwssswk........"
            ".kwwwwwk........"
            ".kwssswk..g....."
            ".kwwwwwk..gg...."
            ".kwssswkggggg..."
            ".kwwwwwkggggggg."
            ".kwssswkggggg..."
            ".kwwwwwk..gg...."
            ".kwssswk..g....."
            ".kwwwwwk........"
            ".kkkkkkk........"
            "................"
            "................"];

    case "export"  % table with an arrow leaving it downward
        rows = [ ...
            "................"
            ".kkkkkkkkk......"
            ".kwwwkwwwk......"
            ".kkkkkkkkk......"
            ".kwwwkwwwk..bb.."
            ".kwwwkwwwk..bb.."
            ".kkkkkkkkk..bb.."
            ".kwwwkwwwk..bb.."
            ".kwwwkwwwk..bb.."
            ".kkkkkkkkkbbbbbb"
            "...........bbbb."
            "............bb.."
            "................"
            "................"
            "................"
            "................"];

    case "projectnew" % folder with a green plus
        rows = [ ...
            "................"
            "................"
            "kkkkk..........."
            "kyyyykkkkkk....."
            "kyyyyyyyyyk....."
            "kYYYYYYYYYk....."
            "kYYYYYYYYYk....."
            "kYYYYYYYYYk....."
            "kYYYYYYYYYk.gg.."
            "kYYYYYYYYYk.gg.."
            "kYYYYYYYYYgggggg"
            "kYYYYYYYYYgggggg"
            "kkkkkkkkkkk.gg.."
            "............gg.."
            "................"
            "................"];

    case "projectedit" % folder with a pencil
        rows = [ ...
            "................"
            "................"
            "kkkkk..........."
            "kyyyykkkkkk....."
            "kyyyyyyyyyk....."
            "kYYYYYYYYYk....."
            "kYYYYYYYYYk....."
            "kYYYYYYYYYk....."
            "kYYYYYYYYYk...oo"
            "kYYYYYYYYYk..oo."
            "kYYYYYYYYYk.oo.."
            "kYYYYYYYYYkoo..."
            "kkkkkkkkkktt...."
            "..........t....."
            "................"
            "................"];

    case "projectdelete" % folder with a red cross
        rows = [ ...
            "................"
            "................"
            "kkkkk..........."
            "kyyyykkkkkk....."
            "kyyyyyyyyyk....."
            "kYYYYYYYYYk....."
            "kYYYYYYYYYk....."
            "kYYYYYYYYYk....."
            "kYYYYYYYYYrr..rr"
            "kYYYYYYYYYkrrrr."
            "kYYYYYYYYYk.rr.."
            "kYYYYYYYYYk.rr.."
            "kkkkkkkkkkkrrrr."
            "..........rr..rr"
            "................"
            "................"];

    case "subjectedit" % person with a pencil
        rows = [ ...
            "................"
            "...kkkk........."
            "..kssssk........"
            "..kssssk........"
            "..kssssk........"
            "...kkkk........."
            "..kkkkkk......oo"
            ".kssssssk....oo."
            ".kssssssk...oo.."
            ".kssssssk..oo..."
            ".kssssssk.oo...."
            ".kkkkkkkktt....."
            ".........t......"
            "................"
            "................"
            "................"];

    case "subjectdelete" % person with a red cross
        rows = [ ...
            "................"
            "...kkkk........."
            "..kssssk........"
            "..kssssk........"
            "..kssssk........"
            "...kkkk........."
            "..kkkkkk........"
            ".kssssssk.rr..rr"
            ".kssssssk..rrrr."
            ".kssssssk...rr.."
            ".kssssssk...rr.."
            ".kkkkkkkk..rrrr."
            "..........rr..rr"
            "................"
            "................"
            "................"];

    case "addtoproject" % green arrow going into a folder
        rows = [ ...
            "................"
            "................"
            "................"
            ".......kkkk....."
            ".......kyyykkkkk"
            "..g....kyyyyyyyk"
            "..gg...kYYYYYYYk"
            "ggggg..kYYYYYYYk"
            "gggggggkYYYYYYYk"
            "ggggg..kYYYYYYYk"
            "..gg...kYYYYYYYk"
            "..g....kYYYYYYYk"
            ".......kkkkkkkkk"
            "................"
            "................"
            "................"];

    case "removefromproject" % red arrow coming out of a folder
        rows = [ ...
            "................"
            "................"
            "................"
            ".......kkkk....."
            ".......kyyykkkkk"
            "....r..kyyyyyyyk"
            "...rr..kYYYYYYYk"
            "..rrrrrkYYYYYYYk"
            "rrrrrrrkYYYYYYYk"
            "..rrrrrkYYYYYYYk"
            "...rr..kYYYYYYYk"
            "....r..kYYYYYYYk"
            ".......kkkkkkkkk"
            "................"
            "................"
            "................"];

    case "retire"  % arrow going down into an archive box
        rows = [ ...
            "................"
            "......sss......."
            "......sss......."
            "...sssssssss...."
            "....sssssss....."
            ".....sssss......"
            "......sss......."
            ".kkkkkkkkkkkkkk."
            ".kssssssssssssk."
            ".kkkkkkkkkkkkkk."
            "..kssssssssssk.."
            "..kssssssssssk.."
            "..kssssssssssk.."
            "..kkkkkkkkkkkk.."
            "................"
            "................"];

    case "restore" % arrow coming back up out of the box
        rows = [ ...
            "................"
            "......ggg......."
            ".....ggggg......"
            "....ggggggg....."
            "...ggggggggg...."
            "......ggg......."
            "......ggg......."
            ".kkkkkkkkkkkkkk."
            ".kssssssssssssk."
            ".kkkkkkkkkkkkkk."
            "..kssssssssssk.."
            "..kssssssssssk.."
            "..kssssssssssk.."
            "..kkkkkkkkkkkk.."
            "................"
            "................"];

    case "tosession" % green arrow going into a session window
        rows = [ ...
            "................"
            "................"
            "................"
            ".......kkkkkkkkk"
            ".......kbbbbbbbk"
            "..g....kwwwwwwwk"
            "..gg...kwwwwwwwk"
            "ggggg..kwwwwwwwk"
            "gggggggkwwwwwwwk"
            "ggggg..kwwwwwwwk"
            "..gg...kwwwwwwwk"
            "..g....kwwwwwwwk"
            ".......kkkkkkkkk"
            "................"
            "................"
            "................"];

    % ---- behavior windows (gui.ScreenCapture) --------------------------

    case "camera"  % camera body with a lens and a flash
        rows = [ ...
            "................"
            "................"
            "....kkkkk......."
            "....kkkkk......."
            ".kkkkkkkkkkkkkk."
            ".kssssssssswwsk."
            ".kssssssssssssk."
            ".ksssskkkkssssk."
            ".kssskwbbbksssk."
            ".kssskbbbbksssk."
            ".kssskbbbbksssk."
            ".kssskbbbbksssk."
            ".ksssskkkkssssk."
            ".kkkkkkkkkkkkkk."
            "................"
            "................"];

    % ---- behavior GUI component toolbar (gui.ComponentToolbar) ---------
    %
    % One glyph per display component the toolbar can open in its own window.
    % The name is the component's class name without its package, lowercased,
    % with underscores removed: gui.Parameter_Monitor -> "parametermonitor".
    % gui.ComponentToolbar builds that name itself and falls back to
    % "component" when there is no case for it, so a new gui.PopOut adopter
    % works on the toolbar before anyone draws its icon -- adding a case here
    % is what replaces the generic two-window glyph with its own.

    case "parameterscatter" % axes with scattered points
        rows = [ ...
            "................"
            "..k............."
            "..k............."
            "..k........rr..."
            "..k..bb....rr..."
            "..k..bb........."
            "..k......gg....."
            "..k......gg....."
            "..k.........bb.."
            "..k...rr....bb.."
            "..k...rr........"
            "..k............."
            "..k............."
            "..kkkkkkkkkkkkk."
            "................"
            "................"];

    case "history"  % trial table, each row flagged by its outcome
        rows = [ ...
            "................"
            ".kkkkkkkkkkkkkk."
            ".kssssssssssssk."
            ".kssssssssssssk."
            ".kkkkkkkkkkkkkk."
            ".kggkwwwwwwwwwk."
            ".kggkwwwwwwwwwk."
            ".kkkkkkkkkkkkkk."
            ".krrkwwwwwwwwwk."
            ".krrkwwwwwwwwwk."
            ".kkkkkkkkkkkkkk."
            ".kbbkwwwwwwwwwk."
            ".kbbkwwwwwwwwwk."
            ".kkkkkkkkkkkkkk."
            "................"
            "................"];

    case "sessionperformance" % rising bars under a check mark
        rows = [ ...
            "...............g"
            "..............gg"
            ".........g...gg."
            ".........gg.gg.."
            "..........ggg..."
            "................"
            "..........bbb..."
            "......bbb.bbb..."
            "......bbb.bbb..."
            "......bbb.bbb..."
            "..bbb.bbb.bbb..."
            "..bbb.bbb.bbb..."
            "..bbb.bbb.bbb..."
            "..kkkkkkkkkkkk.."
            "................"
            "................"];

    case "nexttrial" % skip-forward mark: what comes next
        rows = [ ...
            "................"
            "................"
            "................"
            "..b......kk....."
            "..bb.....kk....."
            "..bbbb...kk....."
            "..bbbbb..kk....."
            "..bbbbbb.kk....."
            "..bbbbbb.kk....."
            "..bbbbb..kk....."
            "..bbbb...kk....."
            "..bb.....kk....."
            "..b......kk....."
            "................"
            "................"
            "................"];

    case "parametermonitor" % panel showing a live trace, with a lamp
        rows = [ ...
            "................"
            ".kkkkkkkkkkkkkk."
            ".kwwwwwwwwwggwk."
            ".kwwwwwwwwwggwk."
            ".kwwwwwwwwwwwwk."
            ".kwwwwwwwwwwwwk."
            ".kwwwgggggwwwwk."
            ".kwwwgwwwgwwwwk."
            ".kwwwgwwwgwwwwk."
            ".kwwwgwwwgwwwwk."
            ".kwgggwwwggggwk."
            ".kwwwwwwwwwwwwk."
            ".kkkkkkkkkkkkkk."
            "................"
            "................"
            "................"];

    case "psychplot" % psychometric function rising to a plateau
        rows = [ ...
            "................"
            "..k............."
            "..k............."
            "..k......bbbbbb."
            "..k.....b......."
            "..k.....b......."
            "..k....b........"
            "..k....b........"
            "..k...b........."
            "..k...b........."
            "..k..b.........."
            "..kbbb.........."
            "..k............."
            "..kkkkkkkkkkkkk."
            "................"
            "................"];

    case "syringepump" % syringe: plunger, filled barrel, needle
        rows = [ ...
            "................"
            "................"
            "................"
            "................"
            ".s..kkkkkkkkk..."
            ".s..kbbbbwwwk..."
            ".s..kbbbbwwwk..."
            ".ssskbbbbwwwksss"
            ".ssskbbbbwwwksss"
            ".s..kbbbbwwwk..."
            ".s..kbbbbwwwk..."
            ".s..kkkkkkkkk..."
            "................"
            "................"
            "................"
            "................"];

    case "staircase" % steps descending to a reversal, over a threshold
        rows = [ ...
            "................"
            "................"
            "................"
            ".ooo............"
            "...o............"
            "...ooo.....ooo.."
            ".....o.....o...."
            ".....ooo.ooo...."
            ".......o.o......"
            ".......ooo......"
            "................"
            "ss.ss.ss.ss.ss.."
            "................"
            "................"
            "................"
            "................"];

    case "component" % generic: a window lifted out of another window
        rows = [ ...
            "................"
            ".....kkkkkkkkkkk"
            ".....kbbbbbbbbbk"
            ".....kbbbbbbbbbk"
            ".....kkkkkkkkkkk"
            "kkkkkkwwwwwwwwwk"
            "ksssskwwwwwwwwwk"
            "ksssskwwwwwwwwwk"
            "kkkkkkwwwwwwwwwk"
            "kwwwwkwwwwwwwwwk"
            "kwwwwkkkkkkkkkkk"
            "kwwwwwwwwk......"
            "kwwwwwwwwk......"
            "kwwwwwwwwk......"
            "kkkkkkkkkk......"
            "................"];

    otherwise
        error('epsych:gui:UnknownToolbarIcon','Unknown toolbar icon "%s".',name)
end

icon = localIconFromMask(rows, C);
cache.(key) = icon;

end

% -----------------------------------------------------------------------
function icon = localIconFromMask(rows, C)
% Convert a string mask into an m-by-n-by-3 truecolor array. '.' pixels stay
% NaN, which uipushtool/uitoggletool render as transparent.
nR = numel(rows);
nC = strlength(rows(1));
icon = nan(nR, nC, 3);
for i = 1:nR
    line = char(rows(i));
    for j = 1:numel(line)
        if line(j) ~= '.'
            icon(i,j,:) = C.(line(j));
        end
    end
end
end
