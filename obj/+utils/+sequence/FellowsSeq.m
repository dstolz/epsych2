function [S,M,cnt] = FellowsSeq(nSeq)
% S = FellowsSeq([nSeq])
% [S,M,cnt] = FellowsSeq([nSeq])
%
% Generates sequences described in: Fellows, B. CHANCE STIMULUS SEQUENCES FOR
% DISCRIMINATION TASKS, Psychological Bulletin, 1967, Vol. 67, No. 2, 87-92
%
% default nSeq = 100
%
% Use the RNG function before calling to seed for repeatability.
%
% DJS 2020
% [MIGRATED from helpers/FellowsSeq.m to obj/+utils/+sequence/FellowsSeq.m]

if nargin < 1 || isempty(nSeq), nSeq = 100; end

M = uint8([0 1 0 0 1 1 1 0 0 0 1 1;1 0 1 1 0 0 0 1 1 1 0 0;0 0 1 1 1 0 0 0 1 1 0 1;1 1 0 0 0 1 1 1 0 0 1 0;0 1 1 0 0 0 1 1 1 0 0 1;1 0 0 1 1 1 0 0 0 1 1 0;0 0 1 0 0 0 1 1 0 1 1 1;1 1 0 1 1 1 0 0 1 0 0 0;0 0 0 1 0 0 1 1 1 0 1 1;1 1 1 0 1 1 0 0 0 1 0 0;0 1 1 1 0 0 1 0 0 0 1 1;1 0 0 0 1 1 0 1 1 1 0 0;0 1 1 0 0 0 1 0 0 1 1 1;1 0 0 1 1 1 0 1 1 0 0 0;0 0 1 1 1 0 1 1 0 0 0 1;1 1 0 0 0 1 0 0 1 1 1 0;0 0 0 1 1 0 1 1 1 0 0 1;1 1 1 0 0 1 0 0 0 1 1 0;0 0 1 0 1 1 0 0 0 1 1 1;1 1 0 1 0 0 1 1 1 0 0 0;0 0 0 1 1 0 1 0 0 1 1 1;1 1 1 0 0 1 0 1 1 0 0 0;0 0 0 1 1 1 0 0 1 0 1 1;1 1 1 0 0 0 1 1 0 1 0 0]);

n = size(M,1);

cnt = zeros(n,1);

idx = randi(n,1);

S = zeros(1,12*nSeq,'int8');

B = M(:,1:2);

k = 1;
for i = 1:nSeq
    a = M(idx,end-1:end);
    
    if a(1) == a(2)
        idx = all(B~=a,2);
    else
        idx = B(:,1) == a(2) & B(:,2) == a(1) & B(:,1) ~= B(:,2);
    end
    idx = find(idx);
    
    x = find(cnt(idx)==min(cnt(idx)));
    idx = idx(randi(length(x),1));
    
    cnt(idx) = cnt(idx) + 1;
    
    S(k:k+11) = M(idx,:);
    
    k = k + 12;
end