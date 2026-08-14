function n = versionNumber(versionString)
    % n = epsych.Protocol.versionNumber(versionString)
    %
    % The comparable part of a 'vN.YYMMDD' protocol version: the integer N,
    % which save() increments on every write.
    %
    % The date half is not comparable — two protocols saved on the same day
    % differ only in N — so ordering is by N alone. An unparseable or absent
    % version returns NaN, which compares false against everything: an unknown
    % version is never reported as outdated.
    %
    % Parameters:
    %   versionString - 'vN.YYMMDD', or anything else
    %
    % Returns:
    %   n - the leading integer, or NaN
    %
    % See also: epsych.Protocol.versionOnDisk, epsych.Protocol.save

    arguments
        versionString = ''
    end

    n = NaN;
    if isempty(versionString), return, end

    tok = regexp(char(string(versionString)), '^v(\d+)\.', 'tokens', 'once');
    if ~isempty(tok)
        n = str2double(tok{1});
    end
end
