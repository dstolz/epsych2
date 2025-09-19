function showGridBorders(gridLayout)
    % Visualizes a uigridlayout's cells with colored borders and descriptive labels.
    
    % Ensure the gridLayout is valid
    assert(isa(gridLayout, 'matlab.ui.container.GridLayout'), ...
        'Input must be a uigridlayout object');
    
    % Get grid dimensions
    numRows = numel(gridLayout.RowHeight);
    numCols = numel(gridLayout.ColumnWidth);
    
    % Define a colormap for cell background colors
    cmap = turbo(numRows * numCols); % Generate enough unique colors
    
    % Iterate through rows and columns
    for row = 1:numRows
        for col = 1:numCols
            colorIdx = (row - 1) * numCols + col; % Linear index for color


            % Add a label inside the panel
            lblText = sprintf('Row: %d\nCol: %d\n[%s x %s]', ...
                row, col, ...
                gridDimensionToStr(gridLayout.RowHeight{row}), ...
                gridDimensionToStr(gridLayout.ColumnWidth{col}));

            p = uilabel(gridLayout, ...
                'Text', lblText, ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'center', ...
                'BackgroundColor',cmap(colorIdx, :), ...
                'FontSize', 8, ... 
                'FontWeight','bold', ...
                'FontColor', 'k', ...
                'WordWrap', 'on'); % Enable text wrapping for small cells
            p.Layout.Row = row;
            p.Layout.Column = col;
        end
    end
end

function dimStr = gridDimensionToStr(dim)
    % Helper function to convert grid dimension to a string
    if isnumeric(dim)
        dimStr = sprintf('%dpx', dim);
    else
        dimStr = char(dim); % Handles '1x', 'fit', etc.
    end
end
