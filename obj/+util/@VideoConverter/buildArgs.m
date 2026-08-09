function args = buildArgs(src, dst, opts, extra)
% args = util.VideoConverter.buildArgs(src, dst, opts)
% args = util.VideoConverter.buildArgs(src, dst, opts, Name=Value,...)
% Compose the ffmpeg command-line argument string for converting src to
% dst under an ffmpegtranscode-style option struct opts (field names match
% util.VideoConverter's public vocabulary properties).
%
% Pure function: no I/O, no process launch -- directly unit-testable.
% Flag order is significant: global options, then input options, then
% "-i INFILE", then output options, then OUTFILE.
%
% Name-value options:
%   ProgressFile     (default "") -- when set, adds -progress/-stats_period
%   SourceFrameRate  (default NaN) -- fps used only when Units="frames"
arguments
    src (1,1) string
    dst (1,1) string
    opts (1,1) struct
    extra.ProgressFile (1,1) string = ""
    extra.SourceFrameRate (1,1) double = NaN
end

if ~isempty(opts.VideoCrop) && numel(opts.VideoCrop) ~= 4
    error('util:VideoConverter:InvalidVideoCrop', 'VideoCrop must be a 4-element [left top right bottom] vector.');
end
if ~isempty(opts.InputFrameSize) && numel(opts.InputFrameSize) ~= 2
    error('util:VideoConverter:InvalidInputFrameSize', 'InputFrameSize must be a 2-element [width height] vector.');
end
if ~isempty(opts.Range) && numel(opts.Range) > 2
    error('util:VideoConverter:InvalidRange', 'Range must be a scalar or 2-element vector.');
end

g = string.empty(1,0);   % global
i = string.empty(1,0);   % input
o = string.empty(1,0);   % output

% ---------- global ----------
% -y : dst is our own .part sidecar, which the caller already ensured
%      does not exist; overwrite policy is enforced by the caller, not
%      ffmpeg. Omitting -y/-n makes ffmpeg PROMPT on stdin, which with
%      -nostdin is an immediate hard failure.
g = [g, "-hide_banner", "-loglevel", "error", "-nostats", "-nostdin", "-y"];
if extra.ProgressFile ~= ""
    g = [g, "-progress", quoteArg(extra.ProgressFile), "-stats_period", "0.5"];
end

% ---------- range: exactly ONE side gets -ss (never both) ----------
[ss, dur] = rangeToSeconds(opts, extra.SourceFrameRate);
if ~isempty(ss)
    i = [i, "-ss", sprintf("%.6f", ss)];
    if strcmpi(opts.FastSearch, "on")
        i = [i, "-noaccurate_seek"];
    end
end
if ~isempty(dur) && isfinite(dur)
    o = [o, "-t", sprintf("%.6f", dur)];
end

% ---------- other input options ----------
if ~isempty(opts.InputFrameRate)
    i = [i, "-r", ratioStr(opts.InputFrameRate)];
end
if opts.InputPixelFormat ~= ""
    i = [i, "-pix_fmt", opts.InputPixelFormat];
end
if ~isempty(opts.InputFrameSize)
    i = [i, "-s", sprintf("%dx%d", opts.InputFrameSize(1), opts.InputFrameSize(2))];
end

i = [i, "-i", quoteArg(src)];

% ---------- video ----------
switch opts.VideoCodec
    case "none"
        o = [o, "-vn"];
    case "copy"
        o = [o, "-c:v", "copy"];
    case "raw"
        o = [o, "-c:v", "rawvideo"];
        o = [o, "-pix_fmt", defaultTo(opts.PixelFormat, "bgr24")];
    case "mpeg4"
        o = [o, "-c:v", "mpeg4"];
        o = [o, "-q:v", string(opts.Mpeg4Quality)];
        o = [o, "-pix_fmt", defaultTo(opts.PixelFormat, "yuv420p")];
    case "x264"
        o = [o, "-c:v", "libx264"];
        o = [o, "-crf", string(opts.x264Crf)];
        if opts.x264Preset ~= ""
            o = [o, "-preset", opts.x264Preset];
        end
        if opts.x264Tune ~= ""
            o = [o, "-tune", opts.x264Tune];
        end
        o = [o, "-pix_fmt", defaultTo(opts.PixelFormat, "yuv420p")];
    otherwise
        error('util:VideoConverter:UnsupportedVideoCodec', 'VideoCodec "%s" is not supported.', opts.VideoCodec);
end
if ~isempty(opts.OutputFrameRate)
    o = [o, "-r:v", ratioStr(opts.OutputFrameRate)];
end

% ---------- audio ----------
switch opts.AudioCodec
    case "none"
        o = [o, "-an"];
    case "copy"
        o = [o, "-c:a", "copy"];
    case "wav"
        o = [o, "-c:a", "pcm_s16le"];
    case "mp3"
        o = [o, "-c:a", "libmp3lame"];
        if ~isempty(opts.Mp3Quality)
            o = [o, "-q:a", string(opts.Mp3Quality)];
        end
    case "aac"
        o = [o, "-c:a", "aac"];   % no "-strict -2": obsolete since ffmpeg 2015
        if ~isempty(opts.AacBitRate)
            o = [o, "-b:a", string(opts.AacBitRate)];
        end
end
if ~isempty(opts.AudioSampleRate)
    o = [o, "-ar:a", string(opts.AudioSampleRate)];
end

% ---------- filters: crop -> pad -> scale -> flip ----------
vf = buildFilterChain(opts);
if vf ~= ""
    if strcmp(opts.VideoCodec, "copy")
        error('util:VideoConverter:FilterWithCopy', ...
            'VideoCrop/VideoScale/VideoFlip require re-encoding; VideoCodec="copy" cannot be filtered.');
    end
    o = [o, "-vf", quoteArg(vf)];
end

if ~isempty(opts.ExtraArgs)
    o = [o, string(opts.ExtraArgs)];
end

args = strjoin([g, i, o, quoteArg(dst)], " ");
end

% =========================================================================

function [ss, dur] = rangeToSeconds(opts, srcFps)
% Scalar Range = total duration from the start (no -ss). 2-element Range =
% [start end] (ss = start, duration = end-start). Units="frames"/"samples"
% convert using srcFps/AudioSampleRate, degrading to a fixed assumed rate
% (with no I/O -- this function is pure) when neither is known.
ss = [];
dur = [];
if isempty(opts.Range)
    return
end
r = double(opts.Range);
switch opts.Units
    case "frames"
        fps = srcFps;
        if isempty(fps) || isnan(fps) || fps <= 0
            fps = 30;
        end
        r = r / fps;
    case "samples"
        sr = opts.AudioSampleRate;
        if isempty(sr) || isnan(sr) || sr <= 0
            sr = 44100;
        end
        r = r / sr;
end
if isscalar(r)
    dur = r;
else
    ss = r(1);
    dur = r(2) - r(1);
end
end

function s = ratioStr(v)
if isscalar(v)
    s = sprintf("%g", v);
else
    s = sprintf("%g/%g", v(1), v(2));
end
end

function v = defaultTo(val, dflt)
if val == ""
    v = dflt;
else
    v = val;
end
end

function vf = buildFilterChain(opts)
% Every scale/crop dimension is truncated to even: yuv420p (the default
% pix_fmt for x264/mpeg4) hard-errors "width not divisible by 2" on any
% odd output dimension, which a naive scale factor produces routinely.
f = string.empty(1,0);
if ~isempty(opts.VideoCrop)
    c = round(opts.VideoCrop);   % [left top right bottom]; negative = pad
    p = max(c, 0);
    n = max(-c, 0);
    if any(p > 0)
        f = [f, sprintf("crop=w=iw-%d:h=ih-%d:x=%d:y=%d", p(1)+p(3), p(2)+p(4), p(1), p(2))];
    end
    if any(n > 0)
        f = [f, sprintf("pad=w=iw+%d:h=ih+%d:x=%d:y=%d:color=%s", n(1)+n(3), n(2)+n(4), n(1), n(2), opts.VideoFillColor)];
    end
end
if ~isempty(opts.VideoScale)
    if isscalar(opts.VideoScale)
        num = opts.VideoScale; den = 1;
    else
        num = opts.VideoScale(1); den = opts.VideoScale(2);
    end
    f = [f, sprintf("scale=w=trunc(iw*%g/%g/2)*2:h=trunc(ih*%g/%g/2)*2", num, den, num, den)];
end
switch opts.VideoFlip
    case "horizontal"
        f = [f, "hflip"];
    case "vertical"
        f = [f, "vflip"];
    case "both"
        f = [f, "hflip", "vflip"];
end
vf = strjoin(f, ",");
end

function s = quoteArg(v)
% ProcessStartInfo.Arguments is one string re-parsed by the child via
% CommandLineToArgvW. Windows filenames cannot contain '"', so wrapping in
% '"..."' is always safe to add and is skipped only when clearly unneeded.
v = string(v);
if v == "" || any(contains(v, [" ","&","(",")","^","%","!",";",","]))
    s = """" + v + """";
else
    s = v;
end
end
