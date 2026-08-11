function smoke_test_epsychinfo_worktree()
% smoke_test_epsychinfo_worktree()
% Exercise EPsychInfo's git metadata from both a main checkout and a linked
% "git worktree": commit checksums, the submodule checksum, the commit
% timestamp, and the worktree name reported in the metadata struct.
%
%   matlab -batch "run('tmp/smoke_test_epsychinfo_worktree.m')"
%
% A worktree's ".git" is a file rather than a folder, so every one of these
% reads goes through a different code path there than in a main checkout.
% A real worktree is required: nothing else reproduces the gitfile.

here = fileparts(mfilename('fullpath'));
run(fullfile(here, '..', 'epsych_startup.m'));

REPO = fileparts(here);
failures = {};

scratch  = fullfile(tempdir,'epsychinfo_smoke');
worktree = fullfile(scratch,'ep_wt');

cleanupScratch_(REPO,scratch,worktree);

% ===== A. main checkout =================================================
try
    E = EPsychInfo;

    assert(strcmpi(E.root,REPO), 'EPsychInfo.root is "%s", expected "%s"', E.root, REPO);
    assert(isempty(E.worktree), ...
        'the main checkout reported worktree "%s"', E.worktree);
    assert(strcmpi(E.chksum,headOf_(REPO)), ...
        'chksum is "%s", expected "%s"', E.chksum, headOf_(REPO));
    assert(strcmpi(E.stimgenChksum,headOf_(fullfile(REPO,'obj','stimgen'))), ...
        'stimgenChksum is "%s", expected "%s"', ...
        E.stimgenChksum, headOf_(fullfile(REPO,'obj','stimgen')));
    assert(datetime(E.commitTimestamp) > datetime(2000,1,1), ...
        'commitTimestamp fell back to its unavailable value');

    m = E.meta;
    assert(isfield(m,'Worktree') && isempty(m.Worktree), ...
        'meta.Worktree should be present and empty for a main checkout');

    fprintf('PASS: A. main checkout metadata (%s)\n', E.chksum(1:7));
catch ME
    failures{end+1} = sprintf('A. main checkout: %s', ME.message);
    fprintf('FAIL: A. %s\n', ME.message);
end

% Matlab reloads a class definition when the path moves to another checkout,
% but only once no instance of it survives.
clear E m

% ===== B. linked worktree ===============================================
try
    mkdir(scratch);
    [st,msg] = system(sprintf('git -C "%s" worktree add --detach "%s" HEAD',REPO,worktree));
    assert(st == 0, 'could not create the worktree: %s', strtrim(msg));
    assert(isfile(fullfile(worktree,'.git')), ...
        'setup: the worktree ".git" should be a file, not a folder');

    % A worktree checks out HEAD, so it would otherwise run whatever was last
    % committed rather than the code under test.
    for c = {fullfile('helpers','@EPsychInfo'), fullfile('obj','+epsych','@RunExpt')}
        copyfile(fullfile(REPO,c{1}),fullfile(worktree,c{1}));
    end

    epsych_startup(worktree,false);

    E = EPsychInfo;

    assert(strcmpi(E.root,worktree), ...
        'EPsychInfo.root is "%s", expected "%s"', E.root, worktree);
    % git names the administrative folder after the checkout, appending a
    % digit when that name is already registered.
    assert(strncmp(E.worktree,'ep_wt',5), ...
        'the worktree name is "%s", expected it to start with "ep_wt"', E.worktree);
    assert(strcmpi(E.chksum,headOf_(worktree)), ...
        'chksum is "%s", expected "%s"', E.chksum, headOf_(worktree));
    assert(datetime(E.commitTimestamp) > datetime(2000,1,1), ...
        'commitTimestamp fell back to its unavailable value');

    m = E.meta;
    assert(strcmp(m.Worktree,E.worktree), ...
        'meta.Worktree is "%s", expected "%s"', m.Worktree, E.worktree);

    % "git worktree add" does not populate submodules, so the missing
    % submodule has to read as unavailable rather than throw.
    assert(isnan(E.stimgenChksum), ...
        'an uninitialized submodule reported checksum "%s"', num2str(E.stimgenChksum));

    fprintf('PASS: B. worktree metadata (%s @ %s)\n', E.worktree, E.chksum(1:7));
catch ME
    failures{end+1} = sprintf('B. worktree: %s', ME.message);
    fprintf('FAIL: B. %s\n', ME.message);
end

% ===== C. the worktree reaches the RunExpt title ========================
rx = [];
try
    E = EPsychInfo;
    expected = sprintf('[%s]',E.worktree);

    rx = epsych.RunExpt;
    fig = findall(groot,'Type','figure','-and','Tag','RunExpt');
    assert(~isempty(fig), 'the RunExpt figure was not created');

    assert(contains(fig(1).Name,expected), ...
        'the title is "%s", expected it to contain "%s"', fig(1).Name, expected);

    fprintf('PASS: C. RunExpt title is "%s"\n', fig(1).Name);
catch ME
    failures{end+1} = sprintf('C. RunExpt title: %s', ME.message);
    fprintf('FAIL: C. %s\n', ME.message);
end

% ===== D. the Version Info dialog names the worktree =====================
try
    assert(~isempty(rx), 'no RunExpt instance to open the dialog from');
    rx.version_info;

    dlg = findall(groot,'Type','figure','-and','Tag','RunExptVersionInfo');
    assert(~isempty(dlg), 'the version info dialog was not created');

    labels = findall(dlg(1),'Type','uilabel');
    texts  = arrayfun(@(h) string(h.Text), labels);
    idx    = find(texts == "Worktree:");
    assert(~isempty(idx), 'the dialog has no Worktree row');

    % The row's value shares a grid row with its label.
    row   = labels(idx(1)).Layout.Row;
    value = labels(arrayfun(@(h) h.Layout.Row == row && h.Layout.Column == 2, labels));
    assert(~isempty(value), 'the Worktree row has no value');
    assert(strcmp(char(value(1).Text),EPsychInfo().worktree), ...
        'the dialog shows worktree "%s", expected "%s"', ...
        value(1).Text, EPsychInfo().worktree);

    fprintf('PASS: D. version info dialog shows worktree "%s"\n', value(1).Text);
catch ME
    failures{end+1} = sprintf('D. version info dialog: %s', ME.message);
    fprintf('FAIL: D. %s\n', ME.message);
end
delete(findall(groot,'Type','figure'));
clear rx

% ===== restore the original checkout ====================================
run(fullfile(REPO,'epsych_startup.m'));
cleanupScratch_(REPO,scratch,worktree);

fprintf('\n');
if isempty(failures)
    fprintf('ALL PASSED\n');
else
    fprintf('%d FAILURE(S):\n', numel(failures));
    fprintf('  %s\n', failures{:});
end


function h = headOf_(checkout)
[st,out] = system(sprintf('git -C "%s" rev-parse HEAD',checkout));
assert(st == 0, 'git rev-parse failed in "%s"', checkout);
h = strtrim(out);


function cleanupScratch_(repo,scratch,worktree)
% git owns the administrative files under .git/worktrees as well as the
% checkout itself, so let it take the worktree down before clearing scratch.
if isfolder(worktree)
    system(sprintf('git -C "%s" worktree remove --force "%s"',repo,worktree));
end
system(sprintf('git -C "%s" worktree prune',repo));
if isfolder(scratch) && ~isfolder(worktree)
    rmdir(scratch,'s');
end
