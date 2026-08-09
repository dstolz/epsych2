function onCompile(obj, verb, varargin)
% onCompile(obj, verb, varargin)
% Handle every Compile-tab action.
%
% Parameters
%   verb - 'validate', 'compile', 'upload', 'insert', 'copy', 'goto',
%       'reportSelected', 'workspace'.
%   varargin - Verb-specific arguments.
%
% See also: teensy.Compiler, hw.Teensy.sendProgramBlock

arguments
    obj (1,1) teensy.TrialDesigner
    verb (1,:) char
end
arguments (Repeating)
    varargin
end

switch verb

    case 'validate'
        report = obj.Program.validate();
        obj.CompileResult.Report = report;
        obj.CompileResult.Stats = teensy.Compiler().stats(obj.Program);
        obj.TabGroup.SelectedTab = obj.HCompile.Tab;
        obj.refreshAll();
        obj.setStatus(localReportSummary_(report, 'Validation'));

    case 'compile'
        c = teensy.Compiler();
        obj.CompileResult = c.compile(obj.Program);
        obj.TabGroup.SelectedTab = obj.HCompile.Tab;
        obj.refreshAll();

        if obj.CompileResult.Ok
            obj.setStatus(sprintf('Compiled to %d records. %s', ...
                numel(obj.CompileResult.Lines), ...
                localReportSummary_(obj.CompileResult.Report, '')));
        else
            obj.setStatus(sprintf('Compile failed. %s', ...
                localReportSummary_(obj.CompileResult.Report, '')));
        end

    case 'upload'
        if ~obj.CompileResult.Ok
            obj.setStatus('Compile the program before uploading it.');
            return
        end

        if isempty(obj.Interface) || ~isa(obj.Interface, 'hw.Teensy')
            uialert(obj.Figure, ...
                ['No Teensy interface is bound to this designer. Open the designer ' ...
                 'from the Protocol Designer with a Teensy interface selected, or ' ...
                 'from a running session.'], 'No Board', Icon = 'warning');
            return
        end

        % uiprogressdlg refuses to attach to a hidden figure, so the dialog is
        % optional; the upload itself must work either way.
        dlg = [];
        if obj.Figure.Visible == "on"
            dlg = uiprogressdlg(obj.Figure, Title = 'Teensy', ...
                Message = 'Uploading the program...', Indeterminate = 'on');
        end
        closeDialog = onCleanup(@() localCloseDialog_(dlg));

        [ok, msg] = teensy.Compiler().upload(obj.CompileResult, obj.Interface);

        if ok
            obj.setStatus(sprintf('Upload succeeded. %s', msg));
        else
            obj.setStatus(sprintf('Upload failed: %s', msg));
            uialert(obj.Figure, msg, 'Upload Failed', Icon = 'error');
        end

    case 'insert'
        localInsertIntoProtocol_(obj);

    case 'copy'
        if isempty(obj.CompileResult.Text)
            obj.setStatus('Compile the program first.');
            return
        end
        clipboard('copy', obj.CompileResult.Text);
        obj.setStatus('Copied the wire program to the clipboard.');

    case 'reportSelected'
        evt = varargin{1};
        if ~isempty(evt.Indices)
            obj.HCompile.SelectedIssue = evt.Indices(1, 1);
        end

    case 'goto'
        localGoToIssue_(obj);

    case 'workspace'
        assignin('base', 'teensyProgram', obj.Program);
        obj.setStatus('Exported the program to the base workspace as teensyProgram.');

end
end


% =========================================================================
function txt = localReportSummary_(report, prefix)
% txt = localReportSummary_(report, prefix)
% One-line count of what validation found.
nErr = teensy.Compiler.countBySeverity(report, "error");
nWarn = teensy.Compiler.countBySeverity(report, "warning");
nInfo = teensy.Compiler.countBySeverity(report, "info");

if nErr == 0 && nWarn == 0 && nInfo == 0
    txt = strtrim(sprintf('%s found nothing to report.', prefix));
    return
end

txt = strtrim(sprintf('%s found %d error(s), %d warning(s), %d note(s).', ...
    prefix, nErr, nWarn, nInfo));
end


function localCloseDialog_(dlg)
% localCloseDialog_(dlg)
% Close a progress dialog if it is still open.
if ~isempty(dlg) && isvalid(dlg)
    close(dlg);
end
end


function localGoToIssue_(obj)
% localGoToIssue_(obj)
% Jump to the item the selected report row is about.
%
% The Where field is written by the validators as "State 'X' transition 2" or
% "Channel 'Y'", so the leading noun and the quoted name are enough to route.
if ~isfield(obj.HCompile, 'SelectedIssue') || obj.HCompile.SelectedIssue < 1
    obj.setStatus('Select a row in the report first.');
    return
end

row = obj.HCompile.SelectedIssue;
if row > numel(obj.CompileResult.Report)
    return
end

where = string(obj.CompileResult.Report(row).Where);
name = regexp(where, "'([^']+)'", 'tokens', 'once');

if isempty(name)
    obj.setStatus(sprintf('That issue is about the program as a whole: %s', where));
    return
end
name = string(name{1});

if startsWith(where, "State")
    idx = obj.Program.stateIndex(name);
    if idx > 0
        obj.SelectedState = idx;
        obj.TabGroup.SelectedTab = obj.HStates.Tab;
        obj.refreshAll();
        obj.setStatus(sprintf('Jumped to state %s.', name));
        return
    end

elseif startsWith(where, "Channel")
    idx = obj.Program.channelIndex(name);
    if idx > 0
        obj.SelectedChannel = idx;
        obj.TabGroup.SelectedTab = obj.HChannels.Tab;
        obj.refreshAll();
        obj.setStatus(sprintf('Jumped to channel %s.', name));
        return
    end

elseif startsWith(where, "Variable")
    idx = obj.Program.variableIndex(name);
    if idx > 0
        obj.SelectedVariable = idx;
        obj.TabGroup.SelectedTab = obj.HVariables.Tab;
        obj.refreshAll();
        obj.setStatus(sprintf('Jumped to variable %s.', name));
        return
    end
end

obj.setStatus(sprintf('Could not locate "%s".', where));
end


function localInsertIntoProtocol_(obj)
% localInsertIntoProtocol_(obj)
% Create this program's parameters on a Teensy interface, or export them.
%
% Prefers an already-open Protocol Designer, since that is where the protocol
% being built actually lives; exporting JSON is the fallback for when the
% protocol is somewhere else.
designers = findall(groot, 'Type', 'figure', '-and', 'Name', 'Protocol Designer');

target = [];
for i = 1:numel(designers)
    ud = designers(i).UserData;
    if isa(ud, 'epsych.ProtocolDesigner') && isvalid(ud)
        target = ud;
        break
    end
end

options = {'Export Parameters as JSON', 'Cancel'};
if ~isempty(target)
    options = [{'Add to the Open Protocol Designer'}, options];
end

answer = uiconfirm(obj.Figure, ...
    sprintf(['This program defines %d parameters, including the triggers the ' ...
        'runtime requires for box %d.'], numel(obj.Program.parameterSpecs()), ...
        obj.Program.BoxID), ...
    'Insert Into Protocol', Options = options, ...
    DefaultOption = 1, CancelOption = numel(options), Icon = 'question');

switch answer
    case 'Add to the Open Protocol Designer'
        iface = [];
        for i = 1:numel(target.Protocol.Interfaces)
            if isa(target.Protocol.Interfaces(i), 'hw.Teensy')
                iface = target.Protocol.Interfaces(i);
                break
            end
        end

        if isempty(iface)
            uialert(obj.Figure, ...
                ['The open protocol has no Teensy interface. Add one in the ' ...
                 'Protocol Designer first, with Interface > Add Interface, then ' ...
                 'try again.'], 'No Teensy Interface', Icon = 'warning');
            return
        end

        if isempty(iface.Module)
            uialert(obj.Figure, ...
                ['The Teensy interface has no module to hold the parameters. ' ...
                 'Add one in the Protocol Designer with Interface > Add Module.'], ...
                'No Module', Icon = 'warning');
            return
        end

        P = obj.Program.applyToModule(iface.Module(1));
        target.refreshUI();
        obj.setStatus(sprintf('Added %d parameter(s) to the open protocol.', numel(P)));

    case 'Export Parameters as JSON'
        [f, pth] = uiputfile({'*.json', 'Parameter Definitions (*.json)'}, ...
            'Export Parameters', char(obj.Program.Name) + "_parameters.json");
        figure(obj.Figure);
        if isequal(f, 0)
            return
        end

        specs = obj.Program.parameterSpecs();
        fid = fopen(fullfile(pth, f), 'w');
        if fid < 0
            obj.setStatus('Could not open the file for writing.');
            return
        end
        closeFile = onCleanup(@() fclose(fid));
        fprintf(fid, '%s', jsonencode(specs, PrettyPrint = true));
        obj.setStatus(sprintf('Exported %d parameter definition(s).', numel(specs)));
end
end
