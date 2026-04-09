function onCompile(obj)
    obj.Protocol.compile();
    obj.refreshCompiledPreview();
    obj.LabelStatus.Text = sprintf('Compiled %d trials', obj.Protocol.COMPILED.ntrials);
end

