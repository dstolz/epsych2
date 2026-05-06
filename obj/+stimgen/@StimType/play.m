function play(obj)
% play(obj)
% Audition the current Signal through the default audio device.
% Signal is normalized to unit peak before playback.

fsValue = double(obj.get_selected_property_value_("Fs"));
ap = audioplayer(obj.Signal./max(abs(obj.Signal)), fsValue);
playblocking(ap);
delete(ap);
