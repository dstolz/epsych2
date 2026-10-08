classdef (Abstract) Builtin
    % behavior.fit.Builtin -- the built-in psychometric fit in the common schema.
    %
    % Every fitting engine hands its result back in ONE shape, so the
    % session view, the plots, the exports and a generated script never ask
    % which engine made it. The built-in engine is
    % psychophysics.Staircase.fitPsychometric (maximum likelihood); this
    % class only calls it and renames its fields.
    %
    %   F = behavior.fit.Builtin.fromStaircase(S, settings.fitArgs());
    %   if F.Converged && F.Identifiable, F.Threshold, end
    %
    % The common schema:
    %   Engine       - "builtin" | "psignifit"
    %   Shape        - "Logistic" | "Normal" | "Weibull"
    %   Threshold    - level at the criterion; NaN unless Converged AND
    %                  Identifiable (Raw.Threshold keeps whatever the
    %                  optimizer stopped at)
    %   Alpha, Beta  - location and slope (psignifit: its threshold parameter
    %                  in stimulus units, and the slope AT the threshold)
    %   Gamma        - lower asymptote (guess rate) used
    %   Lambda       - upper asymptote offset (lapse rate), fixed or fitted
    %   Width        - psignifit's width (the span between widthalpha and
    %                  1-widthalpha; log units for logn/weibull); NaN here
    %   Eta          - psignifit's overdispersion; NaN here
    %   Deviance     - deviance of the fit from the per-level data
    %   Warnings     - what the engine warned about but did not fail on
    %                  (string row; psignifit's captured warnings)
    %   Levels, NumYes, NumTotal, Proportion - per-level data (1,:)
    %   Curve        - struct x, P: the fitted function, for plotting
    %   CI           - struct ThresholdLo, ThresholdHi, Level (NaN without
    %                  a bootstrap)
    %   Converged, Identifiable - whether to believe it
    %   Message      - why not, when either is false ("" otherwise)
    %   Raw          - the engine's own result, untouched
    %
    % Documentation: documentation/behavior/behavior_Classes.md
    % See also: behavior.fit.Psignifit, behavior.Session.fit,
    %   psychophysics.Staircase.fitPsychometric

    methods (Static)
        function F = fromStaircase(S, fitOpts)
            % F = behavior.fit.Builtin.fromStaircase(S, fitOpts)
            % Fit the staircase's own trials and return the common schema.
            %
            % Parameters:
            %   S       - psychophysics.Staircase (offline or live)
            %   fitOpts - name-value cell for fitPsychometric
            %             (behavior.Settings.fitArgs)
            arguments
                S (1,1) psychophysics.Staircase
                fitOpts cell = {}
            end
            F = behavior.fit.Builtin.fromRaw(S.fitPsychometric(fitOpts{:}));
        end

        function F = fromRaw(R)
            % F = behavior.fit.Builtin.fromRaw(R)
            % The common schema from a fitPsychometric / fitProportions result.
            F = behavior.fit.Builtin.empty();
            F.Engine = "builtin";
            F.Shape = string(R.Shape);
            F.Alpha = R.Alpha;
            F.Beta = R.Beta;
            F.Gamma = R.GuessRate;
            F.Lambda = R.LapseRate;
            F.Deviance = R.Deviance;
            F.Levels = reshape(R.Levels, 1, []);
            F.NumYes = reshape(R.NumYes, 1, []);
            F.NumTotal = reshape(R.NumTotal, 1, []);
            F.Proportion = reshape(R.Proportion, 1, []);
            F.Curve = struct('x', reshape(R.Curve.x, 1, []), 'P', reshape(R.Curve.P, 1, []));
            F.CI = struct('ThresholdLo', R.CI.Threshold(1), 'ThresholdHi', R.CI.Threshold(2), ...
                'Level', R.CI.Level);
            F.Converged = logical(R.Converged);
            F.Identifiable = logical(R.Identifiable);
            F.Message = string(R.Message);
            if F.Converged && F.Identifiable
                F.Threshold = R.Threshold;
            elseif F.Message == ""
                F.Message = "The fit did not converge.";
            end
            F.Raw = R;
        end

        function F = empty()
            % F = behavior.fit.Builtin.empty()
            % The common schema with nothing fitted: NaN numbers, empty
            % vectors, Converged and Identifiable false.
            F = struct( ...
                'Engine',       "builtin", ...
                'Shape',        "", ...
                'Threshold',    NaN, ...
                'Alpha',        NaN, ...
                'Beta',         NaN, ...
                'Gamma',        NaN, ...
                'Lambda',       NaN, ...
                'Width',        NaN, ...
                'Eta',          NaN, ...
                'Deviance',     NaN, ...
                'Warnings',     strings(1,0), ...
                'Levels',       zeros(1,0), ...
                'NumYes',       zeros(1,0), ...
                'NumTotal',     zeros(1,0), ...
                'Proportion',   zeros(1,0), ...
                'Curve',        struct('x', zeros(1,0), 'P', zeros(1,0)), ...
                'CI',           struct('ThresholdLo', NaN, 'ThresholdHi', NaN, 'Level', NaN), ...
                'Converged',    false, ...
                'Identifiable', false, ...
                'Message',      "", ...
                'Raw',          struct());
        end
    end
end
