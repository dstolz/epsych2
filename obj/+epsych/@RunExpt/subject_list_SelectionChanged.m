function subject_list_SelectionChanged(self, hObj, ~)
% Prints subject and protocol info to the command window when selection changes.
if isempty(hObj.Selection), return, end
idx = hObj.Selection(1);
S = self.CONFIG(idx).SUBJECT;
C = self.CONFIG(idx);

fprintf('\n--- Subject ---\n')
fprintf('  Name:     %s\n', S.Name);
fprintf('  Box ID:   %d\n', S.BoxID);
if isfield(S,'Species') && ~isempty(S.Species)
    fprintf('  Species:  %s\n', S.Species);
end
if isfield(S,'Sex') && ~isempty(S.Sex)
    fprintf('  Sex:      %s\n', S.Sex);
end
if isfield(S,'Weight') && ~isempty(S.Weight)
    fprintf('  Weight:   %g g\n', S.Weight);
end
if isfield(S,'Notes') && ~isempty(strtrim(char(S.Notes)))
    fprintf('  Notes:    %s\n', strtrim(char(S.Notes)));
end

protocolFile = char(C.protocol_fn);
[~,pfn,pext] = fileparts(protocolFile);
fprintf('--- Protocol ---\n')
fprintf('  File:     %s%s\n', pfn, pext);
fprintf('  Path:     %s\n', protocolFile);
if isempty(protocolFile) || ~isfile(protocolFile)
    fprintf('  Status:   FILE NOT FOUND\n');
else
    d = dir(protocolFile);
    fprintf('  Modified on disk: %s (%.1f KB)\n', d.date, d.bytes/1024);
end

proto = C.PROTOCOL;
if isa(proto,'epsych.Protocol') && isvalid(proto)
    fprintf('  Version:  %s\n', proto.meta.protocolVersion);
    fprintf('  Format:   %g\n', proto.meta.formatVersion);
    if isfield(proto.meta,'epsychVersion') && ~isempty(proto.meta.epsychVersion)
        fprintf('  Saved by: %s\n', proto.meta.epsychVersion);
    end
    if isfield(proto.meta,'createdDate') && ~isempty(proto.meta.createdDate)
        fprintf('  Created:  %s\n', proto.meta.createdDate);
    end
    if isfield(proto.meta,'lastModified') && ~isempty(proto.meta.lastModified)
        fprintf('  Modified: %s\n', proto.meta.lastModified);
    end
    if ~isempty(proto.Info)
        fprintf('  Info:     %s\n', proto.Info);
    end

    fprintf('  Needs compile: %s\n', mat2str(proto.needsCompile));
    if proto.COMPILED.ntrials > 0
        fprintf('  Trials:   %d', proto.COMPILED.ntrials);
        if ~isempty(proto.COMPILED.compiledAt) && ~isnat(proto.COMPILED.compiledAt)
            fprintf(' (compiled %s)', datestr(proto.COMPILED.compiledAt)); %#ok<DATST>
        end
        fprintf('\n');
    end

    fprintf('--- Options ---\n')
    opt = proto.Options;
    if isfield(opt,'trialFunc') && ~isempty(opt.trialFunc)
        fprintf('  trialFunc:         %s\n', func2str_(opt.trialFunc));
    end
    if isfield(opt,'compileAtRuntime')
        fprintf('  compileAtRuntime:  %s\n', mat2str(opt.compileAtRuntime));
    end
    if isfield(opt,'IncludeWAVBuffers')
        fprintf('  IncludeWAVBuffers: %s\n', mat2str(opt.IncludeWAVBuffers));
    end
    if isfield(opt,'ConnectionType')
        fprintf('  ConnectionType:    %s\n', char(opt.ConnectionType));
    end

    fprintf('--- Interfaces ---\n')
    if isempty(proto.Interfaces)
        fprintf('  (none defined)\n');
    end
    for i = 1:numel(proto.Interfaces)
        iface = proto.Interfaces(i);
        nModules = numel(iface.Module);
        nParams = 0;
        for m = 1:nModules
            nParams = nParams + numel(iface.Module(m).Parameters);
        end
        ifaceName = '';
        if isprop(iface,'Name') && ~isempty(iface.Name)
            ifaceName = char(iface.Name);
        end
        if isempty(ifaceName)
            fprintf('  %-16s %d module(s), %d parameter(s)\n', char(iface.Type), nModules, nParams);
        else
            fprintf('  %-16s "%s" - %d module(s), %d parameter(s)\n', char(iface.Type), ifaceName, nModules, nParams);
        end
    end

    report = proto.validate();
    nErr  = sum([report.severity] == 2);
    nWarn = sum([report.severity] == 1);
    fprintf('--- Validation ---\n')
    if isempty(report)
        fprintf('  OK - no issues found\n');
    else
        fprintf('  %d error(s), %d warning(s)\n', nErr, nWarn);
        for i = 1:numel(report)
            switch report(i).severity
                case 2, tag = 'ERROR';
                case 1, tag = 'WARN ';
                otherwise, tag = 'INFO ';
            end
            fprintf('    [%s] %s: %s\n', tag, report(i).field, report(i).message);
        end
    end
elseif isstruct(proto) && isfield(proto,'OPTIONS')
    opt = proto.OPTIONS;
    if isfield(opt,'numReps'), fprintf('  Reps:     %d\n', opt.numReps); end
    if isfield(opt,'ISI'),     fprintf('  ISI:      %d ms\n', opt.ISI); end
    if isfield(opt,'randomize'), fprintf('  Randomize:%s\n', mat2str(opt.randomize)); end
    if isfield(proto,'ntrials') && proto.ntrials > 0
        fprintf('  Trials:   %d\n', proto.ntrials);
    end
end
end

function s = func2str_(f)
% Render Options.trialFunc (char, string, or function_handle) as text.
if isa(f,'function_handle')
    s = func2str(f);
else
    s = char(string(f));
end
end
