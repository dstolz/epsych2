function onOpenCheckCalculationsDialog(obj)
% onOpenCheckCalculationsDialog(obj)
% Open the expression sweep dialog and refresh its report.
% Raises and re-sweeps in the dialog when it is already open.
    [dialog, isNew] = obj.openToolDialog('CheckCalcFigure', 'Check Calculations', [1100 720]);
    if isNew
        obj.buildCheckCalculationsTab(dialog);
    end

    obj.refreshCheckCalculations();
end
