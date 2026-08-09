function s = stamp(c)
% s = eplog.stamp(c)
% Format a clock vector as 'HH:mm:ss.SSS'.
%
% Built by placing digits directly rather than calling a formatter, because
% this runs once per emitted message and the alternatives are expensive out of
% all proportion to the job:
%
%   datestr(now,'HH:MM:SS.FFF')   ~290 us   (what vprintf used to do)
%   char(datetime,'HH:mm:ss.SSS') ~275 us
%   sprintf('%02d:%02d:%06.3f')    ~11 us
%   this                            ~1 us
%
% At the 100 Hz PsychTimer period that RunExpt defaults to, with several trace
% messages per trial, that difference is the difference between logging being
% free and logging being something to think about.
%
% Parameters:
%   c - clock vector [year month day hour minute seconds]
%
% Returns:
%   s - 12-character row 'HH:mm:ss.SSS'
%
% See also: eplog.dateTag, eplog.Logger

ms = round(c(6)*1000);
if ms > 59999, ms = 59999; end      % a rounded-up 59.9996 s must not read '60'
if ms < 0, ms = 0; end

ss = floor(ms/1000);
ms = ms - ss*1000;
hh = c(4);
mi = c(5);

s = '00:00:00.000';

t = floor(hh/10);  s(1)  = char(48+t);  s(2)  = char(48+hh-t*10);
t = floor(mi/10);  s(4)  = char(48+t);  s(5)  = char(48+mi-t*10);
t = floor(ss/10);  s(7)  = char(48+t);  s(8)  = char(48+ss-t*10);

h = floor(ms/100);
d = floor((ms-h*100)/10);
s(10) = char(48+h);
s(11) = char(48+d);
s(12) = char(48+ms-h*100-d*10);
end
