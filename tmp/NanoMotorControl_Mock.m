classdef NanoMotorControl_Mock < peripherals.NanoMotorControl
%NANOMOTORCONTROL_MOCK peripherals.NanoMotorControl with the serial link canned.
%
%   Overrides the transport (transact_) only, so everything above it -- the ERR
%   and BUSY policy in send(), ExpectOk, the Last* properties, and every reply
%   parser -- is the real code. Replies are keyed by the command's first token
%   ("POS?", "MOVEDEG", ...); an unknown one answers like the firmware does.
%
%   Usage
%     r = containers.Map({'POSD?'}, {"POSD -12.345600"});
%     m = NanoMotorControl_Mock(r);
%     deg = m.positionDeg();
%     disp(m.Sent)      % every command the class actually sent
%
%   See also tmp/smoke_test_nanomotor_protocol.m

    properties
        Replies containers.Map           % command token -> reply line
        Sent (:,1) string = strings(0,1) % transcript, in order
    end

    methods
        function obj = NanoMotorControl_Mock(replies)
            arguments
                replies containers.Map = containers.Map()
            end
            obj@peripherals.NanoMotorControl();
            obj.Replies = replies;
        end

        function setReply(obj, key, line)
            obj.Replies(char(key)) = string(line);
        end
    end

    methods (Access=protected)
        function reply = transact_(obj, cmd, timeoutSec, flushBefore) %#ok<INUSD>
            obj.Sent(end+1,1) = cmd;

            key = char(extractBefore(cmd + " ", " "));
            if isKey(obj.Replies, key)
                reply = string(obj.Replies(key));
            else
                reply = "ERR Unknown command. Send HELP.";
            end
        end
    end
end
