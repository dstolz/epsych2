classdef (Abstract) Psignifit
    % behavior.fit.Psignifit -- the psignifit engine's seam (v2).
    %
    % psignifit (https://github.com/wichmann-lab/psignifit) fits a
    % psychometric function by Bayesian inference over the same per-level
    % counts the built-in engine uses. v1 of the offline analysis ships the
    % built-in engine only; this class is where psignifit plugs in, so that
    % behavior.Settings.Fit.Engine, behavior.Session.fit, the common fit
    % schema (behavior.fit.Builtin) and the exports already have a place for
    % it.
    %
    %   behavior.fit.Psignifit.available()        % installed and on the path?
    %   behavior.fit.Psignifit.whyUnavailable()   % why it cannot be used now
    %
    % FINDING IT. psignifit is not a toolbox and is not shipped with EPsych.
    % available() adds getpref('EPsych','PsignifitPath') to the path once,
    % when that preference exists (read behind ispref, which never creates
    % it), mirroring how epsych_startup finds granary. Point it at the folder
    % holding psignifit.m:
    %   setpref('EPsych', 'PsignifitPath', 'C:\src\psignifit')
    %
    % PLANNED MAPPING (v2), so the common schema needs no change:
    %   data      [levels(:) numYes(:) numTotal(:)] -- exactly psignifit's
    %             data matrix, taken from the built-in fit's counts
    %   options.sigmoidName  <- Settings.Fit.Shape ("Logistic" -> 'logistic',
    %             "Normal" -> 'norm', "Weibull" -> 'weibull')
    %   options.expType      <- 'YesNo' with GuessRate/LapseRate priors, or
    %             'nAFC' (expN) for a forced-choice paradigm
    %   options.threshPC     <- Settings.Fit.ThresholdCriterion (psignifit
    %             reads it between the asymptotes, as CriterionScale
    %             "relative" does)
    %   result.Fit = [threshold width lambda gamma eta] -> Threshold, Alpha,
    %             Beta (from width), Lambda, Gamma; result.conf_Intervals ->
    %             CI.ThresholdLo/ThresholdHi at Settings.Fit.ConfidenceLevel;
    %             Converged/Identifiable from the posterior's spread;
    %             Raw keeps psignifit's whole result.
    %
    % Documentation: documentation/behavior/behavior_Classes.md
    % See also: behavior.fit.Builtin, behavior.Session.fit, behavior.Settings

    properties (Constant)
        URL (1,1) string = "https://github.com/wichmann-lab/psignifit"
    end

    methods (Static)
        function tf = available()
            % tf = behavior.fit.Psignifit.available()
            % Whether psignifit is on the path, after adding the folder named
            % by the EPsych/PsignifitPath preference (once per session).
            persistent added
            if isempty(added)
                added = true;
                if ispref('EPsych', 'PsignifitPath')
                    folder = string(getpref('EPsych', 'PsignifitPath'));
                    if isfolder(folder)
                        addpath(folder);
                        vprintf(2, 'behavior.fit.Psignifit: added "%s" to the path', folder)
                    else
                        vprintf(1, 'behavior.fit.Psignifit: EPsych/PsignifitPath names "%s", which is not a folder', folder)
                    end
                end
            end
            tf = exist('psignifit', 'file') == 2;
        end

        function why = whyUnavailable()
            % why = behavior.fit.Psignifit.whyUnavailable()
            % Why the psignifit engine cannot fit now, in one sentence. In
            % this version that is always something: when psignifit is
            % installed, the engine is still not wired.
            if behavior.fit.Psignifit.available()
                why = "psignifit is installed, but this version of EPsych fits with the built-in engine only (psignifit arrives in v2).";
            else
                why = "psignifit is not installed (" + behavior.fit.Psignifit.URL + ...
                    "); put it on the path or setpref('EPsych','PsignifitPath',<folder>).";
            end
        end

        function F = fromCounts(levels, numYes, numTotal, opts)
            % F = behavior.fit.Psignifit.fromCounts(levels, numYes, numTotal, opts)
            % The common fit struct from psignifit (v2). In this version it
            % always errors: behavior:fit:Psignifit:NotAvailable when
            % psignifit cannot be found, behavior:fit:Psignifit:NotImplemented
            % when it can.
            %
            % Parameters:
            %   levels, numYes, numTotal - per-level counts (psignifit's
            %                              data matrix, column by column)
            %   opts                     - behavior.Settings.Fit
            arguments
                levels double
                numYes double
                numTotal double
                opts (1,1) struct = struct()
            end
            F = behavior.fit.Builtin.empty();
            F.Engine = "psignifit";
            if ~behavior.fit.Psignifit.available()
                error('behavior:fit:Psignifit:NotAvailable', ...
                    ['psignifit is not installed. Get it from %s and put it on the path, ' ...
                    'or name its folder with setpref(''EPsych'',''PsignifitPath'',<folder>).'], ...
                    behavior.fit.Psignifit.URL);
            end
            vprintf(3, 'behavior.fit.Psignifit: options %s', jsonencode(opts))
            error('behavior:fit:Psignifit:NotImplemented', ...
                ['The psignifit engine arrives in v2 (%d levels, %d of %d trials "yes", not fitted); ' ...
                'set Settings.Fit.Engine = "builtin".'], numel(levels), sum(numYes), sum(numTotal));
        end
    end
end
