function [standardFiles, deviantFiles] = make_oddball_sounds(folder, options)
% [standardFiles, deviantFiles] = make_oddball_sounds(folder, Name=Value, ...)
% Synthesize the default sound banks for the oddball example: a bank of
% steady tones to serve as standards and a bank of rising frequency glides
% to serve as deviants, each written as a .wav file.
%
% The two banks differ in KIND rather than in one value, which is what makes
% this a categorical oddball: the standards vary among themselves (four
% different pitches), so the subject cannot detect a deviant by noticing
% that "the pitch changed" -- only by noticing that the sound glided. Swap in
% your own recordings with create_oddball_protocol(StandardFiles=...,
% DeviantFiles=...) or from the behavior GUI's Sound Banks panel.
%
% Files that already exist are left alone unless Overwrite is true, so the
% banks are generated once and then reused.
%
% Parameters:
%   folder - Output root. Standards go in <folder>/standards, deviants in
%            <folder>/deviants. Default: sounds/ beside this file.
%
% Options:
%   StandardFreqs - Standard tone frequencies, Hz (default [700 850 1000 1200])
%   DeviantFreqs  - Starting frequencies of the deviant glides, Hz; each
%                   rises one octave (default [700 850 1000])
%   Duration      - Sound duration, s (default 0.15)
%   RampDur       - Raised-cosine on/off ramp, s (default 0.005)
%   Level         - Peak amplitude, 0-1 (default 0.25)
%   SampleRate    - Hz (default 44100)
%   Overwrite     - Rewrite files that already exist (default false)
%
% Returns:
%   standardFiles - string row of absolute paths to the standard .wav files
%   deviantFiles  - string row of absolute paths to the deviant .wav files
%
% Try it:
%   [s, d] = make_oddball_sounds;
%   [y, fs] = audioread(d(1)); sound(y, fs)
%
% See also create_oddball_protocol, audiowrite

arguments
    folder (1,:) char = ''
    options.StandardFreqs (1,:) double {mustBePositive} = [700 850 1000 1200]
    options.DeviantFreqs (1,:) double {mustBePositive} = [700 850 1000]
    options.Duration (1,1) double {mustBePositive} = 0.15
    options.RampDur (1,1) double {mustBeNonnegative} = 0.005
    options.Level (1,1) double {mustBeInRange(options.Level, 0, 1)} = 0.25
    options.SampleRate (1,1) double {mustBePositive, mustBeInteger} = 44100
    options.Overwrite (1,1) logical = false
end

if isempty(folder)
    folder = fullfile(fileparts(mfilename('fullpath')), 'sounds');
end
stdDir = fullfile(folder, 'standards');
devDir = fullfile(folder, 'deviants');
if ~isfolder(stdDir), mkdir(stdDir); end
if ~isfolder(devDir), mkdir(devDir); end

fs = options.SampleRate;
t  = (0:round(options.Duration * fs) - 1).' / fs;
env = rampEnvelope(numel(t), round(options.RampDur * fs));

standardFiles = strings(1, numel(options.StandardFreqs));
for k = 1:numel(options.StandardFreqs)
    f = options.StandardFreqs(k);
    fn = fullfile(stdDir, sprintf('std_tone_%04dHz.wav', round(f)));
    if options.Overwrite || ~isfile(fn)
        y = options.Level * env .* sin(2*pi*f*t);
        audiowrite(fn, y, fs);
    end
    standardFiles(k) = fn;
end

deviantFiles = strings(1, numel(options.DeviantFreqs));
for k = 1:numel(options.DeviantFreqs)
    f0 = options.DeviantFreqs(k);
    f1 = 2 * f0;
    fn = fullfile(devDir, sprintf('dev_glide_%04d-%04dHz.wav', round(f0), round(f1)));
    if options.Overwrite || ~isfile(fn)
        % Exponential glide: the phase is the integral of an instantaneous
        % frequency f0*(f1/f0)^(t/T), which rises at a constant rate in
        % octaves -- the way a glide is heard, unlike a linear sweep.
        T = options.Duration;
        k_ = log(f1/f0) / T;
        phase = 2*pi*f0 * (exp(k_*t) - 1) / k_;
        y = options.Level * env .* sin(phase);
        audiowrite(fn, y, fs);
    end
    deviantFiles(k) = fn;
end

vprintf(1, 'Oddball sound banks: %d standards in %s, %d deviants in %s', ...
    numel(standardFiles), stdDir, numel(deviantFiles), devDir)
end


function env = rampEnvelope(n, nRamp)
% Raised-cosine onset and offset, so a sound starts and stops without the
% click a rectangular gate puts at its edges.
env = ones(n, 1);
nRamp = min(nRamp, floor(n/2));
if nRamp < 1, return; end
r = 0.5 * (1 - cos(pi * (0:nRamp-1).' / nRamp));
env(1:nRamp) = r;
env(end-nRamp+1:end) = flipud(r);
end
