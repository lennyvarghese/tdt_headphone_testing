function headphone_test(testID, sampleRate, channel, hb7Setting, stimType, ...
                        nReps, varName)
% headphone_test(testID, channel, hb7Setting, stimType, varName, nReps)
% helper function to record ear simulator output and TDT RP2.1
%
% Note: headphone_test.rcx must be in the same directory
%
% last updated 2016-07-28 LV lennyv_at_bu_dot_edu
%
% function arguments:
% testID: what to call this recording (name of saved mat file; will be saved in
%         the working directory) 
% sampleRate: the sampleRate at which the TDT RP2.1 operates. Should match the
%             sample rate of the stimulus when presenting audio via the TDT
%             RP2.1/HB7 combo. If recording from an external source (on a
%             different clock), this is the sample rate that the recording via
%             TDT will take place. Should be either 24414(.0625) or 48828(.125)
% channel: headphone channel 1 or 2 when RP2.1/HB7 combo is used for audio
%          presentation, Doesn't matter if stimType is "none"
% hb7Setting: what the HB7 is set to (in dB). This is used to determine the
%              voltage that the headphone actually "sees" when using the
%              RP2.1/HB7 combo for audio presentation. Doesn't matter if
%              stimType is "none"
% stimType: "tones" (log spaced tones, 1 s in duration, from 20 to 20000,
%                     RMS 1 V)
%           "click" - a click train - useful for computing conduction delays
%                     (5 V peak height, 82 microseconds)
%           "noise" - gaussian random noise (RMS 1V prior to HB7 scaling)
%           "none" - no sound played through headphones. useful for recording
%                     an external stimulus (like tone from pistonphone
%                     calibrator, or another sound card)
%           path_to_matfile - a mat file with a stimulus for which the level
%                             is to be measured. if it is a 1 channel
%                             stimulus, then it will be played back on
%                             whatever channel is specified to in the
%                             arguments. if it is a 2 channel stimulus, then
%                             the channel played will be the one matching the
%                             channel selected for playback.
% nReps: the number of recordings to take. For "tone", this specifies the
%        number of log-spaced steps between 20Hz and 20 khz.
% varname: the name of the variable in the mat file specified. Not
%                     unless stimType is a mat filename (set to '' when using
%                     "tones", "click", "noise", or "none", or do not specify).

assert(channel == 1 || channel == 2);

if nargin == 4
    nReps = 1;
end
if nargin == 5
    varName = '';
end

f1 = figure(999);
set(f1,'Position', [5 5 30 30], 'Visible', 'off');
RP = actxcontrol('RPco.x', [5 5 30 30], f1);
RP.ConnectRP2('USB', 1);
RP.ClearCOF;
if round(sampleRate) == 48828
    RP.LoadCOFsf('headphone_test.rcx', 3);
elseif round(sampleRate) == 24414
    RP.LoadCOFsf('headphone_test.rcx', 2);
end
RP.Run();

RP.SetTagVal('channel', channel);
if channel == 1
    otherChannel = 2;
else
    otherChannel = 1;
end;
RP.SetTagVal('otherChannel', otherChannel);
RP.ZeroTag('headphoneInput');
RP.ZeroTag('couplerOutput');
RP.ZeroTag('testSignal');
RP.SoftTrg(1);
curSample = RP.GetTagVal('bufIdx');
RP.SetTagVal('nSamps', 25);
while curSample ~= 0
    curSample = RP.GetTagVal('bufIdx');
end

t = 0:1/sampleRate:(1-1/sampleRate);
if strcmpi(stimType, 'tones')
    freqs = logspace(log10(20), log10(20000), nReps);
    testSignal = zeros([length(freqs), length(t)], 'single');
    for fi = 1:length(freqs)
        testSignal(fi, :) = single(2*sin(2*pi*t*freqs(fi))/sqrt(2));
    end
elseif strcmpi(stimType, 'click')
    testSignal = zeros(nReps, length(t), 'single');
    for fi = 1:size(testSignal, 1)
        
        pos = randperm(length(t), 20);
        neg = randperm(length(t), 20);
        
        while any(intersect(pos, neg))
            pos = randperm(length(t), 20);
            neg = randperm(length(t), 20);    
        end
        testSignal(fi, pos) = 5;
        testSignal(fi, pos+1) = 5;
        if sampleRate >= 48828
            testSignal(fi, pos+2) = 5;
            testSignal(fi, pos+3) = 5;
        end
    end
elseif strcmpi(stimType, 'noise')
    ok = false;
    while ~ok
        testSignal = randn([nReps, length(t)]);
        testSignal = single(bsxfun(@rdivide, testSignal, ...
                            sqrt(mean(testSignal.^2, 2))));
        % ensure no clipping occurs
        if max(abs(testSignal(:))) < 9
            ok = true;
        end
    end
elseif strcmpi(stimType, 'none')
    testSignal = zeros([nReps, length(t)], 'single');
else
    s = load(stimType, varName);
    x = getfield(s, varName);
    if size(x, 2) > 1
        x = x(:, channel);
    end
    scaleFac = 1 / rms(x);
    x = x * scaleFac;
    infoStr = sprintf(['Original RMS (V): %2.3e\nNew RMS (V): ',...
                       '%2.3e\nNew peak-to-peak (V): %2.3e'],...
                       1/scaleFac, 1.0*db2mag(hb7Setting),...
                       max(abs(x))*db2mag(hb7Setting));
    ButtonName = questdlg(infoStr, ...
                         'Verify', ...
                         'OK', 'Abort', 'Abort');
    switch ButtonName
        case 'Abort', return
    end
    testSignal = repmat(x', nReps, 1);
    [~, stimType, ~] = fileparts(stimType);
end

headphoneInput = zeros(size(testSignal), 'single');
couplerOutput = zeros(size(testSignal), 'single');
nSamps = size(testSignal, 2);
if nSamps > 2.794E6
    error('stimulus size must be < 2.794E6 samples')
end
                                                 
for fi = 1:size(testSignal,1)
    fprintf('Sweep %d / %d\n', fi, size(testSignal, 1));
    RP.SetTagVal('nSamps', nSamps);
    
    RP.WriteTagVEX('testSignal', 0, 'F32', testSignal(fi, :)');
    RP.SoftTrg(1);
    curSample = RP.GetTagVal('bufIdx');
    fprintf('\nSample: %07d', 0)
    while curSample ~= 0
        curSample = RP.GetTagVal('bufIdx');
        if curSample ~= 0
            fprintf('\b\b\b\b\b\b\b%07d', curSample)
        else
            fprintf('\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b all %d samples played!',...
                nSamps)
        end
    end
    fprintf(' Retrieving data... \n')
    headphoneInput(fi, :) = db2mag(hb7Setting) * ...
        RP.ReadTagVEX('headphoneInput', 0, nSamps, 'F32', 'F32', 1);
    couplerOutput(fi, :) = RP.ReadTagVEX('couplerOutput', 0, nSamps, ...
        'F32', 'F32', 1);
    
    RP.ZeroTag('headphoneInput');
    RP.ZeroTag('couplerOutput');
    RP.ZeroTag('testSignal');
end

t = 0:1/sampleRate:((nSamps-1) / sampleRate);
if exist('freqs', 'var') ~= 1
    save([testID '_' stimType '.mat'], 't', 'hb7Setting', ...
        'headphoneInput', 'couplerOutput', 'testSignal', '-v7');
else
    save([testID '_' stimType '.mat'], 't', 'hb7Setting',...
        'headphoneInput', 'couplerOutput', 'testSignal', 'freqs', '-v7');
end
fprintf('data saved as: %s\n', fullfile(pwd, [testID '_' stimType '.mat']));
RP.Halt;
RP.ClearCOF;
close(f1);

end