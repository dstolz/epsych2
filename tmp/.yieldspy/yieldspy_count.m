function n = yieldspy_count(cmd)
% n = yieldspy_count()         calls to pause/drawnow counted so far
% n = yieldspy_count('reset')  zero the count
% n = yieldspy_count('bump')   count one (called by the spies)
%
% Counter behind tmp/.yieldspy/pause.m and drawnow.m, which shadow the
% built-ins while this folder is on the path. A harness adds the folder,
% runs the code under test, and reads how many times that code asked MATLAB
% to process its event queue. See tmp/bench_trial_boundary.m.
persistent count
if isempty(count), count = 0; end
if nargin > 0
    switch cmd
        case 'reset'
            count = 0;
        case 'bump'
            count = count + 1;
    end
end
n = count;
end
