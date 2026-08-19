function smoke_test_metrics()
% smoke_test_metrics()
% Exercise psychophysics.Metrics, the stateless signal-detection arithmetic
% every analysis class now delegates to: the toolbox-free z-transform, the
% four corrections for rates of 0 and 1, d'/criterion/beta, the nonparametric
% A' and B'', proportion correct, the counts entry point, and the forwarding
% shims left behind in psychophysics.Detection and gui.Helper. Headless-safe:
% no figures are created.
%
%   matlab -batch "run('tmp/smoke_test_metrics.m')"

here = fileparts(mfilename('fullpath'));
run(fullfile(here,'..','epsych_startup.m'));

M   = @psychophysics.Metrics;      %#ok<NASGU> % named for the reader
Z   = @psychophysics.Metrics.z;
ZI  = @psychophysics.Metrics.zinv;
R   = @psychophysics.Metrics.rate;
D   = @psychophysics.Metrics.dprime;
C   = @psychophysics.Metrics.criterion;
LB  = @psychophysics.Metrics.lnBeta;
A   = @psychophysics.Metrics.aprime;
B   = @psychophysics.Metrics.bprimeprime;
PC  = @psychophysics.Metrics.percentCorrect;
CR  = @psychophysics.Metrics.correctRates;
tol = 1e-12;

hasStats = license('test','statistics_toolbox') && exist('norminv','file') == 2;

% 1. z and zinv ------------------------------------------------------------
% Published standard normal quantiles
assert(abs(Z(0.5)   - 0) < tol,                    'z(0.5) should be 0');
assert(abs(Z(0.75)  - 0.67448975019608182) < tol,  'z(0.75) should be 0.6744897...');
assert(abs(Z(0.9)   - 1.2815515655446004) < tol,   'z(0.9) should be 1.2815515...');
assert(abs(Z(0.975) - 1.9599639845400545) < tol,   'z(0.975) should be 1.9599639...');
assert(abs(Z(0.99)  - 2.3263478740408408) < tol,   'z(0.99) should be 2.3263478...');

p = 0.001:0.001:0.999;
assert(max(abs(Z(p) + Z(1-p))) < tol, 'z should be antisymmetric about p = 0.5');

% The extremes are reported honestly rather than corrected here
assert(Z(0) == -Inf && Z(1) == Inf, 'z should send 0 and 1 to -Inf and +Inf');
assert(isnan(Z(NaN)), 'z(NaN) should be NaN');
assert(isnan(Z(-0.1)) && isnan(Z(1.1)), 'a rate outside [0 1] should give NaN');
assert(isempty(Z([])), 'z of an empty rate should be empty');
assert(isequal(size(Z(rand(3,4))), [3 4]), 'z should preserve the shape of its input');

% z and zinv invert each other
assert(max(abs(ZI(Z(p)) - p)) < tol, 'zinv should invert z');
n = -4:0.01:4;
assert(max(abs(Z(ZI(n)) - n)) < 1e-10, 'z should invert zinv');
assert(ZI(-Inf) == 0 && ZI(Inf) == 1, 'zinv should map +/-Inf to 0 and 1');

% The toolbox-free promise, checked two ways: numerically where the toolbox
% is installed, and mechanically so a later edit cannot quietly undo it
if hasStats
    assert(max(abs(Z(p) - norminv(p))) < 1e-12, 'z should agree with norminv');
    assert(max(abs(ZI(n) - normcdf(n))) < 1e-12, 'zinv should agree with normcdf');
    fprintf('PASS: z/zinv agree with the Statistics Toolbox\n');
else
    fprintf('SKIP: Statistics Toolbox absent, z/zinv not cross-checked against norminv\n');
end

src = fileread(which('psychophysics.Metrics'));
code = regexprep(string(split(src, newline)), '%.*$', '');
assert(~any(contains(code, ["norminv(" "normcdf(" "normpdf(" "norminv " "normcdf "])), ...
    'psychophysics.Metrics must not call the Statistics Toolbox outside its comments');
fprintf('PASS: psychophysics.Metrics.z / zinv\n');

% 2. rate ------------------------------------------------------------------
assert(abs(R(3,10) - 0.3) < tol, 'rate(3,10) should be 0.3');
assert(isnan(R(0,0)), 'rate with no trials should be undefined, not zero');
assert(isnan(R(5,0)), 'a zero denominator should give NaN rather than Inf');
assert(isequaln(R([1 2 6],[10 0 30]), [0.1 NaN 0.2]), 'rate should be element-wise');
assert(isequal(R([2 4 6], 8), [0.25 0.5 0.75]), 'rate should broadcast a scalar denominator');
assert(isa(R(int32(3), int32(10)), 'double'), 'rate should return a double');
fprintf('PASS: psychophysics.Metrics.rate\n');

% 3. d' and criterion against published values ------------------------------
assert(abs(D(0.75,0.25,Correction="none") - 1.3489795003921636) < tol, 'd''(.75,.25)');
assert(abs(D(0.9, 0.1, Correction="none") - 2.5631031310892007) < tol, 'd''(.9,.1)');
assert(abs(D(0.99,0.01,Correction="none") - 4.6526957480816815) < tol, 'd''(.99,.01)');
assert(abs(D(0.6, 0.2, Correction="none") - 1.0949683367087140) < tol, 'd''(.6,.2)');

% Symmetric rates are unbiased; an asymmetric pair pins down the sign
for hf = [0.75 0.25; 0.9 0.1; 0.99 0.01]'
    assert(abs(C(hf(1),hf(2),Correction="none")) < tol, ...
        'symmetric rates should give an unbiased criterion');
end
assert(abs(C(0.6,0.2,Correction="none") - 0.2941370652185573) < tol, ...
    'c(.6,.2) should be positive (conservative)');
assert(abs(C(0.99,0.5,Correction="none") + 1.1631739370204204) < tol, ...
    'c(.99,.5) should be negative (liberal)');

% d' rises with the hit rate and is unmoved by relabelling
assert(all(diff(D(0.1:0.05:0.9, 0.2, Correction="none")) > 0), 'd'' should rise with the hit rate');
assert(abs(D(0.2,0.6,Correction="none") + D(0.6,0.2,Correction="none")) < tol, ...
    'swapping the rates should negate d''');

% The three bias measures are one quantity in three forms
hh = [0.6 0.9 0.99 0.3]; ff = [0.2 0.1 0.5 0.4];
assert(max(abs(LB(hh,ff,Correction="none") - ...
    C(hh,ff,Correction="none").*D(hh,ff,Correction="none"))) < 1e-14, ...
    'ln(beta) should equal c * d''');
assert(max(abs(psychophysics.Metrics.beta(hh,ff,Correction="none") - ...
    exp(LB(hh,ff,Correction="none")))) < tol, 'beta should be exp(ln beta)');
assert(max(abs(psychophysics.Metrics.criterionRelative(hh,ff,Correction="none") - ...
    C(hh,ff,Correction="none")./D(hh,ff,Correction="none"))) < tol, 'c'' should be c/d''');
fprintf('PASS: d'', criterion, beta against published values\n');

% 4. Corrections -----------------------------------------------------------
% Every mode the class advertises is accepted, and nothing else is
for mode = psychophysics.Metrics.CORRECTIONS
    if ismember(mode, ["halfcell","loglinear"])
        v = D(0.8, 0.2, Correction=mode, NSignal=10, NNoise=10);
    else
        v = D(0.8, 0.2, Correction=mode);
    end
    assert(isfinite(v), 'the "%s" correction should be accepted', mode);
end
assertThrows(@() D(0.8,0.2,Correction="bogus"), 'an unlisted correction should be rejected');

% "none" lets the extremes through
assert(D(1,0.2,Correction="none") == Inf,  'a perfect hit rate should give an infinite d''');
assert(D(0.8,0,Correction="none") == Inf,  'a zero false alarm rate should give an infinite d''');
assert(D(0,1,Correction="none") == -Inf,   'fully reversed rates should give -Inf');

% "clamp" reproduces the legacy max/min arithmetic for finite rates
bnds = [0.01 0.99];
for h = 0:0.05:1
    for f = 0:0.05:1
        legacy = zLegacy(max(min(h,bnds(2)),bnds(1))) - zLegacy(max(min(f,bnds(2)),bnds(1)));
        assert(abs(D(h,f,Correction="clamp",Bounds=bnds) - legacy) < tol, ...
            'the clamp correction should match the legacy arithmetic at (%g,%g)', h, f);
    end
end
assert(isequal(psychophysics.Metrics.DEFAULT_BOUNDS, [0.01 0.99]), ...
    'the default clamp should be [0.01 0.99]');
assert(abs(D(1,0,Correction="clamp") - D(1,0,Correction="clamp",Bounds=[0.01 0.99])) < tol, ...
    'the default Bounds should be DEFAULT_BOUNDS');

% "halfcell" moves only the extremes -- the equivalence that justifies
% implementing an extremes-only rule as a clamp
N = 10;
[hc, ~] = CR(0, 0.5, Correction="halfcell", NSignal=N, NNoise=N);
assert(abs(hc - 0.5/N) < tol, 'halfcell should map a rate of 0 to 1/(2N)');
[hc, ~] = CR(1, 0.5, Correction="halfcell", NSignal=N, NNoise=N);
assert(abs(hc - (1 - 0.5/N)) < tol, 'halfcell should map a rate of 1 to 1-1/(2N)');
for k = 1:N-1
    [hc, ~] = CR(k/N, 0.5, Correction="halfcell", NSignal=N, NNoise=N);
    assert(abs(hc - k/N) < tol, 'halfcell should leave the interior rate %d/%d alone', k, N);
end

% "loglinear" moves every rate, including the interior ones
[hc, ~] = CR(1, 0.5, Correction="loglinear", NSignal=N, NNoise=N);
assert(abs(hc - 10.5/11) < tol, 'loglinear should map 10/10 to 10.5/11');
[hc, ~] = CR(0, 0.5, Correction="loglinear", NSignal=N, NNoise=N);
assert(abs(hc - 0.5/11) < tol, 'loglinear should map 0/10 to 0.5/11');
[hc, ~] = CR(0.8, 0.5, Correction="loglinear", NSignal=N, NNoise=N);
assert(abs(hc - 8.5/11) < tol, 'loglinear should move interior rates too');

% The N-dependent modes refuse to guess
assertThrows(@() D(1,0.2,Correction="loglinear"), ...
    'loglinear without counts should error rather than fall back to a clamp', ...
    'psychophysics:Metrics:CountsRequired');
assertThrows(@() D(1,0.2,Correction="halfcell",NSignal=10), ...
    'halfcell should require the false alarm count as well', ...
    'psychophysics:Metrics:CountsRequired');

% They converge as trials accumulate, and both outrun a fixed clamp -- the
% demonstration that a trial-count-independent clamp discards data
dHalf = D(1,0,Correction="halfcell", NSignal=1000,NNoise=1000);
dLog  = D(1,0,Correction="loglinear",NSignal=1000,NNoise=1000);
assert(abs(dHalf - dLog) < 0.02, 'the two N-dependent corrections should converge at large N');
assert(dHalf > D(1,0,Correction="clamp",Bounds=[0.05 0.95]), ...
    'a fixed clamp should cap d'' below what 1000 trials support');

% The retired teensy.Simulator implementation, inlined
for ns = [4 10 50]
    for nn = [4 10 50]
        for h = [0 0.5 1]
            for f = [0 0.5 1]
                hL = min(max(h, 0.5/ns), 1 - 0.5/ns);
                fL = min(max(f, 0.5/nn), 1 - 0.5/nn);
                legacy = zLegacy(hL) - zLegacy(fL);
                assert(abs(D(h,f,Correction="halfcell",NSignal=ns,NNoise=nn) - legacy) < tol, ...
                    'halfcell should reproduce the monteCarlo implementation');
            end
        end
    end
end
fprintf('PASS: the four corrections and their equivalences\n');

% 5. NaN propagation -------------------------------------------------------
% This is the bug the class was built to fix: min/max drop NaN, so the
% obvious clamp turns an undefined rate into a bound.
[hc, fc] = CR(NaN, 0.2, Correction="clamp");
assert(isnan(hc) && abs(fc - 0.2) < tol, ...
    'correctRates must not turn an undefined rate into a bound');

for mode = ["none","clamp","halfcell","loglinear"]
    if ismember(mode, ["halfcell","loglinear"])
        args = {'Correction', mode, 'NSignal', 10, 'NNoise', 10};
    else
        args = {'Correction', mode};
    end
    assert(isnan(D(NaN,0.2,args{:})) && isnan(D(0.8,NaN,args{:})), ...
        'd'' should be NaN under "%s" when a rate is undefined', mode);
    assert(isnan(C(NaN,0.2,args{:})) && isnan(C(0.8,NaN,args{:})), ...
        'criterion should be NaN under "%s" when a rate is undefined', mode);
    assert(isnan(LB(NaN,0.2,args{:})), 'ln(beta) should be NaN under "%s"', mode);
    assert(isnan(psychophysics.Metrics.criterionRelative(NaN,0.2,args{:})), ...
        'c'' should be NaN under "%s"', mode);
end
assert(isnan(A(NaN,0.2)) && isnan(A(0.8,NaN)), 'A'' should be NaN when a rate is undefined');
assert(isnan(B(NaN,0.2)) && isnan(B(0.8,NaN)), 'B'''' should be NaN when a rate is undefined');
assert(isnan(PC(NaN,0.2)), 'percent correct should be NaN when a rate is undefined');

% A NaN keeps its place in a vector, and does not contaminate its neighbours
d = D([0.8 NaN 0.6], 0.2, Correction="clamp");
assert(isnan(d(2)) && abs(d(1) - D(0.8,0.2)) < tol && abs(d(3) - D(0.6,0.2)) < tol, ...
    'a NaN rate should not disturb the rates beside it');

% No trials behind a rate leaves it undefined rather than fabricated
assert(isnan(D(0,0.2,Correction="halfcell", NSignal=0,NNoise=10)), ...
    'halfcell with no signal trials should be NaN, not Inf');
assert(isnan(D(0,0.2,Correction="loglinear",NSignal=0,NNoise=10)), ...
    'loglinear with no signal trials should be NaN, not a fabricated 50%%');
fprintf('PASS: NaN propagates instead of becoming a bound\n');

% 6. Vectorization ---------------------------------------------------------
assert(max(abs(D([0.3 0.6 0.9],0.2) - [D(0.3,0.2) D(0.6,0.2) D(0.9,0.2)])) < tol, ...
    'a vector of hit rates should pair with a scalar false alarm rate');
assert(isequal(size(D([0.3;0.6],0.2)), [2 1]), 'a column of rates should give a column');
assert(isequal(size(D(rand(2,3),rand(2,3))), [2 3]), 'shapes should be preserved');
assert(isempty(D([],[])), 'empty rates should give an empty result');
assert(max(abs(D([0.5 1],0.2,Correction="halfcell",NSignal=[10 20],NNoise=50) - ...
    [D(0.5,0.2,Correction="halfcell",NSignal=10,NNoise=50) ...
     D(1,  0.2,Correction="halfcell",NSignal=20,NNoise=50)])) < tol, ...
    'NSignal should broadcast alongside the rates');
fprintf('PASS: broadcasting\n');

% 7. Round trips against theory --------------------------------------------
% Generate the rates an equal-variance Gaussian observer at a known d' and c
% would produce, and recover the parameters. Nothing here reuses the value
% under test to compute the expectation.
for dTrue = [0.5 1 2 3]
    for cTrue = [-1 -0.5 0 0.5 1]
        h = ZI(dTrue/2 - cTrue);
        f = ZI(-dTrue/2 - cTrue);
        assert(abs(D(h,f,Correction="none") - dTrue) < 1e-10, ...
            'd'' should be recovered at d''=%g, c=%g', dTrue, cTrue);
        assert(abs(C(h,f,Correction="none") - cTrue) < 1e-10, ...
            'c should be recovered at d''=%g, c=%g', dTrue, cTrue);
        assert(abs(LB(h,f,Correction="none") - cTrue*dTrue) < 1e-10, ...
            'ln(beta) should be recovered at d''=%g, c=%g', dTrue, cTrue);
    end
end

for dTrue = [0.5 1 2 3]
    h = ZI(dTrue/2); f = ZI(-dTrue/2);
    % The balanced yes/no proportion correct at an unbiased criterion is
    % zinv(d'/2); zinv(d'/sqrt(2)) below is the 2AFC quantity, which is a
    % different number for the same observer.
    assert(abs(PC(h,f) - ZI(dTrue/2)) < 1e-10, ...
        'unbiased percent correct should be zinv(d''/2) at d''=%g', dTrue);
    assert(abs(psychophysics.Metrics.dprime2AFC(ZI(dTrue/sqrt(2)),Correction="none") - dTrue) < 1e-10, ...
        'dprime2AFC should invert the 2AFC relation at d''=%g', dTrue);
    % A' estimates the area under the ROC curve, which for equal-variance
    % Gaussian evidence is zinv(d'/sqrt(2))
    assert(abs(A(h,f) - ZI(dTrue/sqrt(2))) < 0.03, ...
        'A'' should track the Gaussian ROC area at d''=%g', dTrue);
end
fprintf('PASS: round trips against theory\n');

% 8. Nonparametric metrics -------------------------------------------------
% A' moved from psychophysics.Detection; the move must be exact
grid = 0:0.1:1;
for h = grid
    for f = grid
        assert(abs(A(h,f) - psychophysics.Detection.a_prime(h,f)) < tol, ...
            'aprime should match Detection.a_prime at (%g,%g)', h, f);
    end
end
assert(abs(A(1,0) - 1) < tol && abs(A(0,1)) < tol, 'A'' should span [0 1]');
assert(abs(A(0.8,0.2) - 0.875) < tol, 'A''(0.8,0.2) should be 0.875');

assert(abs(B(0.8,0.8)) < tol, 'B'''' should be 0 when the rates match');
assert(abs(B(0.8,0.2)) < tol, 'B'''' should be 0 when the rates are symmetric');
assert(abs(B(0.99,0.5) + 0.92381685263562907) < tol, 'B''''(.99,.5) should be strongly liberal');
assert(B(0.5,0.1) > 0, 'B'''' should be positive (conservative) when the FA rate is low');
for h = grid
    for f = grid
        b = B(h,f);
        assert(b >= -1-tol && b <= 1+tol, 'B''''(%g,%g) = %g is outside [-1 1]', h, f, b);
        % B'' is symmetric under a swap, unlike A': the sign factor exists so
        % that a sparse responder reads as conservative whichever
        % distribution the rates came from
        assert(abs(b - B(f,h)) < tol, 'B'''' should be unchanged when the rates swap');
    end
end
assert(B(1,0) == 0 && B(0,1) == 0 && B(1,1) == 0, ...
    'rates that extreme carry no evidence about bias, so B'''' is 0');
fprintf('PASS: A'' and B''''\n');

% 9. percentCorrect and dprime2AFC -----------------------------------------
assert(max(abs(PC(hh,ff) - (0.5 + (hh-ff)/2))) < tol, 'percentCorrect should match its formula');
assert(abs(PC(0.5,0.5) - 0.5) < tol, 'matched rates should give chance');
assert(abs(PC(1,0) - 1) < tol && abs(PC(0,1)) < tol, 'percentCorrect should span [0 1]');
assert(abs(psychophysics.Metrics.dprime2AFC(0.5,Correction="none")) < tol, ...
    '2AFC chance should give d'' = 0');
assert(abs(psychophysics.Metrics.dprime2AFC(0.75,Correction="none") - sqrt(2)*Z(0.75)) < tol, ...
    'dprime2AFC should be sqrt(2)*z(pc)');
assertThrows(@() psychophysics.Metrics.dprime2AFC(1,Correction="loglinear"), ...
    'dprime2AFC should require a trial count for the N-dependent modes', ...
    'psychophysics:Metrics:CountsRequired');
fprintf('PASS: percentCorrect and dprime2AFC\n');

% 10. fromCounts -----------------------------------------------------------
S = psychophysics.Metrics.fromCounts(18, 7, 3, 22);
assert(S.N.Signal == 25 && S.N.Noise == 25 && S.N.Total == 50, 'the counts should add up');
assert(abs(S.Rate.Hit - 0.72) < tol && abs(S.Rate.FalseAlarm - 0.12) < tol, 'the observed rates');
assert(abs(S.Rate.Miss - 0.28) < tol && abs(S.Rate.CorrectReject - 0.88) < tol, ...
    'the complementary rates');
assert(abs(S.DPrime    - D(0.72,0.12)) < tol, 'DPrime should match the standalone method');
assert(abs(S.Criterion - C(0.72,0.12)) < tol, 'Criterion should match the standalone method');
assert(abs(S.APrime    - A(0.72,0.12)) < tol, 'APrime should match the standalone method');
assert(abs(S.BPrimePrime - B(0.72,0.12)) < tol, 'BPrimePrime should match the standalone method');
assert(abs(S.LnBeta    - LB(0.72,0.12)) < tol, 'LnBeta should match the standalone method');
assert(S.Correction == "clamp" && isequal(S.Bounds,[0.01 0.99]), ...
    'fromCounts should record which correction it applied');

% Observed and balanced percent correct differ once the trial mix is uneven,
% and the distinction must not be flattened by a later edit
assert(abs(S.PercentCorrect - 40/50) < tol, 'observed percent correct on a balanced session');
assert(abs(S.PercentCorrectBalanced - 0.8) < tol, 'balanced percent correct on a balanced session');
U = psychophysics.Metrics.fromCounts(72, 18, 5, 5);   % 90 stimulus, 10 catch
assert(abs(U.PercentCorrect - 77/100) < tol, 'observed percent correct weights the trial mix');
assert(abs(U.PercentCorrectBalanced - PC(0.8,0.5)) < tol, 'balanced percent correct ignores it');
assert(abs(U.PercentCorrect - U.PercentCorrectBalanced) > 0.1, ...
    'observed and balanced percent correct must stay distinct');

% Corrections reach the metrics but never the reported rates
L = psychophysics.Metrics.fromCounts(10, 0, 0, 10, Correction="loglinear");
assert(abs(L.Rate.Hit - 1) < tol && abs(L.Rate.FalseAlarm) < tol, ...
    'Rate should report what was observed');
assert(abs(L.RateCorrected.Hit - 10.5/11) < tol, 'RateCorrected should report what z saw');
assert(isfinite(L.DPrime), 'a log-linear correction should give a finite d'' at 10/10');
assert(abs(L.APrime - A(1,0)) < tol, 'A'' should take the uncorrected rates');

% Missing trials leave the affected half undefined
E = psychophysics.Metrics.fromCounts(0,0,3,22);
assert(isnan(E.Rate.Hit) && isnan(E.DPrime) && isnan(E.APrime), ...
    'no stimulus trials should leave sensitivity undefined');
assert(abs(E.Rate.FalseAlarm - 3/25) < tol, 'the catch side should still be reported');
E2 = psychophysics.Metrics.fromCounts(5,5,0,0);
assert(isnan(E2.Rate.FalseAlarm) && isnan(E2.DPrime), 'no catch trials should leave d'' undefined');
for mode = ["none","clamp","halfcell","loglinear"]
    assert(isnan(psychophysics.Metrics.fromCounts(0,0,3,22,Correction=mode).DPrime), ...
        'an empty stimulus set should be undefined under "%s" too', mode);
end

% Counts broadcast
V = psychophysics.Metrics.fromCounts([3 6 9],[7 4 1],4,16);
assert(isequal(size(V.DPrime),[1 3]), 'fromCounts should broadcast to a row');
assert(max(abs(V.DPrime - [D(0.3,0.2) D(0.6,0.2) D(0.9,0.2)])) < tol, ...
    'the broadcast d'' should match three scalar calls');
assert(max(abs(V.APrime - A([0.3 0.6 0.9],0.2))) < tol, 'the broadcast A''');
fprintf('PASS: fromCounts\n');

% 11. The aborts policy ----------------------------------------------------
RD = @psychophysics.Metrics.rateDenominator;
assert(RD(20, 5, false) == 20, 'aborts should stay out of the denominator by default');
assert(RD(20, 5, true)  == 25, 'IncludeAborts should add them');
assert(RD(20, 0, true)  == 20, 'no aborts means no difference');
assert(isequal(RD([10 20], [1 2], true), [11 22]), 'rateDenominator should broadcast');
assert(isequal(RD([10 20], 3, true), [13 23]), 'a scalar abort count should broadcast');

% 8 hits, 2 misses and 5 aborts on the stimulus side
Ax = psychophysics.Metrics.fromCounts(8, 2, 3, 7, AbortSignal=5, AbortNoise=0);
assert(Ax.N.Signal == 10 && abs(Ax.Rate.Hit - 0.8) < tol, ...
    'by default an abort should not depress the hit rate');
assert(Ax.N.AbortSignal == 5 && Ax.N.AbortNoise == 0, 'the abort counts should be reported');
assert(Ax.IncludeAborts == false, 'fromCounts should record the policy it applied');

Ai = psychophysics.Metrics.fromCounts(8, 2, 3, 7, AbortSignal=5, AbortNoise=0, ...
    IncludeAborts=true);
assert(Ai.N.Signal == 15 && abs(Ai.Rate.Hit - 8/15) < tol, ...
    'IncludeAborts should score aborts as failures to respond');
assert(Ai.N.Noise == 10 && abs(Ai.Rate.FalseAlarm - 0.3) < tol, ...
    'the catch side should be untouched when it has no aborts');
assert(Ai.DPrime < Ax.DPrime, 'counting aborts against the hit rate should lower d''');
assert(Ai.IncludeAborts == true, 'fromCounts should record the policy it applied');

% Each side answers to its own abort count
An = psychophysics.Metrics.fromCounts(8, 2, 3, 7, AbortNoise=10, IncludeAborts=true);
assert(An.N.Signal == 10 && An.N.Noise == 20, 'aborts should be charged to their own side');
assert(abs(An.Rate.Hit - 0.8) < tol, 'a catch-side abort should not move the hit rate');

% Supplying counts without the flag changes nothing, so a caller can pass
% them unconditionally and flip one option
A0 = psychophysics.Metrics.fromCounts(8, 2, 3, 7);
assert(isequaln(rmfield(A0,'N'), rmfield(Ax,'N')), ...
    'abort counts should be inert while IncludeAborts is false');
fprintf('PASS: the aborts policy\n');

% 12. Backward-compatibility shims -----------------------------------------
for h = 0.05:0.1:0.95
    for f = 0.05:0.1:0.95
        legacy = zLegacy(max(min(h,0.99),0.01)) - zLegacy(max(min(f,0.99),0.01));
        assert(abs(psychophysics.Detection.d_prime(h,f) - legacy) < tol, ...
            'Detection.d_prime should keep its historic value at (%g,%g)', h, f);
        legacyC = -(zLegacy(max(min(h,0.95),0.05)) + zLegacy(max(min(f,0.95),0.05)))/2;
        assert(abs(psychophysics.Detection.bias(h,f,[0.05 0.95]) - legacyC) < tol, ...
            'Detection.bias should keep its historic value at (%g,%g)', h, f);
        assert(abs(gui.Helper.criterion(h,f) - ...
            (-(zLegacy(max(min(h,0.99),0.01)) + zLegacy(max(min(f,0.99),0.01)))/2)) < tol, ...
            'gui.Helper.criterion should keep its historic value');
        assert(abs(gui.Helper.dprime2AFC(h) - sqrt(2)*zLegacy(max(min(h,0.99),0.01))) < tol, ...
            'gui.Helper.dprime2AFC should keep its historic value');
        assert(abs(gui.Helper.percent_correct(h,f) - (0.5+(h-f)/2)) < tol, ...
            'gui.Helper.percent_correct should keep its historic value');
    end
end
assert(abs(psychophysics.Detection.norminv(0.5) - 0) < tol, 'Detection.norminv should still work');
assert(abs(psychophysics.Detection.norminv(0.999) - zLegacy(0.99)) < tol, ...
    'Detection.norminv should still clamp');

% The one intentional change: an undefined rate no longer becomes a bound
assert(isnan(psychophysics.Detection.norminv(NaN)), ...
    'Detection.norminv(NaN) should now be NaN rather than the upper bound');
assert(isnan(psychophysics.Detection.d_prime(NaN,0.2)), ...
    'Detection.d_prime should now propagate an undefined rate');
fprintf('PASS: Detection and gui.Helper shims\n');

% 13. Consumers still agree ------------------------------------------------
% 20 trials: 12 stimulus (8 hit, 3 miss, 1 abort), 8 catch (2 FA, 6 CR).
% The expected values were computed with the pre-refactor code.
SM = psychophysics.SessionMetrics(fakeData());
assert(abs(SM.Results.Rate.Hit - 8/11) < tol && abs(SM.Results.Rate.FalseAlarm - 2/8) < tol, ...
    'the fixture should give the expected rates');
assert(abs(SM.Results.DPrime    - 1.2790750967793190) < tol, 'SessionMetrics d'' is unchanged');
assert(abs(SM.Results.Criterion - 0.0349522018064223) < tol, 'SessionMetrics criterion is unchanged');
assert(abs(SM.Results.APrime    - 0.8231534090909092) < tol, 'SessionMetrics A'' is unchanged');
assert(abs(SM.Results.BPrimePrime - 0.0281124497991967) < tol, 'SessionMetrics B''''');

d0 = SM.Results.DPrime; a0 = SM.Results.APrime;
SM.CorrectionMode = "loglinear";
assert(abs(SM.Results.DPrime - d0) > 1e-9, 'CorrectionMode should change d''');
assert(abs(SM.Results.APrime - a0) < tol, 'CorrectionMode should not touch A''');
SM.CorrectionMode = "clamp";
assert(abs(SM.Results.DPrime - d0) < tol, 'the correction should be reversible');

assert(ismember("BPrimePrime", psychophysics.SessionMetrics.metricNames()), ...
    'B'''' should be a named metric');
assert(~ismember("BPrimePrime", psychophysics.SessionMetrics.defaultMetrics()), ...
    'B'''' should not join the default display');
T = SM.summary();
assert(T.Group(T.Name == "BPrimePrime") == "Sensitivity", 'B'''' belongs to the Sensitivity group');

% The fixture's one abort is on a stimulus trial, so the policy is visible
assert(SM.Results.N.AbortStimulus == 1 && SM.Results.N.AbortCatch == 0, ...
    'aborts should be split by trial type');
assert(SM.IncludeAborts == false, 'aborts should be excluded by default');
assert(SM.Results.N.Scored == 11, 'the default denominator should be Hit + Miss');

SM.IncludeAborts = true;
assert(SM.Results.N.Scored == 12, 'IncludeAborts should add the aborted stimulus trial');
assert(abs(SM.Results.Rate.Hit - 8/12) < tol, 'the hit rate should follow the denominator');
assert(abs(SM.Results.Rate.FalseAlarm - 2/8) < tol, ...
    'the catch side has no aborts, so it should not move');
[~, ~, detail] = SM.metric("HitRate");
assert(detail == "8/12", 'the reported fraction should match the rate (got "%s")', detail);
SM.IncludeAborts = false;
assert(abs(SM.Results.Rate.Hit - 8/11) < tol, 'the policy should be reversible');

% An empty window leaves everything undefined rather than at chance
SM.TrialWindow = psychophysics.TrialWindow.range(50,60);
assert(isnan(SM.Results.DPrime) && isnan(SM.Results.BPrimePrime), ...
    'an empty window should leave the metrics undefined');
fprintf('PASS: psychophysics.SessionMetrics delegates unchanged\n');

% 14. psychophysics.Detection uses the same policy -------------------------
% 3 levels x 10 stimulus trials (3/6/9 hits, the rest split miss/abort) and
% 20 catch trials (4 FA, 14 CR, 2 aborts).
DT = fakeDetection();
assert(max(abs(DT.Hit_Rate - [3/8 6/9 9/10])) < tol, ...
    'Hit_Rate should divide by the answered stimulus trials, not all of them');
assert(max(abs(DT.FA_Rate - 4/18)) < tol, ...
    'FA_Rate should divide by the answered catch trials');
assert(max(abs(DT.Miss_Rate - (1 - DT.Hit_Rate))) < tol, 'Miss_Rate is the complement');

DT.IncludeAborts = true;
assert(max(abs(DT.Hit_Rate - [3/10 6/10 9/10])) < tol, ...
    'IncludeAborts should put the aborted trials back in the denominator');
assert(max(abs(DT.FA_Rate - 4/20)) < tol, 'and on the catch side too');
DT.IncludeAborts = false;
assert(max(abs(DT.Hit_Rate - [3/8 6/9 9/10])) < tol, 'the policy should be reversible');
fprintf('PASS: psychophysics.Detection honors IncludeAborts\n');

fprintf('\nALL PASS: smoke_test_metrics\n');
end


function z = zLegacy(p)
% The z-transform as the pre-refactor code computed it, so the compatibility
% checks compare against something this class did not produce. Written with
% erfcinv rather than norminv so the test still runs without the toolbox;
% section 1 is what proves the two agree.
z = -sqrt(2) * erfcinv(2 * p);
end


function assertThrows(fcn, msg, id)
% Assert that fcn() errors, optionally with a specific identifier.
arguments
    fcn function_handle
    msg (1,1) string
    id (1,1) string = ""
end
try
    fcn();
catch ME
    if id ~= "" && ~strcmp(ME.identifier, id)
        error('smoke_test_metrics:wrongError', ...
            '%s (threw %s instead of %s)', msg, ME.identifier, id);
    end
    return
end
error('smoke_test_metrics:expectedError', '%s', msg);
end


function DATA = fakeData()
% 20 trials: 12 stimulus (8 hit, 3 miss, 1 abort), 8 catch (2 FA, 6 CR).
stim = epsych.BitMask.TrialType_0;
ctch = epsych.BitMask.TrialType_1;
codes = [ ...
    repmat(bit(epsych.BitMask.Hit,  stim), 1, 8), ...
    repmat(bit(epsych.BitMask.Miss, stim), 1, 3), ...
    bit(epsych.BitMask.Abort, stim), ...
    repmat(bit(epsych.BitMask.FalseAlarm,    ctch), 1, 2), ...
    repmat(bit(epsych.BitMask.CorrectReject, ctch), 1, 6)];
types = [zeros(1,12) ones(1,8)];

DATA = struct('RespCode', num2cell(codes), 'TrialType', num2cell(types), ...
    'TrialID', num2cell(1:20));
end


function D = fakeDetection()
% Three stimulus levels of 10 trials each with 3/6/9 hits and 2/1/0 aborts,
% so every level has a different answered count, plus 20 catch trials
% (4 false alarms, 14 correct rejects, 2 aborts).
stim = epsych.BitMask.TrialType_0;
ctch = epsych.BitMask.TrialType_1;

levels   = [10 20 30];
nHit     = [3 6 9];
nAbort   = [2 1 0];

codes = uint32([]);
vals  = [];
types = [];
for i = 1:numel(levels)
    nMiss = 10 - nHit(i) - nAbort(i);
    c = [repmat(bit(epsych.BitMask.Hit,   stim), 1, nHit(i)), ...
         repmat(bit(epsych.BitMask.Miss,  stim), 1, nMiss), ...
         repmat(bit(epsych.BitMask.Abort, stim), 1, nAbort(i))];
    codes = [codes c]; %#ok<AGROW>
    vals  = [vals repmat(levels(i), 1, 10)]; %#ok<AGROW>
    types = [types zeros(1,10)]; %#ok<AGROW>
end
codes = [codes, repmat(bit(epsych.BitMask.FalseAlarm,    ctch), 1, 4), ...
                repmat(bit(epsych.BitMask.CorrectReject, ctch), 1, 14), ...
                repmat(bit(epsych.BitMask.Abort,         ctch), 1, 2)];
vals  = [vals zeros(1,20)];
types = [types ones(1,20)];

TRIALS.DATA = struct('RespCode', num2cell(codes), 'TrialType', num2cell(types), ...
    'Level', num2cell(vals));
TRIALS.TrialIndex  = numel(codes);
TRIALS.Subject     = struct('Name','TEST');
TRIALS.BoxID       = 1;
TRIALS.writeparams = {'Level'};

RUNTIME.EVENTS = epsych.EventHub;
P = struct('Name','Level','validName','Level');

D = psychophysics.Detection(RUNTIME, P, epsych.BitMask.TrialType_0);
D.update_data([], epsych.TrialsData(TRIALS));
end


function m = bit(varargin)
m = uint32(0);
for i = 1:nargin
    m = bitset(m, double(varargin{i}));
end
end
