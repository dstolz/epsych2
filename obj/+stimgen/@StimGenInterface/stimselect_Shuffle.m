function idx = stimselect_Shuffle(obj)

% select according to shuffled list

SO = obj.StimPlayObjs;


rep = [SO.Reps];
cnt = [SO.RepsPresented];



if all(cnt == rep) % all stim presented
    idx = -1; 
    return
end

m = min(cnt);

idx = find(cnt == m);



idx = idx(randperm(length(idx),1));

