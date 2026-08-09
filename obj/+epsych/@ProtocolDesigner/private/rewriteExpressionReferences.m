function rewriteExpressionReferences(obj, ownerModule, oldName, newName)
% rewriteExpressionReferences(obj, ownerModule, oldName, newName)
% Rewrite every expression that named a parameter before it was renamed.
%
% hw.Parameter.resolveExpressionContext recognizes a parameter three ways: bare
% inside its own module, ModuleName.ParamName from anywhere, and either form
% suffixed with .Min/.Max/.Value/.Values. All are rewritten here, otherwise a
% rename silently orphans the calculations that depended on it.
%
% Parameters:
%	ownerModule	- Module owning the renamed parameter.
%	oldName		- Name the expressions currently use.
%	newName		- Name they should use instead.
    qualifiedPattern = ['(?<![\w.])' regexptranslate('escape', ownerModule.Name) ...
                        '\.' regexptranslate('escape', oldName) '\>'];
    qualifiedReplacement = localEscapeReplacement_([ownerModule.Name '.' newName]);

    % Siblings reference each other through makeValidName, so a name that is not
    % already an identifier needs both spellings rewritten.
    barePairs = {oldName, newName};
    oldValidName = matlab.lang.makeValidName(oldName);
    if ~strcmp(oldValidName, oldName)
        barePairs(end + 1, :) = {oldValidName, matlab.lang.makeValidName(newName)};
    end

    for ifaceIdx = 1:length(obj.Protocol.Interfaces)
        iface = obj.Protocol.Interfaces(ifaceIdx);
        for moduleIdx = 1:length(iface.Module)
            module = iface.Module(moduleIdx);
            isOwnerModule = isequal(module, ownerModule);
            for paramIdx = 1:length(module.Parameters)
                parameter = module.Parameters(paramIdx);
                expressionText = obj.getParameterExpression(parameter);
                if isempty(expressionText)
                    continue
                end

                % Qualified references first: rewriting them leaves the new name
                % preceded by '.', which the bare pass then correctly ignores.
                updatedText = regexprep(expressionText, qualifiedPattern, qualifiedReplacement);
                if isOwnerModule
                    for pairIdx = 1:size(barePairs, 1)
                        barePattern = ['(?<![\w.])' regexptranslate('escape', barePairs{pairIdx, 1}) '\>'];
                        updatedText = regexprep(updatedText, barePattern, ...
                            localEscapeReplacement_(barePairs{pairIdx, 2}));
                    end
                end

                if ~strcmp(updatedText, expressionText)
                    parameter.Expression = string(updatedText);
                end
            end
        end
    end
end

function escapedText = localEscapeReplacement_(replacementText)
% Protect '$' and '\' so regexprep treats the replacement as literal text.
    escapedText = strrep(replacementText, '\', '\\');
    escapedText = strrep(escapedText, '$', '$$');
end
