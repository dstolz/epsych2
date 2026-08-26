classdef NotesBehaviorGUI < gui.BehaviorGUI
    % Minimal gui.BehaviorGUI subclass exercised by tmp/smoke_test_notes.m.
    % Hosts both forms of the notes component -- the panel and the button --
    % so the test can assert that the base-class helpers wire them to the
    % session store and that teardown takes the button's window with it.

    properties
        NotesPanel   % addNotes result
        NotesButton  % addNotesButton result
    end

    methods
        function obj = NotesBehaviorGUI(RUNTIME)
            obj@gui.BehaviorGUI(RUNTIME, Name='Notes BehaviorGUI', ...
                PreferenceTag='smokeNotesBehaviorGUI', ...
                DefaultPosition=[100 100 640 420], Visible=false);
            if nargout == 0, clear obj; end
        end
    end

    methods (Access = protected)
        function build(obj, fig)
            g = uigridlayout(fig, [2 1]);
            g.RowHeight = {30, '1x'};

            obj.NotesButton = obj.add('gui.components.Notes', g, 'ButtonOnly', true, Text='Notes...');
            obj.NotesButton.OpenH.Layout.Row = 1;

            p = uipanel(g);
            p.Layout.Row = 2;
            obj.NotesPanel = obj.add('gui.components.Notes', p, PreferenceTag='smokeNotesPanel');
        end
    end
end
