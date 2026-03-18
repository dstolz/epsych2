function post_stimdelay_update(objStimDelay,StimDelayValue,pStimDur,pRespWinDelay,pRespWinDur,pRespWinPreStim,pRespWinPostStim)
% post_stimdelay_update(objStimDelay,StimDelayValue,pStimDur,pRespWinDelay,...
%     pRespWinDur,pRespWinPreStim,pRespWinPostStim)
%
% Update response-window timing after Stimulus Delay changes.
% This keeps the response window aligned to stimulus timing.
%
% Definitions:
% - StimDelay: time from trial start to stimulus onset.
% - StimDur: stimulus duration.
% - RespWinDelay: time from stimulus onset to response-window onset.
% - RespWinDur: response-window duration.
% - pRespWinPreStim: response-window portion before stimulus onset.
% - pRespWinPostStim: response-window portion after stimulus end.
%
% Inputs:
%   objStimDelay     Parameter object for Stimulus Delay (updated).
%   StimDelayValue   New Stimulus Delay value.
%   pStimDur         Parameter object for Stimulus Duration.
%   pRespWinDelay    Parameter object for Response Window Delay.
%   pRespWinDur      Parameter object for Response Window Duration.
%   pRespWinPreStim  Parameter object for pre-stimulus response-window time.
%   pRespWinPostStim Parameter object for post-stimulus response-window time.




preStim  = pRespWinPreStim.Value;
postStim = pRespWinPostStim.Value;

rwDelay = StimDelayValue + pStimDur.Value - preStim;
rwDur   = preStim + postStim; 


pRespWinDelay.Value = rwDelay;
pRespWinDur.Value = rwDur;