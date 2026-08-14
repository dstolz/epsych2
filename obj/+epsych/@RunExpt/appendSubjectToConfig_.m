function appendSubjectToConfig_(self, S, pfn, protocol)
% appendSubjectToConfig_(self, S, pfn, protocol)
% Write one subject and its protocol into the next CONFIG slot.
%
% CONFIG starts life as a single placeholder element with empty fields, so the
% first subject fills slot 1 rather than landing at index 2 behind a blank row.
% Both AddSubject and epsych.SubjectRoster.assignToSession need that rule, and
% it is the one piece of the write that would silently drift if duplicated.
%
% Callers are responsible for validating the subject, the name, and the box
% before calling: this only writes.
%
% Parameters:
%   S        - epsych.Subject to store.
%   pfn      - full path to the protocol file.
%   protocol - the loaded epsych.Protocol.
%
% See also: epsych.RunExpt.AddSubject, epsych.SubjectRoster.assignToSession
arguments
    self
    S (1,1) epsych.Subject
    pfn (1,:) char
    protocol (1,1) epsych.Protocol
end

if isempty(self.CONFIG(1).protocol_fn)
    idx = 1;
else
    idx = numel(self.CONFIG) + 1;
end

self.CONFIG(idx).protocol_fn = pfn;
self.CONFIG(idx).PROTOCOL    = protocol;
self.CONFIG(idx).SUBJECT     = S;
