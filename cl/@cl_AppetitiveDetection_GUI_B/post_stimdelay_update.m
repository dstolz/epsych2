function post_stimdelay_update(objStimDelay,StimDelayValue,pStimDur,pRespWinDelay,pRespWinDur,pRespWinPostStim)
% post_stimdelay_update(objStimDelay,StimDelayValue,pRespWinDelay,pRespWinDur)
%
% StimDelay is defined as the time from trial start to stimulus onset. 
% StimDur is defined as the duration of the stimulus.
% RespWinDelay is defined as the time from stimulus onset to response window onset.
% RespWinDur is defined as the duration of the response window.
% pRespWinPostStim is defined as the portion of the response window that occurs after the end of the stimulus (i.e. the "post-stimulus" portion of the response window).
% To maintain the same temporal relationship between stimulus and response window when StimDelay changes, we need to adjust RespWinDelay and RespWinDur accordingly.
%
% Parameters:
%   objStimDelay - The Parameter object for Stimulus Delay that was just updated.
%   StimDelayValue - The new value of the Stimulus Delay parameter.
%   pStimDur - The Parameter object for Stimulus Duration.
%   pRespWinDelay - The Parameter object for Response Window Delay.
%   pRespWinDur - The Parameter object for Response Window Duration.
%   pRespWinPostStim - The Parameter object for the post-stimulus portion of the Response Window.
%
%
% adjust the Response Window Delay and Duration based on the new Stimulus Delay value, to maintain the same temporal relationship between stimulus and response window
% this is necessary because the response window is defined relative to the onset of the stimulus.


rwPost = pRespWinPostStim.Value;
rwDur = rwPost + rwDelay;
RWDuration = rwDur + rwPost;
% RWDelay = StimDelay 