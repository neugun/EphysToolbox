function locs = getSpikeLocations(data,validMask,Fs,varargin)
% pre-process data: high pass -> artifact removal
% data = nCh x nSamples
% [] save figures? Configs?
% [] align actual spike peaks after getting y_snle

onlyGoing = 'none';

windowSize = round(Fs/2400); %snle
snlePeriod = round(Fs/8000); %snle
minpeakdist = Fs/1000; %hardcoded deadtime
threshGain = 8;
showMe = 0;

for iarg = 1 : 2 : nargin - 3
    switch varargin{iarg}
        case 'onlyGoing'
            onlyGoing = varargin{iarg + 1};
        case 'windowSize'
            windowSize = varargin{iarg + 1};
        case 'minpeakdist'
            minpeakdist = varargin{iarg + 1};
        case 'threshGain'
            threshGain = varargin{iarg + 1};
        case 'showMe'
            showMe = varargin{iarg + 1};
    end
end

disp('Calculating SNLE data...')
%Find smooth non-linear energy
y_snle = snle(data,validMask,'windowSize',windowSize,'snlePeriod',snlePeriod);

%subtract the mean snle value from the snle value
y_snle = bsxfun(@minus,y_snle,mean(y_snle,2)); %zero mean

%Calculate the minimum peak height
minpeakh = threshGain * mean(median(abs(y_snle),2));

disp('Extracting peaks of summed SNLE data...')
locs = peakseek(sum(y_snle,1),minpeakdist,minpeakh);
disp([num2str(length(locs)),' spikes found...']);

% plot the raw data and smooth non linear energy
% figure;
% hs(1) = subplot(211);
% plot(data(1,:));
% hs(2) = subplot(212);
% plot(sum(y_snle(1,:),1));
% linkaxes(hs,'x');

% this just sums the lines, probably need to add in the valid mask or
% handle this better in the future
if(strcmpi(onlyGoing,'positive') || strcmpi(onlyGoing,'negative'))
    sumData = sum(data,1);
    if(strcmp(onlyGoing,'positive'))
        locsGoing = sumData(:,locs) > 0; %positive spikes
    elseif(strcmp(onlyGoing,'negative'))
        locsGoing = sumData(:,locs) < 0; %negative spikes
    end
    locs = locs(locsGoing);
    disp([num2str(round(length(locs)/length(locsGoing)*100)),'% spikes going ',onlyGoing,'...']);
end

if(showMe)
    disp('Showing you...')
    nSamples = min([400 length(locs)]);
    locWindow = 40;
    t = linspace(0,(locWindow*2)/Fs,locWindow*2)*1e3;
    someLocs = datasample(locs,nSamples); % random samples
    for i=1:size(data,1)
        figure;
        for j=1:length(someLocs)
            plot(t,data(i,someLocs(j)-locWindow:someLocs(j)+locWindow-1));
            hold on;
        end
        title(['data row',num2str(i),' - ',num2str(nSamples),' samples']);
        xlabel('time (ms)')
        ylabel('uV')
        xlim([0 max(t)]);
    end
end