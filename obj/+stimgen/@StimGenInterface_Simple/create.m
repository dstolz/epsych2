function create(obj)
if isempty(obj.parent), obj.parent = uifigure('Name','StimGen'); end

f = obj.parent;

pos = f.Position;

pos = getpref('StimGenInterface','parent_pos',pos);

f.Position = pos;
f.Scrollable = 'on';
f.DeleteFcn = @obj.delete_main_figure;
%movegui(f,'onscreen'); % do this after all gui components have loaded



g = uigridlayout(f);
g.ColumnWidth = {300,'1x',300};
g.RowHeight   = {250,'1x'};


% signal plot
ax = uiaxes(g);
ax.Layout.Column = [1 3];
ax.Layout.Row = 1;
grid(ax,'on');
box(ax,'on');
xlabel(ax,'time (s)');
obj.handles.SignalPlotAx = ax;

h = line(ax,nan,nan);
obj.handles.SignalPlotLine = h;

% stimgen interface
tg = uitabgroup(g);
tg.Layout.Column = [1 2];
tg.Layout.Row    = 2;
tg.Tag = 'StimGenTabs';
tg.TabLocation = 'left';
tg.SelectionChangedFcn = @obj.stimtype_changed;
obj.handles.TabGroup = tg;

for i = 1:length(obj.sgTypes)
    try
        sgt = obj.sgTypes{i};
        sgo = obj.sgObj{i};
        fnc = @sgo.create_gui;
        t = uitab(tg,'Tag',sgt,'Title',sgo.DisplayName,'CreateFcn',fnc);
        t.Scrollable = 'on';
        obj.handles.Tabs.(sgt) = t;


    catch me
        t.Title = sprintf('%s ERROR',sgt);
        disp(me)
        rethrow(me)
    end
end

pause(1); % neeeded?
obj.stimtype_changed(tg);



% side-bar grid
sbg = uigridlayout(g);
sbg.Layout.Column = 3;
sbg.Layout.Row = 2;
sbg.ColumnWidth = {'1x', '1x'};
sbg.RowHeight = {30,30,30,30,200,30};

R = 1;

% stim name field
h = uilabel(sbg);
h.Layout.Column = 1;
h.Layout.Row = R;
h.Text = 'Stim Name:';
h.HorizontalAlignment = 'right';
h.FontSize = 16;


h = uieditfield(sbg,'Tag','StimName');
h.Layout.Column = 2;
h.Layout.Row = R;
h.Value = '';
h.ValueChangedFcn = @obj.update_stim_name;
obj.handles.StimName = h;

R = R + 1;            

% inter-stimulus interval
h = uilabel(sbg,'Text','Inter-Stimulus Interval (s)');
h.Tooltip = "Time between onsets of consecutive stimulus presentations in seconds. May be a range of values, e.g., 0.5 1.5";
h.Layout.Column = 1;
h.Layout.Row = R;
h.HorizontalAlignment = 'right';
obj.handles.ISILabel = h;

h = uieditfield(sbg,'Tag','ISI');
h.Layout.Column = 2;
h.Layout.Row = R;
h.Value = '1.00';
h.ValueChangedFcn = @obj.update_isi;
obj.handles.ISI = h;
obj.update_isi;

R = R + 1;

% rep field
h = uilabel(sbg,'Text','# Presentations');
h.Layout.Column = 1;
h.Layout.Row = R;
h.HorizontalAlignment = 'right';
obj.handles.RepsLabel = h;

h = uieditfield(sbg,'numeric','Tag','Reps');
h.Layout.Column = 2;
h.Layout.Row = R;
h.Limits = [1 1e6];
h.RoundFractionalValues = 'on';
h.ValueDisplayFormat = '%d reps';
h.Value = 20;
h.ValueChangedFcn = @obj.update_reps;
obj.handles.Reps = h;
            


R = R + 1;

% stimulus counter
h = uilabel(sbg);
h.Layout.Column = [1 2];
h.Layout.Row = R;
h.Text = '---';
h.FontSize = 18;
h.FontWeight = 'bold';
obj.handles.StimulusCounter = h;

R = R + 1;




% run/stop/pause buttons
h = uibutton(sbg);
h.Layout.Column = 1;
h.Layout.Row = R;
h.Text = 'Run';
h.FontSize = 18;
h.FontWeight = 'bold';
h.ButtonPushedFcn = @obj.playback_control;
h.Enable = 'on';
obj.handles.RunStopButton = h;

h = uibutton(sbg);
h.Layout.Column = 2;
h.Layout.Row = R;
h.Text = 'Pause';
h.FontSize = 18;
h.FontWeight = 'bold';
h.ButtonPushedFcn = @obj.playback_control;
h.Enable = 'off';
obj.handles.PauseButton = h;

R = R + 1;

% play stim
h = uibutton(sbg,'Tag','Play');
h.Layout.Row = R;
h.Layout.Column = [1 2];
h.Text = 'Play Stim';
h.ButtonPushedFcn = @obj.play_current_stim_audio;
obj.handles.PlayStimAudio = h;



% toolbar
hf = uimenu(obj.parent,'Text','&File','Accelerator','F');

h = uimenu(hf,'Tag','menu_Load','Text','&Load','Accelerator','L', ...
    'MenuSelectedFcn',@(~,~) obj.load_config);

h = uimenu(hf,'Tag','menu_Save','Text','&Save','Accelerator','S', ...
    'MenuSelectedFcn',@(~,~) obj.save_config);

h = uimenu(hf,'Tag','menu_Save','Text','&Calibration','Accelerator','A', ...
    'MenuSelectedFcn',@(~,~) obj.set_calibration);




movegui(f,'onscreen');

