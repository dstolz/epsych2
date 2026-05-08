function stats = repeatability_stats_(~, values)
% values is expected to be [repeats x points].
mu = mean(values, 1, 'omitnan');
sigma = std(values, 0, 1, 'omitnan');
stats = struct( ...
    'num_repeats', size(values, 1), ...
    'mean', mu(:), ...
    'std', sigma(:), ...
    'cv_percent', [], ...
    'overall_cv_percent', nan);
stats.cv_percent = 100 * (stats.std ./ max(abs(stats.mean), eps));

muAll = mean(stats.mean, 'omitnan');
sigmaAll = mean(stats.std, 'omitnan');
if isfinite(muAll)
    stats.overall_cv_percent = 100 * sigmaAll / max(abs(muAll), eps);
end
end
