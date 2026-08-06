function onOpenTeensyDesigner(obj)
% onOpenTeensyDesigner(obj)
% Open the Teensy Trial Designer against this protocol's Teensy interface.
%
% Passing the interface through is what lets the designer upload a compiled
% program and drive live I/O for wiring checks; without one it still opens,
% just offline. A protocol with no Teensy interface is reported through the
% status bar rather than as an error, because opening the designer to build a
% paradigm before adding the interface is a perfectly reasonable order to
% work in.
%
% See also: teensy.TrialDesigner, hw.Teensy,
%   documentation/teensy/teensy_TrialDesigner_UserGuide.md

    iface = [];
    for i = 1:numel(obj.Protocol.Interfaces)
        if isa(obj.Protocol.Interfaces(i), 'hw.Teensy')
            iface = obj.Protocol.Interfaces(i);
            break
        end
    end

    try
        if isempty(iface)
            teensy.TrialDesigner();
            obj.setStatus('Opened the Teensy Trial Designer with no board bound.', ...
                'Add a Teensy interface here to enable Upload and Insert Into Protocol.');
        else
            teensy.TrialDesigner(Interface = iface);
            obj.setStatus('Opened the Teensy Trial Designer on this protocol''s Teensy interface.', ...
                'Design the paradigm, then use Insert Into Protocol to add its parameters.');
        end
    catch ME
        vprintf(0, 1, ME);
        uialert(obj.Figure, ...
            sprintf('The Teensy Trial Designer could not be opened:\n\n%s', ME.message), ...
            'Protocol Designer', 'Icon', 'error');
        obj.setStatus(sprintf('Could not open the Teensy Trial Designer: %s', ME.message));
    end
end
