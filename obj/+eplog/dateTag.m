function s = dateTag(c)
% s = eplog.dateTag(c)
% Format a clock vector as 'ddMMMyyyy', e.g. '09Aug2026'.
%
% This is the date portion of the daily log filename, and it must keep
% matching what EPsych has always written -- RunExpt's "Open Current Error
% Log", the SelfTest window's "Open Log" button and SelfTest check A4 all
% build the same name to find the file.
%
% Digits are placed directly: char(datetime,'ddMMMyyyy') costs ~325 us, this
% costs ~2 us, and it is called on every message to decide whether the log has
% rolled over to a new day.
%
% Parameters:
%   c - clock vector [year month day hour minute seconds]
%
% Returns:
%   s - 9-character row 'ddMMMyyyy'
%
% See also: eplog.stamp, eplog.sink.FileSink

persistent MONTHS
if isempty(MONTHS)
    MONTHS = {'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'};
end

d = c(3);
y = c(1);
m = c(2);
if m < 1 || m > 12, m = 1; end

s = ['00' MONTHS{m} '0000'];

t = floor(d/10);
s(1) = char(48+t);
s(2) = char(48+d-t*10);

s(6) = char(48+floor(y/1000));
s(7) = char(48+mod(floor(y/100),10));
s(8) = char(48+mod(floor(y/10),10));
s(9) = char(48+mod(y,10));
end
