function plan = fix_synapse_parameter_names(protocolFile, options)
% plan = fix_synapse_parameter_names(protocolFile)
% plan = fix_synapse_parameter_names(protocolFile, Apply=true)
% Give a TDT_Synapse module's parameters back the names of their tags.
%
% ProtocolDesigner's copy/move tool renames a copied parameter Name_1,
% Name_2, ... when the name is still taken elsewhere in the protocol --
% which it is while the hw.TDT_RPcox module the parameters came from still
% exists. The copy keeps writing the right tag (UserData.HardwareName), but
% everything else goes by Name: the compiled trial table, the paradigm's
% trial selector (obj.T.TrialType), and epsych.Runtime's lookup of
% x_NewTrial_<box> and its kin. Once the RPcox interface is deleted the bare
% names are free again, and this puts them back.
%
% What it does, per hw.TDT_Synapse parameter whose Name is its tag plus a
% _N suffix and whose tag name is used by no other parameter:
%   - renames it to the tag, dropping the now-redundant HardwareName;
%   - rewrites every Expression in the protocol that names it by the old name;
%   - clears isArray on a scalar-typed parameter (a TrialType marked as an
%     array reads through the array path for nothing).
% Then recompiles and saves. epsych.Protocol.save archives the version it
% replaces inside the .eprot, so the change can be reverted from the
% designer's Version History.
%
% Nothing is written unless Apply=true; the default is a report.
%
% Example
%   fix_synapse_parameter_names('D:\epsych_files\Protocols\Appetitive\Appetitive_Platform_synapse.eprot')
%   fix_synapse_parameter_names('D:\...\Appetitive_Platform_synapse.eprot', Apply=true)

arguments
    protocolFile (1,:) char {mustBeFile}
    options.Apply (1,1) logical = false
end

P = epsych.Protocol.load(protocolFile);

allParams = [P.Interfaces.Module];
allParams = [allParams.Parameters];
allNames = {allParams.Name};

plan = struct('Parameter', {}, 'OldName', {}, 'NewName', {}, 'ClearArray', {});

for iface = P.Interfaces
    if ~isa(iface, 'hw.TDT_Synapse')
        continue
    end
    for module = iface.Module
        for p = module.Parameters
            tag = hw.Interface.getHardwareParameterName(p);
            suffixed = ~strcmp(p.Name, tag) && ...
                ~isempty(regexp(p.Name, ['^' regexptranslate('escape', tag) '_\d+$'], 'once'));
            newName = p.Name;
            if suffixed && ~any(strcmp(allNames, tag))
                newName = tag;
            end
            clearArray = p.isArray && ~ismember(p.Type, {'Buffer', 'Coefficient Buffer', 'StimType'});
            if strcmp(newName, p.Name) && ~clearArray
                continue
            end
            plan(end+1) = struct('Parameter', p, 'OldName', p.Name, 'NewName', newName, ...
                'ClearArray', clearArray); %#ok<AGROW>
        end
    end
end

if isempty(plan)
    fprintf('%s: nothing to change.\n', protocolFile);
    return
end

renames = plan(~strcmp({plan.OldName}, {plan.NewName}));
fprintf('%s\n', protocolFile);
fprintf('  %d parameter(s) to rename:\n', numel(renames));
for k = 1:numel(renames)
    fprintf('    %-24s -> %s\n', renames(k).OldName, renames(k).NewName);
end
arrays = plan([plan.ClearArray]);
if ~isempty(arrays)
    fprintf('  %d scalar parameter(s) marked isArray, to clear: %s\n', numel(arrays), ...
        strjoin({arrays.OldName}, ', '));
end

% Expressions that name a renamed parameter.
rewrites = {};
for p = allParams
    expr = char(p.Expression);
    if isempty(expr)
        continue
    end
    newExpr = expr;
    for k = 1:numel(renames)
        newExpr = regexprep(newExpr, ['(?<![\w.])' regexptranslate('escape', renames(k).OldName) '\>'], ...
            renames(k).NewName);
    end
    if ~strcmp(newExpr, expr)
        rewrites(end+1, :) = {p, expr, newExpr}; %#ok<AGROW>
    end
end
if ~isempty(rewrites)
    fprintf('  %d expression(s) to rewrite:\n', size(rewrites, 1));
    for k = 1:size(rewrites, 1)
        fprintf('    %s: "%s" -> "%s"\n', rewrites{k, 1}.Name, rewrites{k, 2}, rewrites{k, 3});
    end
end

if ~options.Apply
    fprintf('  Dry run. Re-run with Apply=true to write the protocol (the previous version is archived in it).\n');
    return
end

for k = 1:numel(plan)
    p = plan(k).Parameter;
    if ~strcmp(plan(k).OldName, plan(k).NewName)
        p.Name = plan(k).NewName;
        if isstruct(p.UserData) && isfield(p.UserData, 'HardwareName')
            p.UserData = rmfield(p.UserData, 'HardwareName');
        end
    end
    if plan(k).ClearArray
        p.isArray = false;
    end
end
for k = 1:size(rewrites, 1)
    rewrites{k, 1}.Expression = string(rewrites{k, 3});
end

P.compile();
if isempty(P.COMPILED)
    error('fix_synapse_parameter_names:CompileFailed', ...
        'The protocol did not compile after the rename; nothing was saved. See the messages above.');
end
P.save(protocolFile);
fprintf('  Saved. %d parameter(s) renamed, %d expression(s) rewritten; the previous version is archived in the file.\n', ...
    numel(renames), size(rewrites, 1));

end
