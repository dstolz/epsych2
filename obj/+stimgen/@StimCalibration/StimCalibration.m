classdef StimCalibration < handle & matlab.mixin.SetGet
    % obj = stimgen.StimCalibration(adapter, parent)
    % obj = stimgen.StimCalibration()
    %
    % GUI controller for SPL-to-voltage calibration.
    %
    % Thin wrapper around stimgen.calibration.Engine. Owns the GUI state
    % machine and exposes proxy properties and methods so that
    % stimgen.StimType continues to work without modification.
    %
    % When constructed without arguments the object is in offline mode and
    % can load a .esgc file for use by StimType. When an adapter is supplied
    % the calibration GUI is launched against that hardware.
    %
    % Properties (delegated from Engine):
    %   CalibrationData, MicSensitivity, ReferenceLevel, ReferenceFrequency,
    %   NormativeValue, ExcitationSignalVoltage, CalibrationTimestamp
    %
    % Methods:
    %   gui                      - Launch calibration GUI.
    %   compute_adjusted_voltage - Proxy to Engine; used by StimType.
    %   load_calibration         - Load .esgc file into Engine.
    %   save_calibration         - Save Engine data to .esgc file.
    %
    % See also: stimgen.calibration.Engine, stimgen.calibration.HwAdapter,
    %           documentation/stimgen/stimgen_StimCalibration.md

    properties (SetAccess = protected)
        Engine  stimgen.calibration.Engine  % core calibration engine
    end

    properties (SetAccess = private, SetObservable, AbortSet)
        STATE (1,1) string {mustBeMember(STATE,["IDLE","REFERENCE","CALIBRATE"])} = "IDLE"
    end

    properties (SetAccess = protected, Hidden)
        handles
    end

    % --- Dependent pass-throughs so StimType sees familiar property names --
    properties (Dependent)
        CalibrationData
        MicSensitivity
        ReferenceLevel
        ReferenceFrequency
        NormativeValue
        ExcitationSignalVoltage
        CalibrationTimestamp
        Fs
    end

    methods

        gui(obj)  % Launch calibration GUI.
        v = compute_adjusted_voltage(obj, type, value, level)  % Proxy to Engine.

        % ---------------------------------------------------------- %
        function obj = StimCalibration(adapter, parent)
            % obj = StimCalibration()
            % obj = StimCalibration(adapter)
            % obj = StimCalibration(adapter, parent)
            %
            % Parameters:
            %   adapter - stimgen.calibration.HwAdapter connected to calibration
            %             hardware (optional; omit for offline use). The host
            %             application builds this, e.g. stimbridge.InterfaceAdapter.
            %   parent  - UI parent container (optional)
            obj.handles.parent = [];
            if nargin > 1
                obj.handles.parent = parent;
            end

            if nargin > 0 && ~isempty(adapter)
                mustBeA(adapter, 'stimgen.calibration.HwAdapter');
                obj.Engine = stimgen.calibration.Engine(adapter);
                obj.gui();
            else
                obj.Engine = stimgen.calibration.Engine();
            end
        end

        % ---------------------------------------------------------- %
        function S = toStruct(obj)
            % S = toStruct(obj)
            % Serialize to a plain struct for protocol persistence.
            S                         = struct;
            S.Class                   = "stimgen.StimCalibration";
            S.CalibrationData         = obj.CalibrationData;
            S.MicSensitivity          = obj.MicSensitivity;
            S.NormativeValue          = obj.NormativeValue;
            S.ReferenceLevel          = obj.ReferenceLevel;
            S.ReferenceFrequency      = obj.ReferenceFrequency;
            S.ExcitationSignalVoltage = obj.ExcitationSignalVoltage;
            S.CalibrationTimestamp    = obj.CalibrationTimestamp;
            S.Fs                      = obj.Fs;
        end

        % ---------------------------------------------------------- %
        % Dependent property accessors — all delegate to Engine

        function v = get.CalibrationData(obj)
            v = obj.Engine.CalibrationData;
        end

        function v = get.MicSensitivity(obj)
            v = obj.Engine.MicSensitivity;
        end
        function set.MicSensitivity(obj, r)
            obj.Engine.MicSensitivity = r;
            obj.sync_gui_field_('MicSensitivity', r);
        end

        function v = get.ReferenceLevel(obj)
            v = obj.Engine.ReferenceLevel;
        end
        function set.ReferenceLevel(obj, r)
            obj.Engine.ReferenceLevel = r;
            obj.sync_gui_field_('ReferenceLevel', r);
        end

        function v = get.ReferenceFrequency(obj)
            v = obj.Engine.ReferenceFrequency;
        end
        function set.ReferenceFrequency(obj, r)
            obj.Engine.ReferenceFrequency = r;
            obj.sync_gui_field_('ReferenceFrequency', r);
        end

        function v = get.NormativeValue(obj)
            v = obj.Engine.NormativeValue;
        end
        function set.NormativeValue(obj, r)
            obj.Engine.NormativeValue = r;
            obj.sync_gui_field_('NormativeValue', r);
        end

        function v = get.ExcitationSignalVoltage(obj)
            v = obj.Engine.ExcitationVoltage;
        end
        function set.ExcitationSignalVoltage(obj, r)
            obj.Engine.ExcitationVoltage = r;
            obj.sync_gui_field_('ExcitationSignalVoltage', r);
        end

        function v = get.CalibrationTimestamp(obj)
            v = obj.Engine.CalibrationTimestamp;
        end

        function v = get.Fs(obj)
            v = obj.Engine.Fs;
        end

        % ---------------------------------------------------------- %
        function set_prop(obj, src, ~)
            % Callback from GUI numeric fields: src.Tag names the Engine property.
            % ExcitationSignalVoltage is a special case (maps to Engine.ExcitationVoltage).
            tag = src.Tag;
            val = src.Value;
            if strcmp(tag, 'ExcitationSignalVoltage')
                obj.Engine.ExcitationVoltage = val;
            else
                obj.Engine.(tag) = val;
            end
        end

        % ---------------------------------------------------------- %
        function calibration_state(obj, ~, ~)
            % STATE PostSet listener — orchestrates Engine calls and GUI state.
            h   = obj.handles;
            hen = findobj(h.parent, '-property', 'Enable');

            switch obj.STATE
                case "IDLE"
                    set(hen, 'Enable', 'on');
                    h.RefMeasure.Text    = 'Measure Reference';
                    h.RunCalibration.Text = 'Calibrate';

                case "REFERENCE"
                    set(hen, 'Enable', 'off');
                    h.RefMeasure.Enable = 'on';
                    h.RefMeasure.Text   = 'Stop';
                    drawnow;

                    try
                        obj.Engine.calibrate_reference();
                        obj.sync_gui_field_('MicSensitivity', obj.Engine.MicSensitivity);
                    catch ME
                        set(hen, 'Enable', 'on');
                        h.RefMeasure.Text = 'REFERENCING ERROR';
                        stimgen.util.vprintf(0, 2, ME);
                        obj.STATE = "IDLE";
                        return;
                    end

                    set(hen, 'Enable', 'on');
                    h.RefMeasure.Text = 'Measure Reference';
                    obj.Engine.plot_signal();
                    obj.Engine.plot_spectrum();
                    obj.STATE = "IDLE";

                case "CALIBRATE"
                    set(hen, 'Enable', 'off');
                    h.RunCalibration.Enable = 'on';
                    h.RunCalibration.Text   = 'Stop';
                    drawnow;

                    try
                        obj.Engine.CalibrationTimestamp = datetime("now");
                        obj.Engine.calibrate_clicks();
                        obj.Engine.calibrate_tones();
                        h.MenuSaveCalibration.Enable = 'on';
                    catch ME
                        set(hen, 'Enable', 'on');
                        h.RunCalibration.Text            = {'CALIBRATION','ERROR'};
                        h.RunCalibration.BackgroundColor = 'r';
                        stimgen.util.vprintf(0, 2, ME);
                        obj.STATE = "IDLE";
                        return;
                    end
                    set(hen, 'Enable', 'on');
                    h.RunCalibration.Text = 'Calibrate';
                    obj.STATE = "IDLE";
            end
            drawnow;
        end

        % ---------------------------------------------------------- %
        function design_filter(obj)
            % design_filter(obj)
            % Design equalization FIR filter from completed tone calibration.
            % Delegates to Engine. Results are stored in CalibrationData.filter.
            obj.Engine.design_filter();
        end

        % ---------------------------------------------------------- %
        function measure_ref(obj, ~, ~)
            if obj.STATE == "REFERENCE"
                obj.STATE = "IDLE";
            else
                obj.STATE = "REFERENCE";
            end
        end

        function run_calibration(obj, ~, ~)
            if obj.STATE == "CALIBRATE"
                obj.STATE = "IDLE";
            else
                obj.STATE = "CALIBRATE";
            end
        end

        % ---------------------------------------------------------- %
        function load_calibration(obj, ffn)
            % load_calibration(obj)
            % load_calibration(obj, ffn)
            % Load a .esgc calibration file into the Engine.
            %
            % Old .sgc files are not supported; please recalibrate.
            if nargin < 2, ffn = ''; end
            eng = stimgen.calibration.Engine.load(ffn);
            if isempty(eng), return; end
            obj.Engine = eng;

            % Sync GUI fields to loaded values.
            obj.sync_gui_field_('MicSensitivity',      obj.Engine.MicSensitivity);
            obj.sync_gui_field_('ReferenceLevel',      obj.Engine.ReferenceLevel);
            obj.sync_gui_field_('ReferenceFrequency',  obj.Engine.ReferenceFrequency);
            obj.sync_gui_field_('NormativeValue',      obj.Engine.NormativeValue);
            obj.sync_gui_field_('ExcitationSignalVoltage', obj.Engine.ExcitationVoltage);

            f = ancestor(obj.handles.parent, 'figure');
            if ~isempty(f), figure(f); end
        end

        function save_calibration(obj, ffn)
            % save_calibration(obj)
            % save_calibration(obj, ffn)
            % Save Engine calibration data to a .esgc file.
            if nargin < 2, ffn = ''; end
            obj.Engine.save(ffn);
            f = ancestor(obj.handles.parent, 'figure');
            if ~isempty(f), figure(f); end
        end

    end  % public methods

    % ------------------------------------------------------------------ %
    methods (Access = private)
        function sync_gui_field_(obj, tag, value)
            % sync_gui_field_(obj, tag, value)
            % Update a GUI control identified by handles.(tag) if it exists.
            if isempty(obj.handles) || ~isfield(obj.handles, tag)
                return;
            end
            h = obj.handles.(tag);
            if isvalid(h) && isprop(h, 'Value')
                h.Value = value;
            end
        end
    end

    % ------------------------------------------------------------------ %
    methods
        function s = saveobj(obj)
            % Serialize for MATLAB session saves.
            s.CalibrationData        = obj.Engine.CalibrationData;
            s.MicSensitivity         = obj.Engine.MicSensitivity;
            s.NormativeValue         = obj.Engine.NormativeValue;
            s.ReferenceLevel         = obj.Engine.ReferenceLevel;
            s.ReferenceFrequency     = obj.Engine.ReferenceFrequency;
            s.ExcitationSignalVoltage = obj.Engine.ExcitationVoltage;
            s.CalibrationTimestamp   = obj.Engine.CalibrationTimestamp;
        end
    end

    methods (Static)
        function obj = loadobj(s)
            % Restore from a MATLAB session save struct.
            obj = stimgen.StimCalibration();  % offline, no adapter
            if isstruct(s)
                eng = obj.Engine;
                if isstruct(s.CalibrationData)
                    eng.CalibrationData = s.CalibrationData;
                end
                eng.MicSensitivity      = s.MicSensitivity;
                eng.NormativeValue      = s.NormativeValue;
                eng.ReferenceLevel      = s.ReferenceLevel;
                eng.ReferenceFrequency  = s.ReferenceFrequency;
                eng.ExcitationVoltage   = s.ExcitationSignalVoltage;
                eng.CalibrationTimestamp = s.CalibrationTimestamp;
            end
        end
    end

end
