function setup_interface(obj,RPvdsFile,moduleType,moduleAlias,options)
% hw.TDT_RPcox
vprintf(2,'Establishing RPcox ActiveX')

obj.ConnectionType = options.Interface;


% use TDTRP to establish connection, but use hardware
% abstraction object (hw.Module) for interface
for i = 1:length(moduleType)
    obj.HW(i) = TDTRP(RPvdsFile{i}, moduleType{i}, ...
        'INTERFACE', options.Interface, ...
        'NUMBER', options.Number(i), ...
        'FS', options.Fs(i));

    M = hw.Module(obj,moduleType{i},moduleAlias{i},i);


    M.Fs = obj.HW(i).RP.GetSFreq;
    M.Info.RPvdsFile = RPvdsFile{i};
    M.Info.Number = double(options.Number(i));
    M.Info.FsOverride = double(options.Fs(i));
    M.Info.ConnectionType = options.Interface;


    % setup parameters
    pt = obj.HW(i).PARTAG;
    obj.populateModuleParametersFromTags(M, [pt{:}]);

    obj.Module(i) = M;
end

obj.ensureUniqueParameterNames();



end
