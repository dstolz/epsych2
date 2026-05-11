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

[~,pfn,pext] = fileparts(C.protocol_fn);
fprintf('--- Protocol ---\n')
fprintf('  File:     %s%s\n', pfn, pext);

proto = C.PROTOCOL;
if isa(proto,'epsych.Protocol') && isvalid(proto)
    if isfield(proto.meta,'createdDate') && ~isempty(proto.meta.createdDate)
        fprintf('  Created:  %s\n', proto.meta.createdDate);
    end
    if isfield(proto.meta,'lastModified') && ~isempty(proto.meta.lastModified)
        fprintf('  Modified: %s\n', proto.meta.lastModified);
    end
    opt = proto.Options;
    if ~isempty(proto.Info)
        fprintf('  Info:     %s\n', proto.Info);
    end
    if proto.COMPILED.ntrials > 0
        fprintf('  Trials:   %d\n', proto.COMPILED.ntrials);
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
