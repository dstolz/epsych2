function c = Viemeister(depth)
% c = Viemeister(depth)
%
% Viemeister contrast normalization function.
%
% [MIGRATED from helpers/Viemeister.m to obj/+utils/Viemeister.m]

c = (1+(depth.^2./2)).^(-0.5);