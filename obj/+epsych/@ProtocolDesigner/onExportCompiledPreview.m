function onExportCompiledPreview(obj, destination)
% onExportCompiledPreview(obj, destination)
% Export the compiled trial table to workspace or file formats.
%
% Parameters:
% 	destination	- Export target: 'workspace', 'mat', 'csv', or 'xlsx'.
    arguments
        obj
        destination (1,:) char
    end

    parameters = obj.Protocol.COMPILED.parameters;
    trials = obj.Protocol.COMPILED.trials;
    if isempty(parameters) || isempty(trials)
        obj.setStatus('No compiled trials to export', 'Compile the protocol first, then export the compiled table.');
        if ~isempty(obj.Figure) && isvalid(obj.Figure)
            uialert(obj.Figure, 'No compiled trials are available. Compile the protocol before exporting.', 'Export Compiled Table');
        end
        return
    end

    [columnNames, columnTypes, tableData] = obj.getCompiledPreviewTableData(inf);
    exportTable = localBuildExportTable_(columnNames, tableData);
    destination = lower(strtrim(destination));

    switch destination
        case 'workspace'
            assignin('base', 'compiledTable', exportTable);
            obj.setStatus('Exported compiled table to workspace variable "compiledTable"', ...
                'Inspect compiledTable in the base workspace or export to a file format.');

        case 'mat'
            defaultName = 'compiled_trials.mat';
            [fileName, folder] = uiputfile({'*.mat', 'MATLAB File (*.mat)'}, 'Export Compiled Table', defaultName);
            if isequal(fileName, 0)
                obj.setStatus('Export canceled', 'Choose an export target when ready.');
                return
            end

            filePath = fullfile(folder, fileName);
            compiledTable = exportTable;
            compiledColumnNames = columnNames;
            compiledColumnTypes = columnTypes;
            save(filePath, 'compiledTable', 'compiledColumnNames', 'compiledColumnTypes');

            obj.setStatus(sprintf('Exported compiled table to %s', filePath), ...
                'Open the MAT file in MATLAB to inspect compiledTable and metadata.');

        case {'csv', 'xlsx'}
            if strcmp(destination, 'csv')
                filterSpec = {'*.csv', 'Comma Separated Values (*.csv)'};
                defaultName = 'compiled_trials.csv';
            else
                filterSpec = {'*.xlsx', 'Excel Workbook (*.xlsx)'};
                defaultName = 'compiled_trials.xlsx';
            end

            [fileName, folder] = uiputfile(filterSpec, 'Export Compiled Table', defaultName);
            if isequal(fileName, 0)
                obj.setStatus('Export canceled', 'Choose an export target when ready.');
                return
            end

            filePath = fullfile(folder, fileName);
            writetable(exportTable, filePath);
            obj.setStatus(sprintf('Exported compiled table to %s', filePath), ...
                'Open the exported file to review all compiled trial rows.');

        otherwise
            error('epsych:ProtocolDesigner:InvalidExportDestination', ...
                'Unsupported export destination "%s". Use workspace, mat, csv, or xlsx.', destination);
    end
end

function exportTable = localBuildExportTable_(columnNames, tableData)
% exportTable = localBuildExportTable_(columnNames, tableData)
% Build a table with valid variable names and preserve display names.
    validVariableNames = matlab.lang.makeUniqueStrings(...
        matlab.lang.makeValidName(columnNames, 'ReplacementStyle', 'underscore'));

    exportTable = cell2table(tableData, 'VariableNames', validVariableNames);
    exportTable.Properties.VariableDescriptions = columnNames;
end
