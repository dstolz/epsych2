%% quick recalc info

rc = [Data.ResponseCode];

urc = unique(rc);

iStim = rc < 2000;
iHits = rc == 1313;
iMiss = rc == 1602;
iFA = rc == 2312;
iCR = rc == 2564;

FAR = sum(iFA) ./ sum(~iStim) * 100;

HR = sum(iHits) ./ sum(iStim);
dp = norminv(max(min(HR,0.95),0.05)) - norminv(max(min(FAR,0.95),0.05));

fprintf('\n# Stim\td''\tFAR\n%d\t%.4f\t%.2f\n',sum(iStim),dp,FAR)