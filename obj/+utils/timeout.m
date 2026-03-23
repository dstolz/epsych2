function done = timeout(numSeconds)
% done = timeout([numSeconds])
% 
% Helper function to implement a timeout in what might be an infinite loop.
%
% Note that the timeout is not exact and is dependent on how long it takes
% to run the code within the loop or other process.
%
% ex:
%       myCondition = false;
%       timeout(10); % initialize to 10 seconds
%       while ~timeout
%           % whatever code you want goes here
%           if myCondition == true
%               break;
%           end
%           pause(0.001); % be nice to the computer
%       end
%       if timeout, disp('Loop timed out!'); end
%
% Daniel.Stolzberg@gmail.com 2019
% [MIGRATED from helpers/timeout.m to obj/+utils/timeout.m]


persistent t finishTime

if nargin == 1
    t = tic;
    finishTime = numSeconds;
end

done = toc(t) >= finishTime;