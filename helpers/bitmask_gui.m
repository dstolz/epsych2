function fig = bitmask_gui(opts)
%BITMASK_GUI Interactive GUI to build an integer bitmask from epsych.BitMask
%   FIG = BITMASK_GUI() builds a GUI with a table of epsych.BitMask names,
%   their bit indices, and a checkbox to select flags. A large button shows
%   the current integer mask; clicking it copies the value to the clipboard.
%
%   FIG = BITMASK_GUI(opts) allows Name-Value options:
%     Parent       : UI container to place the GUI into (default = new uifigure)
%     InitialMask  : uint32 initial mask to preselect rows (default = 0)
%     Title        : figure title (default = "BitMask Builder")
%
%   UI also includes a numeric "Mask" field:
%     - Typing a positive integer updates the table to match those bits.
%     - Toggling rows updates the field and big button.
%
%   Example:
%     fig = bitmask_gui(InitialMask=uint32(2626));
%
%   Requires: epsych.BitMask on path.

arguments
    opts.Parent = []
    opts.InitialMask (1,1) uint32 = uint32(0)
    opts.Title (1,1) string = "BitMask Builder"
end

% === Enumerations via epsych.BitMask helpers ===
% Use getDefined() to drop Undefined (0)
bm_all = epsych.BitMask.getDefined();
bitPos = uint32(bm_all);                % numeric bit indices (1-based)
bitPosD = double(bitPos);               % for uitable display
bitNames = string(bm_all);              % enum names as strings
maxBit = double(max(bitPos));

% Initial selection from InitialMask using Mask2Bits
initMask = uint32(opts.InitialMask);
sel = false(numel(bitPos),1);
if initMask>0
    [bitsRow, ~] = epsych.BitMask.Mask2Bits(initMask, maxBit); % 1 x maxBit, LSB in column 1
    sel = logical(bitsRow(bitPosD)).';  % ensure column vector% pick only defined bits
end

% === Parent and layout ===
if isempty(opts.Parent) || ~isvalid_container(opts.Parent)
    fig = uifigure('Name',opts.Title,'Position',[100 100 365 650]);
    parent = fig;
else
    fig = ancestor(opts.Parent,'figure');
    parent = opts.Parent;
end
movegui(fig,'onscreen');

% 3 rows: table, mask field, buttons
root = uigridlayout(parent,[3 1],RowHeight={"1x",40,54},ColumnWidth={"1x"},Padding=[10 10 10 10]);

% === Table: Name | Bit | Select ===
T = table(bitNames(:), bitPosD(:), logical(sel(:)), 'VariableNames', {'Name','Value','Selected'});
uit = uitable(root, 'Data', T, 'ColumnEditable',[false false true], 'RowName',[]);
uit.ColumnName = {'Name','Bit','Select'};
uit.ColumnWidth = {'auto','auto',70};
uit.FontName = 'Monospaced';
uit.CellEditCallback = @(src,evt) onCellEdit();

% Row highlight style
st = uistyle('BackgroundColor',[0.94 1.00 0.94]);
addStyle(uit, st, 'row', find(uit.Data.Selected));

% === Controls row: Mask edit field ===
ctl = uigridlayout(root,[1 4], 'ColumnWidth',{50,180,"1x",110}, 'ColumnSpacing',10, 'Padding',[0 0 0 0]);
uilabel(ctl,'Text','Mask','HorizontalAlignment','right','FontWeight','bold');
editMask = uieditfield(ctl,'numeric', ...
    'Limits',[0 Inf], ...                 % allow 0 programmatically; enforce >0 on user edits
    'RoundFractionalValues',true, ...
    'ValueDisplayFormat','%u', ...
    'Value', double(initMask));
editMask.Tooltip = 'Enter a positive integer mask (sum of 2^bit)';
editMask.ValueChangedFcn = @(h,~) onMaskFieldEdited();

% Filler in col 3
uilabel(ctl,'Text','');

% === Button row: Big mask & Reset ===
btnRow = uigridlayout(root,[1 2], 'ColumnWidth',{ "1x",110 }, 'ColumnSpacing',10, 'Padding',[0 0 0 0]);
btnMask = uibutton(btnRow,'Text','0','FontSize',20,'FontWeight','bold', ...
    'ButtonPushedFcn',@(b,~) copyMaskToClipboard());
btnReset = uibutton(btnRow,'Text','Reset','ButtonPushedFcn',@(b,~) resetSelection());
btnReset.Tooltip = 'Uncheck all boxes';

% === Shared state ===
S.Table = uit;
S.Style = st;
S.MaskButton = btnMask;
S.Figure = fig;
S.EditMask = editMask;
S.InProgrammaticUpdate = false;      % flag to differentiate programmatic vs user edits
uit.UserData = S;

% Initial sync
updateFromTable();

if nargout == 0, clear fig; end

% ================= Nested helpers =================
    function tf = isvalid_container(h)
        tf = ~isempty(h) && ishghandle(h) && ~strcmp(get(h,'BeingDeleted'),'on');
    end

    function onCellEdit()
        updateFromTable();
    end

    function m = maskFromSelection(d)
        % Compute mask using epsych.BitMask.Bits2Mask with bit positions
        selBits = uint32(d.Value(logical(d.Selected)));  % positions
        if isempty(selBits)
            m = uint32(0);
        else
            m = epsych.BitMask.Bits2Mask(selBits(:)');    % accepts positions vector
        end
    end

    function updateFromTable()
        % Read table -> mask via Bits2Mask -> update field/button -> styles
        S = uit.UserData;
        d = S.Table.Data;
        m = maskFromSelection(d);

        % Programmatic update of numeric field (allow 0 display)
        S.InProgrammaticUpdate = true;
        if S.EditMask.Value ~= double(m)
            S.EditMask.Value = double(m);
        end
        S.InProgrammaticUpdate = false;

        S.MaskButton.Text = sprintf('%u', m);

        % Refresh highlight styles
        try
            removeStyle(S.Table);
        catch
            try, removeStyle(S.Table, S.Style); end
        end
        selRows = find(d.Selected);
        if ~isempty(selRows)
            addStyle(S.Table, S.Style, 'row', selRows);
        end
        uit.UserData = S;
    end

    function onMaskFieldEdited()
        % Enforce positive integer on USER edits; 0 is only set programmatically
        S = uit.UserData;
        if S.InProgrammaticUpdate, return; end

        val = S.EditMask.Value;
        if ~isfinite(val) || isnan(val) || val < 1 || floor(val) ~= val
            % Revert to current mask and warn
            S.InProgrammaticUpdate = true;
            S.EditMask.Value = str2double(S.MaskButton.Text);
            S.InProgrammaticUpdate = false;
            try
                uialert(S.Figure,'Please enter a positive integer (>=1).','Invalid value','Icon','warning');
            catch
            end
            return
        end

        % Clamp to uint32 max
        if val > double(intmax('uint32'))
            val = double(intmax('uint32'));
            S.InProgrammaticUpdate = true; S.EditMask.Value = val; S.InProgrammaticUpdate = false;
        end
        m = uint32(val);

        % Use Mask2Bits to update table selection
        [bitsRow, ~] = epsych.BitMask.Mask2Bits(m, maxBit);  % 1 x maxBit logical
        d = S.Table.Data;
        selVec = logical(bitsRow(d.Value)).';  % ensure column vector
        d.Selected = selVec;              % pick defined bits
        S.Table.Data = d;
        uit.UserData = S;

        % Mirror to button/styles
        updateFromTable();
    end

    function copyMaskToClipboard()
        S = uit.UserData;
        clipboard('copy', S.MaskButton.Text);
        try
            uialert(S.Figure, "Bitmask copied to clipboard: " + S.MaskButton.Text, 'Copied', 'Icon','success','CloseFcn',[]);
        catch %#ok<CTCH>
        end
    end

    function resetSelection()
        S = uit.UserData;
        d = S.Table.Data;
        d.Selected(:) = false;
        S.Table.Data = d;
        uit.UserData = S;
        try
            removeStyle(S.Table);
        catch
            removeStyle(S.Table, S.Style);
        end
        updateFromTable();
    end

end

