function create_arbmag(obj,varargin)

% create arbitrary magnitude filter based on tone  calibration LUT
vprintf(1,'Creating filter')


freqs = obj.CalibrationData.tone(:,1);
v     = obj.CalibrationData.tone(:,end);

if isempty(varargin)
    Fs = double(obj.Fs);
    arbFilt = designfilt( ...
        'arbmagfir', ...
        'FilterOrder',length(freqs), ...
        'Frequencies',[0; freqs; Fs/2], ...
        'Amplitudes',[0; v; 0], ...
        'SampleRate',Fs);
else
    arbFilt = designfilt( ...
        'arbmagfir', ...
        varargin{:});
end

obj.CalibrationData.filter = arbFilt;
obj.CalibrationData.filterGrpDelay = round(mean(grpdelay(arbFilt)));

assignin('base','arbFilt',arbFilt);
fprintf('<a href="matlab:fvtool(arbFilt)">View filter</a>\n')
