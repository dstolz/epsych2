function smoke_test_nexttrial_fontsize()
% smoke_test_nexttrial_fontsize()
% Exercise gui.components.NextTrial's font-size control: the FontSize property, the
% setFontSize method, clamping, the right-click Font Size menu, and the
% saved size outranking the constructor default on the next session.
% Headless-safe: every figure is closed and every preference this test
% writes is restored on exit.
%
%   matlab -batch "run('tmp/smoke_test_nexttrial_fontsize.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

PREF_GROUP = 'epsych2_gui_NextTrial';
PREF_TAG   = 'smoke_test_nexttrial_fontsize';
saved = [];
if ispref(PREF_GROUP, PREF_TAG), saved = getpref(PREF_GROUP, PREF_TAG); end
cleanupObj = onCleanup(@() cleanupAll(PREF_GROUP, PREF_TAG, saved));

hub = epsych.EventHub();
fig = uifigure('Visible','off','Tag',PREF_TAG,'Position',[100 100 380 300]);

% 1. Constructor default and programmatic control -------------------------
NT = gui.components.NextTrial(hub, fig, PreferenceTag=PREF_TAG);
assert(NT.FontSize == 16, 'the default table font size is 16pt');
assert(NT.TableH.FontSize == 16, 'the table should be built at that size');

NT.FontSize = 24;
assert(NT.FontSize == 24 && NT.TableH.FontSize == 24, ...
    'assigning FontSize should resize the table');

NT.setFontSize(11.4);
assert(NT.FontSize == 11, 'a fractional size should round');
fprintf('PASS: FontSize property and setFontSize\n');

% 2. Clamping rather than refusing ----------------------------------------
NT.setFontSize(500);
assert(NT.FontSize == 72, 'an oversized value should clamp');
NT.setFontSize(2);
assert(NT.FontSize == 6, 'an undersized value should clamp');
assertThrows(@() NT.setFontSize(0), 'a non-positive size should still be rejected');
assertThrows(@() NT.setFontSize(NaN), 'a non-finite size should still be rejected');
NT.setFontSize(16);
fprintf('PASS: font sizes clamp to a legible range\n');

% 3. The right-click menu -------------------------------------------------
assert(~isempty(NT.ContextMenu) && isvalid(NT.ContextMenu), 'a context menu should exist');
NT.ContextMenu.ContextMenuOpeningFcn([],[]);   % builds the checkable entries

fontMenu = findobj(NT.ContextMenu,'Text','Font Size');
assert(~isempty(fontMenu), 'the menu should offer Font Size');
entries = string({fontMenu.Children.Text});
assert(any(entries == "16 pt") && any(entries == "Larger") ...
    && any(entries == "Smaller") && any(entries == "Custom..."), ...
    'the font menu should offer presets, steps, and a prompt');
assert(findobj(fontMenu,'Text','16 pt').Checked == "on", 'the active size should be checked');
assert(findobj(fontMenu,'Text','Custom...').Checked == "off", ...
    'Custom is checked only for a size that is not a preset');

findobj(fontMenu,'Text','24 pt').MenuSelectedFcn([],[]);
assert(NT.FontSize == 24 && NT.TableH.FontSize == 24, ...
    'choosing a preset should resize the table');

NT.ContextMenu.ContextMenuOpeningFcn([],[]);
fontMenu = findobj(NT.ContextMenu,'Text','Font Size');
findobj(fontMenu,'Text','Larger').MenuSelectedFcn([],[]);
assert(NT.FontSize == 26, 'Larger should step up 2pt');
findobj(fontMenu,'Text','Smaller').MenuSelectedFcn([],[]);
findobj(fontMenu,'Text','Smaller').MenuSelectedFcn([],[]);
assert(NT.FontSize == 22, 'Smaller should step down 2pt');

NT.ContextMenu.ContextMenuOpeningFcn([],[]);
fontMenu = findobj(NT.ContextMenu,'Text','Font Size');
assert(findobj(fontMenu,'Text','Custom...').Checked == "on", ...
    'a size off the preset list should check Custom');
fprintf('PASS: the Font Size menu sets and reports the size\n');

% 4. The field menu still works alongside it ------------------------------
assert(~isempty(findobj(NT.ContextMenu,'Text','Show Field')), ...
    'the field menu should still be built when the menu opens');
fprintf('PASS: the field menu is unaffected\n');

% 5. Persistence across sessions ------------------------------------------
NT.setFontSize(20);
NT.setFields(["Depth","Lowpass"]);
delete(NT);

NT2 = gui.components.NextTrial(hub, fig, FontSize=16, PreferenceTag=PREF_TAG);
assert(NT2.FontSize == 20 && NT2.TableH.FontSize == 20, ...
    'a saved size should outrank the constructor default');
assert(isequal(NT2.SelectedFields, ["Depth","Lowpass"]), ...
    'the field selection should still persist alongside it');
delete(NT2);
fprintf('PASS: the operator''s font size persists across sessions\n');

close(fig);
fprintf('\nALL PASS: gui.components.NextTrial font size\n');
end


function assertThrows(fcn, msg)
threw = false;
try
    fcn();
catch
    threw = true;
end
assert(threw, msg);
end


function cleanupAll(prefGroup, prefTag, saved)
if isempty(saved)
    if ispref(prefGroup, prefTag), rmpref(prefGroup, prefTag); end
else
    setpref(prefGroup, prefTag, saved);
end
delete(findall(groot,'Type','figure','-and','Tag',prefTag));
end
