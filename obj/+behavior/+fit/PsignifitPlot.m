classdef (Abstract) PsignifitPlot
    % behavior.fit.PsignifitPlot -- psignifit's own plots, for a fit in the common schema.
    %
    % psignifit draws its figures itself, and these call its functions rather
    % than imitate them, so a fit looks the way psignifit's documentation and
    % papers show it:
    %
    %   behavior.fit.PsignifitPlot.psych(ax, F)          % plotPsych: data, fit, CI
    %   behavior.fit.PsignifitPlot.marginal(ax, F, 1)    % plotMarginal: posterior of one parameter
    %   behavior.fit.PsignifitPlot.pair(ax, F, 1, 2)     % plot2D: joint posterior of two
    %   behavior.fit.PsignifitPlot.bayes(F)              % plotBayes, in its own window
    %   behavior.fit.PsignifitPlot.priors(F)             % plotPrior, in its own window
    %   behavior.fit.PsignifitPlot.modelChecks(F)        % plotsModelfit, its own windows
    %
    % Parameters are numbered as psignifit numbers them: 1 threshold, 2
    % width, 3 lambda (lapse), 4 gamma (guess), 5 eta (overdispersion); a
    % name from behavior.fit.Psignifit.PARAMETERS works too.
    %
    % INTO ANY AXES. psignifit's plot functions draw into the CURRENT axes
    % (axes(h), then plot/hold/xlim with no axes argument). A uifigure hides
    % its handle, so its uiaxes is never current and those calls would open
    % a new figure; inWindow_ makes the target current for the duration of
    % the call -- HandleVisibility on, CurrentFigure and CurrentAxes set --
    % and puts everything back afterwards, Visible included (axes(h) shows
    % a hidden window). plot2D is the exception: it sets the FIGURE's
    % colormap, and a figure colormap write recolours every axes in the
    % window, even those with colormaps of their own (the Compare tab's
    % colour bar), so it draws into an off-screen scratch figure and what it
    % drew is moved into the target axes, which alone takes the colormap.
    % bayes, priors and modelChecks lay out whole figures of subplots, so
    % they get windows of their own, as psignifit intends.
    %
    % psych and marginal read only what the stored fit keeps; pair and bayes
    % need the whole posterior grid, which behavior.fit.Psignifit.posterior
    % refits (seconds on the standard grid). Every object drawn into an axes
    % is tagged BehaviorPlot:Psignifit<Role>; a fit psignifit did not make,
    % or could not make, draws its reason instead of an error, as
    % behavior.Plot does.
    %
    % Documentation: documentation/behavior/behavior_Classes.md
    % See also: behavior.fit.Psignifit, behavior.Plot.psychometric

    properties (Constant)
        LABEL_SIZE = 11
        FONT_SIZE = 9
    end

    methods (Static)
        function H = psych(ax, F, options)
            % H = behavior.fit.PsignifitPlot.psych(ax, F, Unit = "dB", ShowCI = true)
            % psignifit's plotPsych: the data (marker area by trials), the
            % fitted function (dashed beyond the data), the asymptotes, the
            % threshold, and its credible interval.
            %
            % Returns:
            %   H - struct Axes, Line (the fitted function), Data, Message
            arguments
                ax (1,1)
                F
                options.Unit (1,1) string = ""
                options.ShowCI (1,1) logical = true
                options.Parameter (1,1) string = "Stimulus level"
            end
            H = struct('Axes', ax, 'Line', gobjects(0), 'Data', gobjects(0), 'Message', gobjects(0));
            [ok, why] = behavior.fit.PsignifitPlot.hasFit_(F);
            if ~ok
                H.Message = behavior.fit.PsignifitPlot.noFit_(ax, why, "Psychometric function");
                return
            end
            res = F.Raw;
            xl = behavior.fit.PsignifitPlot.withUnit_(options.Parameter, options.Unit);
            if string(res.options.expType) == "YesNo"
                yl = 'Proportion yes';
            else
                yl = 'Proportion correct';
            end
            po = struct('h', ax, 'xLabel', char(xl), 'yLabel', yl, ...
                'labelSize', behavior.fit.PsignifitPlot.LABEL_SIZE, ...
                'fontSize', behavior.fit.PsignifitPlot.FONT_SIZE, ...
                'CIthresh', options.ShowCI && string(res.CriterionScale) == "relative");
            behavior.fit.PsignifitPlot.reset_(ax);
            [hl, hd] = behavior.fit.PsignifitPlot.inWindow_(ax, @() plotPsych(res, po));
            H.Line = hl;
            H.Data = hd(isgraphics(hd));
            behavior.fit.PsignifitPlot.tagAll_(ax, "PsignifitPsych");

            th = double(F.Threshold);
            sub = sprintf('psignifit %s, %s', string(F.Shape), string(res.options.expType));
            if isfinite(th)
                t = "Threshold " + sprintf('%.4g', th);
                if strlength(options.Unit) > 0, t = t + " " + options.Unit; end
                if isfinite(F.CI.ThresholdLo)
                    t = t + sprintf('  [%.4g, %.4g]', F.CI.ThresholdLo, F.CI.ThresholdHi);
                    sub = sprintf('%s; %g%% credible interval', sub, 100 * F.CI.Level);
                end
            else
                t = "No threshold";
            end
            title(ax, t, 'Interpreter', 'none', 'FontWeight', 'normal');
            subtitle(ax, sub, 'Interpreter', 'none', 'Color', [0.35 0.38 0.42]);
            if strlength(string(F.Message)) > 0
                H.Message = text(ax, 0.02, 0.97, string(F.Message), 'Units', 'normalized', ...
                    'VerticalAlignment', 'top', 'Interpreter', 'none', 'Color', [0.60 0.32 0.02], ...
                    'Tag', 'BehaviorPlot:PsignifitMessage');
            end
        end

        function H = marginal(ax, F, dim, options)
            % H = behavior.fit.PsignifitPlot.marginal(ax, F, dim, Unit = "dB")
            % psignifit's plotMarginal: the posterior of one parameter, its
            % prior (dashed) and its credible interval (shaded). A parameter
            % the fit held fixed has no posterior; the axes says so.
            arguments
                ax (1,1)
                F
                dim
                options.Unit (1,1) string = ""
            end
            H = struct('Axes', ax, 'Line', gobjects(0), 'Message', gobjects(0));
            dim = behavior.fit.PsignifitPlot.dim_(dim);
            label = behavior.fit.PsignifitPlot.parameterLabel_(dim);
            [ok, why] = behavior.fit.PsignifitPlot.hasFit_(F);
            if ~ok
                H.Message = behavior.fit.PsignifitPlot.noFit_(ax, why, label);
                return
            end
            res = F.Raw;
            if numel(res.marginals{dim}) <= 1
                plain = ["threshold" "width" "lapse rate" "guess rate" "overdispersion"];
                H.Message = behavior.fit.PsignifitPlot.noFit_(ax, sprintf('The %s was held fixed at %.4g.', ...
                    plain(dim), res.Fit(dim)), label);
                return
            end
            xl = label;
            if dim == 1
                if res.options.logspace
                    xl = "log threshold";
                else
                    xl = behavior.fit.PsignifitPlot.withUnit_("Threshold", options.Unit);
                end
            end
            po = struct('h', ax, 'xLabel', char(xl), 'labelSize', behavior.fit.PsignifitPlot.LABEL_SIZE);
            behavior.fit.PsignifitPlot.reset_(ax);
            H.Line = behavior.fit.PsignifitPlot.inWindow_(ax, @() plotMarginal(res, dim, po));
            set(ax, 'FontSize', behavior.fit.PsignifitPlot.FONT_SIZE);
            behavior.fit.PsignifitPlot.tagAll_(ax, "PsignifitMarginal");
        end

        function H = pair(ax, F, dim1, dim2)
            % H = behavior.fit.PsignifitPlot.pair(ax, F, dim1, dim2)
            % psignifit's plot2D: the joint posterior of two parameters (dim1
            % on y, dim2 on x). Needs the whole posterior, so it refits
            % (behavior.fit.Psignifit.posterior). When either parameter was
            % held fixed psignifit draws the other's marginal instead.
            arguments
                ax (1,1)
                F
                dim1
                dim2
            end
            H = struct('Axes', ax, 'Image', gobjects(0), 'Message', gobjects(0));
            dim1 = behavior.fit.PsignifitPlot.dim_(dim1);
            dim2 = behavior.fit.PsignifitPlot.dim_(dim2);
            what = behavior.fit.PsignifitPlot.parameterLabel_(dim1) + " vs " + ...
                behavior.fit.PsignifitPlot.parameterLabel_(dim2);
            [ok, why] = behavior.fit.PsignifitPlot.hasFit_(F);
            if ok && dim1 == dim2
                ok = false;
                why = "Choose two different parameters.";
            end
            if ~ok
                H.Message = behavior.fit.PsignifitPlot.noFit_(ax, why, what);
                return
            end
            full = behavior.fit.Psignifit.posterior(F);

            % plot2D sets the FIGURE's colormap, and a figure colormap write
            % recolours every axes in that window, even one with a colormap
            % of its own. So it draws into an off-screen scratch figure and
            % what it drew is moved into ax, which alone takes the colormap.
            scratch = figure('Visible', 'off', 'Position', [-20000 -20000 560 420], ...
                'HandleVisibility', 'on', 'Tag', 'BehaviorPlot:PsignifitScratch');
            removeScratch = onCleanup(@() delete(scratch));
            sax = axes(scratch);
            po = struct('h', sax, 'labelSize', behavior.fit.PsignifitPlot.LABEL_SIZE, ...
                'fontSize', behavior.fit.PsignifitPlot.FONT_SIZE);
            behavior.fit.PsignifitPlot.inWindow_(sax, @() plot2D(full, dim1, dim2, po));

            behavior.fit.PsignifitPlot.reset_(ax);
            copyobj(sax.Children, ax);
            set(ax, 'XLim', sax.XLim, 'YLim', sax.YLim, 'XDir', sax.XDir, 'YDir', sax.YDir, ...
                'XScale', sax.XScale, 'YScale', sax.YScale, 'CLim', sax.CLim, 'TickDir', sax.TickDir, ...
                'Box', sax.Box, 'FontSize', sax.FontSize, 'Layer', sax.Layer);
            xlabel(ax, sax.XLabel.String, 'FontSize', sax.XLabel.FontSize);
            ylabel(ax, sax.YLabel.String, 'FontSize', sax.YLabel.FontSize);
            colormap(ax, scratch.Colormap);
            delete(removeScratch);
            H.Image = findobj(ax, 'Type', 'image');
            behavior.fit.PsignifitPlot.tagAll_(ax, "PsignifitPair");
        end

        function fig = bayes(F)
            % fig = behavior.fit.PsignifitPlot.bayes(F)
            % psignifit's plotBayes -- every pair of parameters' joint
            % posterior -- in a window of its own (it lays out the figure).
            fig = behavior.fit.PsignifitPlot.window_(F, "Posterior (plotBayes)");
            full = behavior.fit.Psignifit.posterior(F);
            plotBayes(full);
        end

        function fig = priors(F)
            % fig = behavior.fit.PsignifitPlot.priors(F)
            % psignifit's plotPrior -- the prior on each parameter and the
            % functions it allows -- in a window of its own.
            fig = behavior.fit.PsignifitPlot.window_(F, "Priors (plotPrior)");
            plotPrior(F.Raw);
        end

        function figs = modelChecks(F)
            % figs = behavior.fit.PsignifitPlot.modelChecks(F)
            % psignifit's plotsModelfit: the fit, deviance residuals against
            % level and block, and the deviance against its bootstrap
            % distribution. It opens its own two windows; the bootstrap is
            % seeded and the global random stream is put back afterwards, so
            % looking at a fit never moves anyone else's random numbers.
            [ok, why] = behavior.fit.PsignifitPlot.hasFit_(F);
            if ~ok
                error('behavior:fit:PsignifitPlot:NoFit', '%s', why);
            end
            before = findall(groot, 'Type', 'figure');
            state = rng();
            restore = onCleanup(@() rng(state));
            rng(1, 'twister');
            plotsModelfit(F.Raw);
            delete(restore);
            after = findall(groot, 'Type', 'figure');
            figs = after(arrayfun(@(f) ~any(before == f), after));
            for k = 1:numel(figs)
                figs(k).Name = 'psignifit: model checks (plotsModelfit)';
                figs(k).NumberTitle = 'off';
                figs(k).Tag = 'BehaviorPlot:PsignifitWindow';
            end
        end
    end

    methods (Static, Access = private)
        function varargout = inWindow_(ax, fcn)
            % Run a psignifit plot function with ax as the current axes. Its
            % axes(h) also SHOWS a hidden window, so visibility is put back
            % with everything else.
            arguments
                ax (1,1)
                fcn (1,1) function_handle
            end
            fig = ancestor(ax, 'figure');
            state = struct('HandleVisibility', fig.HandleVisibility, 'Visible', fig.Visible);
            previous = get(groot, 'CurrentFigure');
            fig.HandleVisibility = 'on';
            restore = onCleanup(@() localRestore(fig, state, previous));
            set(groot, 'CurrentFigure', fig);
            fig.CurrentAxes = ax;
            [varargout{1:nargout}] = fcn();
            delete(restore);
        end

        function fig = window_(F, what)
            [ok, why] = behavior.fit.PsignifitPlot.hasFit_(F);
            if ~ok
                error('behavior:fit:PsignifitPlot:NoFit', '%s', why);
            end
            fig = figure('Name', char("psignifit: " + what), 'NumberTitle', 'off', ...
                'Tag', 'BehaviorPlot:PsignifitWindow', 'Color', 'w');
        end

        function [ok, why] = hasFit_(F)
            ok = false;
            why = "";
            if ~isstruct(F) || isempty(F)
                why = "No fit.";
            elseif ~isfield(F, 'Engine') || string(F(1).Engine) ~= "psignifit"
                why = "This fit was not made by psignifit. Choose it in Analysis > Settings > psignifit.";
            elseif ~isfield(F, 'Raw') || ~isstruct(F(1).Raw) || ~isfield(F(1).Raw, 'Fit')
                why = string(F(1).Message);
                if why == "", why = "psignifit made no fit."; end
            else
                ok = true;
            end
        end

        function h = noFit_(ax, why, label)
            behavior.fit.PsignifitPlot.reset_(ax);
            h = text(ax, 0.5, 0.5, string(why), 'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                'Interpreter', 'none', 'Color', [0.35 0.38 0.42], 'Tag', 'BehaviorPlot:PsignifitNoFit');
            title(ax, label, 'FontWeight', 'normal');     % TeX: the labels name \lambda etc.
            ax.XTick = [];
            ax.YTick = [];
        end

        function reset_(ax)
            % A datetime or categorical ruler left by another plot would
            % refuse psignifit's numbers; so would a lingering legend.
            legend(ax, 'off');
            cla(ax, 'reset');
        end

        function tagAll_(ax, role)
            c = ax.Children;
            for k = 1:numel(c)
                if c(k).Tag == ""
                    c(k).Tag = char("BehaviorPlot:" + role);
                end
            end
        end

        function d = dim_(d)
            if isstring(d) || ischar(d)
                k = find(behavior.fit.Psignifit.PARAMETERS == lower(string(d)), 1);
                if isempty(k)
                    error('behavior:fit:PsignifitPlot:Parameter', ...
                        'psignifit has no parameter "%s" (%s).', d, strjoin(behavior.fit.Psignifit.PARAMETERS, ", "));
                end
                d = k;
            end
            mustBeMember(d, 1:5);
        end

        function s = parameterLabel_(dim)
            names = ["Threshold" "Width" "Lapse rate (\lambda)" "Guess rate (\gamma)" "Overdispersion (\eta)"];
            s = names(dim);
        end

        function s = withUnit_(txt, unit)
            s = string(txt);
            if strlength(unit) > 0
                s = s + " (" + unit + ")";
            end
        end
    end
end



function localRestore(fig, state, previous)
% Put the window and the root back as they were before a psignifit call.
if isgraphics(fig)
    fig.HandleVisibility = state.HandleVisibility;
    fig.Visible = state.Visible;
end
if ~isempty(previous) && isgraphics(previous)
    set(groot, 'CurrentFigure', previous);
end
end
