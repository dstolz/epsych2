function showGridBorders(gridLayout)
% showGridBorders(gridLayout)
% Visualize uigridlayout cells for debugging.
%
% Adds a uilabel to each cell of the provided uigridlayout, coloring each
% cell and showing row/column indices plus row/column size strings.
%
% Parameters
%   gridLayout (1,1) matlab.ui.container.GridLayout
%
% Notes
%   This function modifies the layout by adding child components (labels).
%   Use on an empty/debug layout (or clear existing children first).

    arguments
        gridLayout (1,1) matlab.ui.container.GridLayout
    end
    
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
% gridDimensionToStr(dim)
% Convert a GridLayout row/column dimension to a readable string.
%
% Parameters
%   dim - Value from GridLayout RowHeight/ColumnWidth cell arrays.
%
% Returns
%   dimStr (1,:) char

    if isnumeric(dim)
        dimStr = sprintf('%dpx', dim);
    else
        dimStr = char(dim); % Handles '1x', 'fit', etc.
    end
end