function setup_interface(obj,RPvdsFile,moduleType,moduleAlias)
% hw.TDT_RPcox
vprintf(2,'Establishing RPcox ActiveX')

if isempty(moduleAlias) % check this
    moduleAlias = moduleType;
end


% use TDTRP to establish connection, but use hardware
% abstraction object (hw.Module) for interface
for i = 1:length(moduleType)
    obj.HW(i) = TDTRP(RPvdsFile{i},moduleType{i});

    M = hw.Module(obj,moduleType{i},moduleAlias{i},1);


    M.Fs = obj.HW.RP.GetSFreq;
    M.Info.RPvdsFile = RPvdsFile{i};


    % setup parameters
    pt = obj.HW.PARTAG;
    pt = [pt{:}];
    ind = arrayfun(@(a) a.tag_name(1)=='%',pt);
    pt(ind) = [];
    for p = 1:length(pt)
        P = hw.Parameter(obj);

        P.Name = pt(p).tag_name;
        P.isArray = pt(p).tag_size > 1;

        P.isTrigger = P.Name(1) == '!'; % our convention for a trigger
        P.Visible = ~any(P.Name(1) == '_~#%');


        switch pt(p).tag_type
            case 68
                P.Type = 'Buffer';

            case 73
                P.Type = 'Integer';

            case 78
                P.Type = 'Logical';

            case 83
                P.Type = 'Float';

            case 80
                P.Type = 'Coefficient Buffer';

            case 65
                P.Type = 'Undefined';
        end

        P.Module = M;
        
        M.Parameters(p) = P;
    end

    obj.Module(i) = M;
end



end
