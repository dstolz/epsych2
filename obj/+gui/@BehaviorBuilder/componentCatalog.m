function cat = componentCatalog()
% cat = gui.BehaviorBuilder.componentCatalog
% The one table of placeable component types (teensy.Templates pattern).
% Drives the palette, tooltips, placeholder labels, psych gating, the
% pop-out checkbox, and codegen dispatch — new components are added HERE
% plus one emitter branch in generateCode.m.
%
% Fields per entry:
%   Type        spec/codegen identifier
%   Display     palette + placeholder name
%   Category    'Controls' | 'Displays' | 'Add-ons'
%   Description palette tooltip
%   NeedsPsych  requires spec.Psych.Type ~= 'none'
%   PsychTypes  restrict to these analyses ({} = any)
%   Poppable    supports a generated pop-out button (gui.PopOut adopters)
%   HasOptions  has a configureRegion dialog beyond Label/span
%   EmitClass   component class whose PreferenceTag must be uniqued when
%               the type is placed more than once ('' = stateless)

rows = {
 'ControlColumn' 'Control Column'      'Controls' 'Titled, scrollable column of editable parameter controls with an automatic Update button' false {}            false true  ''
 'ButtonRow'     'Button Row'          'Controls' 'Row of trigger/toggle buttons (optionally with a Screen Capture button)'                  false {}            false true  ''
 'Monitor'       'Parameter Monitor'   'Displays' 'Polled read-only display of chosen parameters (table or text)'                            false {}            true  true  'gui.components.Parameter_Monitor'
 'NextTrial'     'Next Trial'          'Displays' 'Upcoming-trial display driven by NewTrial events'                                         false {}            true  false 'gui.components.NextTrial'
 'Performance'   'Session Performance' 'Displays' 'Session summary panel: rates, counts, d'''                                                false {}            true  false 'gui.components.SessionPerformance'
 'Scatter'       'Parameter Scatter'   'Displays' 'Generic X/Y/color scatter over trial parameters'                                          false {}            true  true  'gui.components.ParameterScatter'
 'History'       'Trial History'       'Displays' 'Per-trial outcome table (requires a psych analysis)'                                      true  {}            true  false 'gui.components.History'
 'PsychPlot'     'Psych Plot'          'Displays' 'Psychometric plot (requires a psych analysis)'                                            true  {}            true  false ''
 'StaircasePlot' 'Staircase Plot'      'Displays' 'Staircase track with reversals (requires a Staircase analysis)'                           true  {'Staircase'} true  false ''
 'SlidingWindow' 'Sliding Window'      'Displays' 'Hit rate, FA rate and d'' over trials, cumulative or windowed (requires a psych analysis)'  true  {}            false false ''
 'OnlinePlot'    'Online Plot'         'Displays' 'Real-time traces of hardware activity for named parameters or a bitmask bank'             false {}            false true  ''
 'BufferPlot'    'Buffer Plot'         'Displays' 'Contents of buffer parameters, redrawn once per completed trial'                          false {}            true  true  'gui.components.BufferPlot'
 'SessionClock'  'Session Clock'       'Displays' 'Clock, session duration, and time-since-trial readouts'                                   false {}            false false 'gui.components.SessionClock'
 'TrialTimer'    'Trial Timer'         'Displays' 'Elapsed time since the last completed trial'                                              false {}            false false ''
 'ModeIndicator' 'Mode Indicator'      'Displays' 'Lamp showing the current run mode'                                                        false {}            false false ''
 'Notes'         'Session Notes'       'Add-ons'  'Operator note pad: a typed line stamped with the trial, saved with the data'              false {}            true  true  'gui.components.Notes'
 'SyringePump'   'Syringe Pump'        'Add-ons'  'Operator panel for an NE-1000 reward pump (uses saved pump preferences)'                  false {}            true  true  'gui.components.SyringePump'
 'ScreenCapture' 'Screen Capture'      'Add-ons'  'Button that copies the whole window to the clipboard'                                     false {}            false false ''
 'SessionGate'   'Session Gate'        'Add-ons'  'Begin Experiment button; the session holds until the operator presses it'                 false {}            false true  ''
 'PhaseSelector' 'Phase Selector'      'Add-ons'  'Save and load named parameter phases from a folder'                                       false {}            false true  ''
 'StatusBar'     'Status Bar'          'Add-ons'  'Footer status line, green for messages and red for errors'                                false {}            false true  ''
 'FilenameField' 'Filename Field'      'Add-ons'  'Edit field that validates the session data filename'                                      false {}            false true  ''
 };

n = size(rows,1);
proto = struct('Type','','Display','','Category','','Description','', ...
    'NeedsPsych',false,'Poppable',false,'HasOptions',false,'EmitClass','');
proto.PsychTypes = {}; % assigned separately: struct('f',{{}}) makes an empty ARRAY
cat = repmat(proto, 1, n);
for i = 1:n
    cat(i).Type        = rows{i,1};
    cat(i).Display     = rows{i,2};
    cat(i).Category    = rows{i,3};
    cat(i).Description = rows{i,4};
    cat(i).NeedsPsych  = rows{i,5};
    cat(i).PsychTypes  = rows{i,6};
    cat(i).Poppable    = rows{i,7};
    cat(i).HasOptions  = rows{i,8};
    cat(i).EmitClass   = rows{i,9};
end

% Anything else in the gui.components package joins the palette on its own.
% A component added to that package needs NO edit here: it is discovered,
% its own gui.ComponentSpec supplies the label, category, description and
% options, and generateCode's generic emitter writes the obj.add call.
%
% The rows above are kept rather than derived because they carry two things
% a spec does not: the option field names saved .eblt files already use, and
% the HasOptions flag that says which types have a bespoke configureRegion
% dialog. Discovery appends; it never overrides.
cat = [cat, gui.BehaviorBuilder.discoveredEntries_({cat.EmitClass}, {cat.Type})];
end
