clc; clear; close all;

% --- 1. AUDIO INPUT ---
fprintf('Please select an audio file...\n');
[file, path] = uigetfile('*.wav', 'Select an Audio File');
if isequal(file, 0), disp('Cancelled.'); return; end
File_Name = fullfile(path, file);

[Audio, Fs] = audioread(File_Name);
Audio_Signal = Audio(:, 1);
if isempty(Audio_Signal), error('Audio file is empty.'); end
fprintf('Audio loaded. Length: %d samples.\n', length(Audio_Signal));

% --- 2. CONFIGURATION ---
SF = 16; Spreading_Code = ones(SF, 1);
n_bits = 16; Num_Levels = 2^n_bits;
M = 16; BitsPerSymbol = 4;

% --- 3. TRANSMITTER ---
fprintf('Encoding and Modulating... (Please wait)\n');
[Quantized_Samples, Levels] = Quantizer_1(Audio_Signal, n_bits);
Bit_Stream = Encoder_1(Quantized_Samples, Num_Levels);
Bit_Stream = Bit_Stream(:);

num_pad = mod(length(Bit_Stream), BitsPerSymbol);
if num_pad > 0
    Bit_Stream_Pad = [Bit_Stream; zeros(BitsPerSymbol-num_pad, 1)];
else
    Bit_Stream_Pad = Bit_Stream;
end

Symbols = qammod(Bit_Stream_Pad, M, 'InputType', 'bit', 'UnitAveragePower', true);
Spread_Signal = kron(Symbols, Spreading_Code);

% --- 4. CHANNELS ---
fprintf('Applying Channels...\n');
Ray_Ch = comm.RayleighChannel('SampleRate', Fs, 'MaximumDopplerShift', 30, ...
    'PathDelays', [0 200]*1e-9, 'AveragePathGains', [0 -3], 'FadingTechnique', 'Filtered Gaussian noise');
Ric_Ch = comm.RicianChannel('SampleRate', Fs, 'MaximumDopplerShift', 30, ...
    'PathDelays', [0 100 200]*1e-9, 'AveragePathGains', [0 -3 -6], 'KFactor', 5, 'FadingTechnique', 'Filtered Gaussian noise');
AWGN_Ch = comm.AWGNChannel('EbNo', 20, 'BitsPerSymbol', BitsPerSymbol);

Tx_Ray = Ray_Ch(Spread_Signal);
Tx_Ric = Ric_Ch(Spread_Signal);
Tx_AWGN = AWGN_Ch(Spread_Signal);

% --- 5. RECEIVER ---
    function [Bits, Con] = rx_local(Sig, SF, Code, M, Len)
        Num = length(Sig)/SF;
        Reshaped = reshape(Sig, SF, Num);
        Con = (Code' * Reshaped)' ./ SF;
        D = qamdemod(Con, M, 'OutputType', 'bit', 'UnitAveragePower', true);
        Bits = D(1:Len);
    end

[Bits_Ray, Con_Ray] = rx_local(Tx_Ray, SF, Spreading_Code, M, length(Bit_Stream));
[Bits_Ric, Con_Ric] = rx_local(Tx_Ric, SF, Spreading_Code, M, length(Bit_Stream));
[Bits_AWGN, Con_AWGN] = rx_local(Tx_AWGN, SF, Spreading_Code, M, length(Bit_Stream));

% --- PLOTTING ---
figure('Name', '16-QAM Constellations', 'Color', 'white');
subplot(1,3,1); plot(real(Con_Ray), imag(Con_Ray), '.'); title('16-QAM Rayleigh'); axis square; grid on;
subplot(1,3,2); plot(real(Con_Ric), imag(Con_Ric), '.'); title('16-QAM Rician'); axis square; grid on;
subplot(1,3,3); plot(real(Con_AWGN), imag(Con_AWGN), '.'); title('16-QAM AWGN'); axis square; grid on;

% --- 6. OUTPUT ---
audiowrite('Out_16QAM_Rayleigh.wav', Decoder_1(Bits_Ray', Levels), Fs);
audiowrite('Out_16QAM_Rician.wav', Decoder_1(Bits_Ric', Levels), Fs);
audiowrite('Out_16QAM_AWGN.wav', Decoder_1(Bits_AWGN', Levels), Fs);
disp('16-QAM Audio files saved.');


%% --- LOCAL HELPER FUNCTIONS ---

function [Quantized_Samples, Levels] = Quantizer_1(Samples, n_bits)
    Max_Samples = max(Samples);
    Mini_Samples = min(Samples);
    L = 2^n_bits;
    Quantized_Samples = zeros(1,length(Samples));
    level_sep =(Max_Samples-Mini_Samples)/L; 
    level_1 = [0:level_sep: Max_Samples];
    level_2 = [0-level_sep: -level_sep : Mini_Samples];
    Levels = [flip(level_2) level_1 ];
    transitions = Levels + level_sep/2;
    for i = 1:length(Samples)
        if Samples(i)> transitions(L)
            Quantized_Samples(i) = L;
        else
            for j=1:L
                if Samples(i)<transitions(j)
                   Quantized_Samples(i) = j;
                    break
                end
            end
        end
    end
end

function Bit_Stream = Encoder_1(Quantized_Samples,Num_Levels)
  Bit_Stream = [];
  temp = dec2bin(0:Num_Levels-1, 16);
  for i = 1:length(Quantized_Samples)
      Bit_Stream = [Bit_Stream , temp(Quantized_Samples(i), :)-'0'];
  end
end

function Decoded_Signal = Decoder_1(Recieved_Signal, Levels)
   Decoded_Signal = [];
   n = 16;
   Recieved = sprintf('%d', Recieved_Signal);
   for i = 1 : n : length(Recieved_Signal)
       if (i + n <= length(Recieved_Signal))
           Decoded_Signal = [Decoded_Signal ,Levels(1+bin2dec(Recieved(i:i+n-1)))];
       end
   end
end