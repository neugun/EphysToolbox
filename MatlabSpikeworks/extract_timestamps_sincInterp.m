function extract_timestamps_sincInterp( hsdFile, targetDir, wireList, thresholds, varargin )
%
% usage: extract_timestamps( hsdFile, wireList, thresholds, varargin )
%
% INPUTS:
%   hsdFile - string containing the name of the .hsd file (include the full
%       path)
%   targetDir - directory in which to save the .nex file
%   wireList - vector containing the list of wires for this
%       tetrode/stereotrode
%   thresholds - vector containing the thresholds for each wire in wireList
%
% VARARGs:
%   datatype - data type in binary file (ie, 'int16')
%   maxlevel - maximum level for the wavelet filter (default 5 + the
%       upsampling ratio)
%   wavelength - duration of waveforms in samples
%   peakloc - location of peaks within waveforms in samples
%   deadtime - dead time required before detecting another spike, in
%       samples
%   upsample - boolean indicating whether or not to upsample the signal
%   sinclength - length of the sinc function to use for upsampling
%   upsampleratio - ratio by which to upsample the signal (ie, a value of 2
%       would take Fs from, for example, 30 kHz to 60 kHz)

deadTime   = 16;     % dead time after a spike within which another spike
                     % cannot be detected on the same wire (in samples)
peakLoc    = 8;      % number of samples to look backwards from a peak (ie,
                     % peaks should be aligned peakLoc samples into each
                     % waveform
waveLength = 24;     % duration of each waveform in number of samples
upsample   = true;   % whether to perform sinc interpolation to upsample
                     % the waveforms
sincLength = 13;     % length of sinc function for sinc interpolation
r_upsample = 2;      % upsampling ratio - ie, if original Fs = 31250 and
                     % r_upsample = 2, the sampling rate for each waveform
                     % will be 62500 Hz.
maxLevel   = 0;      % max level for wavelet filtering

% note that deadTime, peakLoc, waveLength, and sincLength are in units of
% number of samples for the ORIGINAL signal. That is, if the signal is
% upsampled by a factor of 2, the deadTime, etc. written to the .nex file
% will be 2 * the deadTime supplied above (or as a varargin).

dataType = 'int16';

for iarg = 1 : 2 : nargin - 4
    switch lower(varargin{iarg})
        case 'datatype',
            dataType = varargin{iarg + 1};
        case 'maxlevel',
            maxLevel = varargin{iarg + 1};
        case 'wavelength',
            waveLength = varargin{iarg + 1};
        case 'peakloc',
            peakLoc = varargin{iarg + 1};
        case 'deadtime',
            deadTime = varargin{iarg + 1};
        case 'upsample',
            upsample = varargin{iarg + 1};
        case 'sinclength',
            sincLength = varargin{iarg + 1};
        case 'upsampleratio',
            r_upsample = varargin{iarg + 1};
    end
end

r_upsample = round(r_upsample);
if ~upsample
    r_upsample = 1;   % for later on to make sure timestamps in the .nex file are interpreted correctly
end

if maxLevel == 0
    maxLevel = r_upsample + 5;      % cutoff frequency = samplingrate/(2^(maxlevel+1))
                                    % this should make the cutoff frequency
                                    % ~230 Hz for an initial sampling rate
                                    % of ~30 kHz. For an initial sampling
                                    % rate of 20 kHz, the cutoff will be
                                    % ~150 Hz. May want to use r_upsample +
                                    % 4 if Fs = 20 kHz (cutoff ~300 Hz)
end

bytes_per_sample = getBytesPerSample( dataType );
switch dataType
    case 'int16',
        ADprecision = 16;   % bits
end
ADrange = [-10 10];

hsdInfo    = dir(hsdFile);
hsdHeader  = getHSDHeader( hsdFile );
Fs         = hsdHeader.main.sampling_rate;
dataOffset = hsdHeader.dataOffset;
numWires   = hsdHeader.main.num_channels;
datalength = (hsdInfo.bytes - dataOffset) / (bytes_per_sample * numWires);

blockSize   = round(Fs * 10);    % process 10 sec at a time
overlapSize = round(Fs * 0.1);   % 100 ms overlap between adjacent blocks 
                                 % to avoid edge effects
final_Fs         = r_upsample * Fs;
final_peakLoc    = r_upsample * peakLoc;
final_waveLength = r_upsample * waveLength;

% make sure wireList and thresholds are column vectors
if size(wireList, 1) < size(wireList, 2); wireList = wireList'; end
if size(thresholds, 1) < size(thresholds, 2); thresholds = thresholds'; end

goodWires = zeros(length(wireList), 1);
for iWire = 1 : length(wireList)
    goodWires(iWire) = hsdHeader.channel(wireList(iWire)).good;
end
% is it more efficient to read single wires in sequence, or read in a big
% chunk of data including all wires, then pull out the one to four wires of
% interest? I think the latter... - DL 3/27/2012

numBlocks = ceil(datalength / blockSize);
numBlocks = 3;                          % just for debugging
datalength = round(blockSize * (numBlocks - 0.5));    % just for debugging
% first, pull out the timestamps.
all_ts    = [];
for iBlock = 1 : numBlocks

    disp(['Finding timestamps for block ' num2str(iBlock) ' of ' num2str(numBlocks)]);
    
    rawData_curSamp   = (iBlock - 1) * blockSize;
    upsampled_curSamp = rawData_curSamp * r_upsample;
    
    % get overlapSize samples on either side of each block to prevent edge
    % effects (may not be that important, but it's easy to do)
    startSample = max(1, rawData_curSamp - overlapSize);
    if iBlock == 1
        numSamples  = blockSize + overlapSize;
    elseif iBlock == numBlocks
        numSamples = datalength - startSample + 1;
    else
        numSamples = blockSize + 2 * overlapSize;
    end
    
    rawData = readHSD(hsdFile, numWires, dataOffset, Fs, [], ...
        'usesamplelimits', [startSample, numSamples]);
    
    rawData = rawData(wireList, :);
    if upsample
        interp_rawData = zeros(size(rawData, 1), size(rawData, 2) * r_upsample);
        for iWire = 1 : size(rawData, 1)
            cutoff_Fs = hsdHeader.channel(wireList(iWire)).high_cut;
            interp_rawData(iWire, :) = sincInterp(rawData(iWire, :), Fs, ...
                cutoff_Fs, final_Fs, 'sinclength', sincLength);
        end
        fdata = wavefilter(interp_rawData, goodWires, maxLevel);
    else
        % wavelet filter the raw data
        % Don't bother to do the calculations for noisy wires.
        fdata = wavefilter(rawData, goodWires, maxLevel);
    end
    
    % calculate the smoothed nonlinear energy of the wavelet filtered data.
    % Don't bother to do the calculations for noisy wires.
    SNLEdata = snle( fdata, goodWires, 'windowsize', 12 );   % 12 is Alex's default window size
    
    % extract the timestamps of peaks in the smoothed non-linear energy
    % signal that are above threshold. Exclude wires with noisy recordings
    % from timestamp extraction.
    ts = gettimestampsSNLE(SNLEdata, thresholds, goodWires, 'deadtime', deadTime * r_upsample);
    
    % make sure peaks above threshold are not contained in the overlap
    % regions for adjacent blocks of data (and also that the first peak
    % location has enough data before it to extract a full waveform, and
    % the last spike has enough data after it to extract the full
    % waveform).
    switch iBlock
        case 1,
            ts = ts(ts > final_peakLoc & ts <= blockSize * r_upsample);
        case numBlocks,
            ts = ts((ts >= overlapSize * r_upsample + 2) & ...
                 (ts < (size(SNLEdata,2) - (final_waveLength - final_peakLoc)))) - ...
                 (overlapSize * r_upsample + 1);
        otherwise,
            ts = ts((ts >= overlapSize * r_upsample + 2) & ...
                 (ts <= overlapSize * r_upsample + 1 + blockSize * r_upsample)) - ...
                 (overlapSize * r_upsample + 1);
    end
    % NOTE: ts is timestamps in samples, not in real time. Divide by the
    % sampling rate to get real time
    
%     if isempty(waveforms)
%         waveforms = extractWaveforms(fdata, ts, peakLoc, waveLength);
%     else
%         waveforms = [waveforms, extractWaveforms(fdata, ts, peakLoc, waveLength)];
%     end
    
    ts = ts + upsampled_curSamp;
    all_ts = [all_ts, ts];
    
end
all_ts = all_ts';   % all_ts should be a column vector for the routines that write to .nex files



% final_ts = all_ts * r_upsample;   % make sure to account for change in
                                  % recorded sampling rate in writing
                                  % the timestamps to disk, but use the
                                  % original sampling rate (and associated
                                  % timestamps) to pull out the waveforms.
                                  
% write the timestamps into a .nex file
plxInfo.comment    = hsdHeader.comment;
plxInfo.ADFs       = final_Fs;
plxInfo.numWires   = length(wireList);
plxInfo.numEvents  = 0;
plxInfo.numSlows   = 0;
plxInfo.waveLength = final_waveLength;
plxInfo.peakLoc    = final_peakLoc;

dateVector = datevec(hsdHeader.date, 'yyyy-mm-dd');
plxInfo.year       = dateVector(1);
plxInfo.month      = dateVector(2);
plxInfo.day        = dateVector(3);

timeVector = datevec(hsdHeader.time, 'HH:MM');
plxInfo.hour       = timeVector(1);
plxInfo.minute     = timeVector(2);
plxInfo.second     = 0;
plxInfo.waveFs     = final_Fs;
plxInfo.dataLength = datalength * r_upsample;



% nexStruct = nexCreateFileData( final_Fs );
PLX_fn    = createPLXName( hsdFile, targetDir, wireList );

% for iWire = 1 : length(wireList)
%     nexStruct.waves{iWire, 1}.name        = sprintf('w%02d', iWire);
%     nexStruct.waves{iWire, 1}.NPointsWave = final_waveLength;
%     nexStruct.waves{iWire, 1}.WFrequency  = final_Fs;
%     nexStruct.waves{iWire, 1}.timestamps  = all_ts / Fs;   % use original sampling rate to calculate timestamps
%     nexStruct.waves{iWire, 1}.waveforms   = zeros(final_waveLength, 1);
%     nexStruct.waves{iWire, 1}.ADtoMV      = (range(ADrange) / 2 ^ ADprecision * 1000) / ...
%                                             hsdHeader.channel(wireList(iWire)).gain;
%     nexStruct.waves{iWire, 1}.wireNumber  = wireList(iWire);
% end

writePLXheader( PLX_fn, plxInfo );
for iWire = 1 : length(wireList)
    writeNex_wf_ts( nex_fn, iWire, all_ts );
end

% now, pull out the waveforms corresponding to the timestamps
numSamplesWritten = 0;
ts_originalSignal = round(all_ts / r_upsample);
for iBlock = 1 : numBlocks
    
    disp(['extracting waveforms for block ' num2str(iBlock) ' of ' num2str(numBlocks)]);
    
    rawData_curSamp   = (iBlock - 1) * blockSize;
    upsampled_curSamp = rawData_curSamp * r_upsample;
    startSample = max(1, rawData_curSamp - overlapSize);
    if iBlock == 1
        numSamples  = blockSize + overlapSize;
    elseif iBlock == numBlocks
        numSamples = datalength - startSample + 1;
    else
        numSamples = blockSize + 2 * overlapSize;
    end
    
    rawData = readHSD(hsdFile, numWires, dataOffset, Fs, [], ...
        'usesamplelimits', [startSample, numSamples]);
    rawData = rawData(wireList, :);

    if upsample
        interp_rawData = zeros(size(rawData, 1), size(rawData, 2) * r_upsample);
        for iWire = 1 : size(rawData, 1)
            cutoff_Fs = hsdHeader.channel(wireList(iWire)).high_cut;
            interp_rawData(iWire, :) = sincInterp(rawData(iWire, :), Fs, ...
                cutoff_Fs, final_Fs, 'sinclength', sincLength);
        end
        fdata = wavefilter(interp_rawData, goodWires, maxLevel);
    else
        % wavelet filter the raw data
        % Don't bother to do the calculations for noisy wires.
        fdata = wavefilter(rawData, goodWires, maxLevel);
    end
    
    ts = all_ts(all_ts > upsampled_curSamp & all_ts <= upsampled_curSamp + blockSize * r_upsample);
    if iBlock > 1
        ts = ts - upsampled_curSamp + overlapSize * r_upsample;
    end
    waveforms = extractWaveforms(fdata, ts, final_peakLoc, final_waveLength);
    %   waveforms - m x n x p matrix, where m is the number of timestamps
    %   (spikes), n is the number of points in a single waveform, and p is
    %   the number of wires

%     ts = ts_originalSignal(ts_originalSignal > rawData_curSamp & ts_originalSignal <= rawData_curSamp + blockSize);
%     if iBlock > 1
%         ts = ts - rawData_curSamp + overlapSize;
%     end
    
    % perform sinc interpolation, but only around the timestamps so that we
    % don't use up memory upsampling the entire signal
%     if upsample
%         % extract a buffer zone around the waveforms for the sinc
%         % interpolation and the wavelet filtering
%         upsample_Fs     = r_upsample * Fs;
%         buffered_peak   = peakLoc + sincLength;
%         buffered_length = waveLength + 2 * sincLength;
%         
%         raw_waveforms = extractWaveforms(rawData, ts, buffered_peak, buffered_length);
%         
%         cutoff_Fs = hsdHeader.channel(wireList(1)).high_cut;   % assumes the filter settings for each wire are the same
%         [interp_wv, ~] = interpWaveforms( raw_waveforms, sincLength, Fs, cutoff_Fs, upsample_Fs);
%         
%         % now wavelet filter each waveform
%         filt_wv = wv_filt_waveforms( interp_wv, maxLevel);
%         
%         % now get rid of the edge buffers
%         startSamp = 2 * sincLength + 1;
%         endSamp   = 2 * sincLength + 2 * waveLength;
%         waveforms = filt_wv(:, startSamp : endSamp, :);
%     else
%         % wavelet filter the raw data; here, do all the wires so noisy wires
%         % are included in the final .nex file.
%         fdata = wavefilter(rawData, ones(length(wireList), 1), maxLevel);
% 
%         waveforms = extractWaveforms(fdata, ts, peakLoc, waveLength);
%     end
    
    for iWire = 1 : length(wireList)
        wf = squeeze(waveforms(:, :, iWire))';
        if ~isempty(wf)
            appendNexWaveforms( nex_fn, iWire, numSamplesWritten, wf);
        end
    end
    numSamplesWritten = numSamplesWritten + length(ts);
    
end
% may have to write timestamps into the .nex file first, then go back and
% put the waveforms in to avoid overflowing memory (and keep the ordering
% of data in the .nex file intact



end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function nexName = createNexName( hsdFile, targetDir, wireList )
%
% usage: nexName = createNexName( hsdFile, wireList )
%
% INPUTS:
%   hsdFile - name of the .hsd file
%   targetDir - target directory in which to save the .nex file
%   wireList - wires on which to extract spiked
%
% OUTPUTS:
%   nexName - name of the .nex file to create for this
%       tetrode/stereotrode/single wire. It is made by taking the name of
%       the .hsd file, which is assumed to be of the form:
%           XXXX_YYYYMMDD_HH-MM-SS.hsd,
%       where XXXX is the animal identifier, YYYYMMDD is the date of the
%       recording, and HH-MM-SS is the time. To the name of the .hsd file,
%       '_ZZZ' is appended, where ZZZ is the name of the channel on which
%       spikes are being extracted (ie, 'T01' = tetrode 1, 'R01' - ref 1,
%       etc. So, the final name is of the form:
%           XXXX_YYYYMMDD_HH-MM-SS_ZZZ.nex

[~, hsdName, ~] = fileparts(hsdFile);

header = getHSDHeader( hsdFile );

chType = header.channel(wireList(1)).channel_type;
chNum  = header.channel(wireList(1)).channel_number;

switch chType
    case 1,     % tetrode
        typeString = 'T';
    case 2,     % ref (stereotrode)
        typeString = 'R';
end

ZZZ = sprintf('%c%02d', typeString, chNum);

nexName = fullfile(targetDir, [hsdName '_' ZZZ '.nex']);

end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function plxName = createPLXName( hsdFile, targetDir, wireList )
%
% usage: nexName = createNexName( hsdFile, wireList )
%
% INPUTS:
%   hsdFile - name of the .hsd file
%   targetDir - target directory in which to save the .nex file
%   wireList - wires on which to extract spiked
%
% OUTPUTS:
%   nexName - name of the .nex file to create for this
%       tetrode/stereotrode/single wire. It is made by taking the name of
%       the .hsd file, which is assumed to be of the form:
%           XXXX_YYYYMMDD_HH-MM-SS.hsd,
%       where XXXX is the animal identifier, YYYYMMDD is the date of the
%       recording, and HH-MM-SS is the time. To the name of the .hsd file,
%       '_ZZZ' is appended, where ZZZ is the name of the channel on which
%       spikes are being extracted (ie, 'T01' = tetrode 1, 'R01' - ref 1,
%       etc. So, the final name is of the form:
%           XXXX_YYYYMMDD_HH-MM-SS_ZZZ.nex

[~, hsdName, ~] = fileparts(hsdFile);

header = getHSDHeader( hsdFile );

chType = header.channel(wireList(1)).channel_type;
chNum  = header.channel(wireList(1)).channel_number;

switch chType
    case 1,     % tetrode
        typeString = 'T';
    case 2,     % ref (stereotrode)
        typeString = 'R';
end

ZZZ = sprintf('%c%02d', typeString, chNum);

nexName = fullfile(targetDir, [hsdName '_' ZZZ '.plx']);

end