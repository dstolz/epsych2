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
g.RowHeight   = {150,'1x',25};


% signal plot
ax = uiaxes(g);
ax.Layout.Column = [1 2];
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

flag = 1;
for i = 1:length(obj.sgTypes)
    try
        sgt = obj.sgTypes{i};
        sgo = obj.sgObjs{i};
        fnc = @sgo.create_gui;
        t = uitab(tg,'Tag',sgt,'Title',sgo.DisplayName,'CreateFcn',fnc);
        t.Scrollable = 'on';
        obj.handles.Tabs.(sgt) = t;
        addlistener(sgo,'Signal','PostSet',@obj.update_signal_plot);
        if flag, obj.update_signal_plot; flag = 0; end
    catch me
        t.Title = sprintf('%s ERROR',sgt);
        disp(me)
        rethrow(me)
    end
end

%             % sample rate
%             h = uieditfield(g,'numeric','Tag','SampleRate');
%             h.Layout.Row = 3;
%             h.Layout.Column = 1;
%             h.Limits = [1 1e6];
%             h.ValueDisplayFormat = '%.3f Hz';
%             h.Value = 48828.125;
%             h.ValueChangedFcn = @obj.update_samplerate;

% play stim
h = uibutton(g,'Tag','Play');
h.Layout.Row = 3;
h.Layout.Column = 2;
h.Text = 'Play Stim';
h.ButtonPushedFcn = @obj.play_current_stim_audio;
obj.handles.PlayStimAudio = h;



% side-bar grid
sbg = uigridlayout(g);
sbg.Layout.Column = 3;
sbg.Layout.Row = [1 3];
sbg.ColumnWidth = {'1x', '1x'};
sbg.RowHeight = repmat({30},1,9);

R = 1;

% stimulus counter
h = uilabel(sbg);
h.Layout.Column = [1 2];
h.Layout.Row = R;
h.Text = '---';
h.FontSize = 18;
h.FontWeight = 'bold';
obj.handles.StimulusCounter = h;

R = R + 1;

% stim name field
h = uilabel(sbg);
h.Layout.Column = 1;
h.Layout.Row = R;
h.Text = 'Stim Name:';
h.HorizontalAlignment = 'right';
h.FontSize = 16;
obj.handles.StimulusCounter = h;

h = uieditfield(sbg,'Tag','StimName');
h.Layout.Column = 2;
h.Layout.Row = R;
h.Value = '';
obj.handles.StimName = h;

R = R + 1;            

% inter-stimulus interval
h = uilabel(sbg,'Text','ISI');
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

R = R + 1;

% rep field
h = uieditfield(sbg,'numeric','Tag','Reps');
h.Layout.Column = 1;
h.Layout.Row = R;
h.Limits = [1 1e6];
h.RoundFractionalValues = 'on';
h.ValueDisplayFormat = '%d reps';
h.Value = 20;
obj.handles.Reps = h;
            

% add stim button
h = uibutton(sbg,'Tag','AddStimToList');
h.Layout.Column = 2;
h.Layout.Row = R;
h.Text = 'Add';
h.FontSize = 16;
h.FontWeight = 'bold';
h.ButtonPushedFcn = @obj.add_stim_to_list;
obj.handles.AddStimToList = h;

R = R + 1;

% stimulus list
h = uitree(sbg,'Tag','StimObjList');
h.SelectionChangedFcn = @obj.onTreeSelectionChanged;
h.Multiselect = 'off';
h.Layout.Column = [1 2];
h.Layout.Row = [R R+5];
obj.handles.StimObjList = h;
obj.populateTree();

R = R + 6;

%             % advance stim button
%             h = uibutton(sbg,'Tag','AdvanceStimFromList');
%             h.Layout.Column = 2;
%             h.Layout.Row = R;
%             h.Text = 'Remove';
%             h.FontSize = 16;
%             h.FontWeight = 'bold';
%             h.ButtonPushedFcn = @obj.advance_stim;
%             obj.handles.AdvanceStimFromList = h;

% remove stim button
h = uibutton(sbg,'Tag','RemStimFromList');
h.Layout.Column = 2;
h.Layout.Row = R;
h.Text = 'Remove';
h.FontSize = 16;
h.FontWeight = 'bold';
h.ButtonPushedFcn = @obj.rem_stim_from_list;
obj.handles.RemStimFromList = h;

R = R + 1;

% playmode dropdown
h = uidropdown(sbg,'Tag','PlayMode');
h.Layout.Column = [1 2];
h.Layout.Row = R;
w = which('stimgen.StimGenInterface');
p = fileparts(w);
d = dir(fullfile(p,'stimselect_*.m'));
itmr = cellfun(@(a) a(1:end-2),{d.name},'uni',0);
itm  = cellfun(@(a) a(find(a=='_',1)+1:end),itmr,'uni',0);
itmf = cellfun(@str2func,itmr,'uni',0);
h.Items = itm;
h.ItemsData = itmf;
obj.handles.SelectionTypeList = h;


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



% toolbar
hf = uimenu(obj.parent,'Text','&File','Accelerator','F');

h = uimenu(hf,'Tag','menu_Load','Text','&Load','Accelerator','L', ...
    'MenuSelectedFcn',@(~,~) obj.load_config);
h = uimenu(hf,'Tag','menu_Save','Text','&Save','Accelerator','S', ...
    'MenuSelectedFcn',@(~,~) obj.save_config);

h = uimenu(hf,'Tag','menu_Save','Text','&Calibration','Accelerator','C', ...
    'MenuSelectedFcn',@(~,~) obj.set_calibration);




movegui(f,'onscreen');
