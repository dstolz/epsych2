function flags = qc_(sess, R, settings, noParameter, ranStaircase)
% flags = qc_(sess, R, settings, noParameter, ranStaircase)
% The QC flags of one analysed session: the file's own (QCFile, from the
% catalog or load) followed by the analysis's, against settings.QC:
%
%   low_trials      - fewer included trials than QC.MinTrials
%   high_abort_rate - the included trials' abort rate above QC.MaxAbortRate
%   few_reversals   - a staircase ran but reversed fewer than
%                     QC.MinReversals times
%   no_parameter    - no parameter to analyse, or the file lacks it
%   fit_failed      - fitting is on and the fit did not converge or is not
%                     identifiable
%
% A flag marks a session for a look; it never removes it from anything.

Q = settings.QC;
flags = reshape(sess.QCFile, 1, []);

if R.NumIncluded < Q.MinTrials
    flags(end+1) = "low_trials";
end
abortRate = R.Metrics.Rate.Abort;
if ~isnan(abortRate) && abortRate > Q.MaxAbortRate
    flags(end+1) = "high_abort_rate";
end
if ranStaircase && R.ReversalCount < Q.MinReversals
    flags(end+1) = "few_reversals";
end
if noParameter
    flags(end+1) = "no_parameter";
end
if ranStaircase && settings.Fit.Enabled && ~(R.Fit.Converged && R.Fit.Identifiable)
    flags(end+1) = "fit_failed";
end

flags = unique(flags, 'stable');

end
