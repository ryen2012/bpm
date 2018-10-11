function [resp, t] = sirius_button_bpm_resp(beam_current, f, beampos, att1_val, machine)

physical_constants;

fe = machine.bpm.cable.fe;
cablelength = machine.bpm.cable.length;
beta = machine.beta;
R0 = machine.bpm.pickup.button.R0;
bd = machine.bpm.pickup.button.diameter;
frf = machine.frf;

% Beam current to image current response
% Choose button with the highest signal
CovF = beamcoverage(machine.bpm.pickup, beampos, 500);
beam2bpm_current = max(CovF)*bd/(beta*c)*(1j*2*pi*f);

% Button impedance response
% (from beam image current to voltage on button)
%Cb = calccapacitance(bpm.pickup.button);
Cb = bpm.pickup.button.Cb_meas;
Zbutton = R0./(1+1j*2*pi*f*R0*Cb);

% Coaxial cable response (LMR195)
Zcable = exp(-(1+sign(f).*1j).*sqrt(abs(f)/fe)*cablelength/30.5);

% RFFE v2 low pass filter response
% Based on Mini-circuits LFCN-530 (https://www.minicircuits.com/pdfs/LFCN-530.pdf)
%flpf_spec = 1e6*[0 1 100 500 530 670 700 815 820 945 1315 2140 3000 3640 4910 6000 1e15];
%Glpf_spec = [0 -0.05 -0.22 -0.73 -0.81 -1.95 -2.89 -26.41 -28.41 -44.98 -39.77 -57.51 -47.94 -42.84 -18.81 -24.8 -24.8];
flpf_spec = 1e6*[0 1 100 500 530 670 700 815 820 945 1315 2140 3000 1e15];
Glpf_spec = [0 -0.05 -0.22 -0.73 -0.81 -1.95 -2.89 -26.41 -28.41 -44.98 -39.77 -57.51 -60 -60];
Glpf = interp1(flpf_spec, Glpf_spec, f);
Glpf = 10.^(Glpf/20);
LPF = mps(Glpf);

% RFFE v2 bandpass filter
% Based on TAI-SAW TA1113A (http://www.taisaw.com/upload/product/TA1113A%20_Rev.1.0_.pdf)
%fbpf_spec = [0 300e3 100e6 200e6 300e6 (frf-20e6) (frf-10e6) (frf+10e6) (frf+40e6) (frf+40e6+2500e6) 1e15];
%Gbpf_spec = [-80 -80 -70 -60 -55 -52 -2 -2 -55 0 0];
fbpf_spec = [0 300e3 100e6 200e6 300e6 (frf-20e6) (frf-10e6) (frf+10e6) (frf+40e6) 1e15];
Gbpf_spec = [-80 -80 -70 -60 -55 -52 -2 -2 -55 -55];
Gbpf = interp1(fbpf_spec, Gbpf_spec, f);
Gbpf = 10.^(Gbpf/20);
BPF = mps(Gbpf);

% RFFE v2 RF amplifier response (Mini-circuits TAMP-72LN)
amp_gain = 10;
amp_nonlinearity = [-0.048634 1 0];

% Attenuator response (Mini-circuits DAT-31R5-SP)
att1 = 10^(-1.5/20)*10^(-att1_val/20);

% RFFE-FMC ADC coaxial cable response
rffe_adc_cable_il = 10^(-0.5/20);

% FMC ADC analog front-end response
adc_afe_il = 10^(-2.5/20);

% ADC non-linearity response
adc_nonlinearity = [-0.001 1 0];

% Build frequency responses along signal path
names = {'Beam current', ...
         'BPM button current', ...
         'BPM button voltage', ... 
         'Coax. cable (BPM to RFFE)', ... 
         'RFFE LPF #1', ... 
         'RFFE BPF #1', ... 
         'RFFE Amp #1', ... 
         'RFFE Att #1', ... 
         'RFFE LPF #2', ... 
         'RFFE Amp #2', ... 
         'RFFE LPF #3', ... 
         'RFFE-FMC ADC coax. cable', ... 
         'ADC analog front-end', ...
         'ADC input', ...
         };
     
freqresps = {1, ...
             beam2bpm_current, ...
             Zbutton, ...
             Zcable, ...
             LPF, ...
             BPF, ...
             amp_gain, ...
             att1, ...
             LPF, ...
             amp_gain, ...
             LPF, ...
             rffe_adc_cable_il, ...
             adc_afe_il, ...
             1, ...
             };

noisefactors = {1, ...
               1, ...
               1+1./abs(Zbutton).^2, ...
               [], ...
               [], ...
               [], ...
               10^(1/10), ...
               [], ...
               [], ...
               10^(1/10), ...
               [], ...
               [], ...
               [], ...
               [], ...
               };
        
         
nonlinearities = {[], ...
                  [], ...
                  [], ...
                  [], ...
                  [], ...
                  [], ...
                  amp_nonlinearity, ...
                  [], ...
                  [], ...
                  amp_nonlinearity, ...
                  [], ...
                  [], ...
                  [], ...
                  adc_nonlinearity, ...
                  };

[resp, t] = buildresp(beam_current, zeros(1,length(f)), f, R0, names, freqresps, noisefactors, nonlinearities);

function [resp, t] = buildresp(signal, noise_psd, f, R0, names, freqresps, F, NL)

df = f(2)-f(1);
Fs = 2*f(end) + df;

signal_time = fourierseries2time(abs(signal), angle(signal), f, 2*length(f)-1)';

[noise_freq_amp, ~, noise_freq_ph] = fourierseries(randn(1, 2*length(f)-1)*sqrt(Fs), Fs);
noise_freq = noise_freq_amp'.*exp(1j*noise_freq_ph').*sqrt(noise_psd);
noise_time = fourierseries2time(abs(noise_freq), angle(noise_freq), f, 2*length(f)-1)';

noise_Vrms = sqrt(noise_psd*R0*df);

resp = struct('name', names{1}, ...
              'freqresp', freqresps{1}, ...
              'nonlinearity', NL{1}, ...
              'signal_freq', signal, ...
              'signal_time', signal_time, ...
              'noise_psd', noise_psd, ...
              'noise_Vrms', noise_Vrms, ...
              'noise_freq', noise_freq, ...
              'noise_time', noise_time  ...
              );

% Reference noise power spectral density of a matched circuit at 290 K [W]
physical_constants;
refnoise_psd = repmat(K*290, 1, length(f));

for i=2:length(names)
    resp(i).name = names{i};
    resp(i).freqresp = resp(i-1).freqresp.*freqresps{i};
    resp(i).signal_freq = resp(i).freqresp.*resp(1).signal_freq;
    [resp(i).signal_time, t] = fourierseries2time(abs(resp(i).signal_freq), angle(resp(i).signal_freq), f, 2*length(f)-1);
    
    if ~isempty(NL{i})
        resp(i).signal_time = polyval(NL{i}, resp(i).signal_time);
    end
    
    % Power gain (G) from amplitude frequency response
    G = abs(freqresps{i}).^2;

    if isempty(F{i})
        F{i} = 1./G;
    end
    
    % From the IEEE's noise factor (F) definition:
    %
    %   F = Na + K*To*B*G
    %       -------------
    %          K*To*B*G
    %
    % where K*To with To = 290 K is reference thermal noise (-174 dBm/Hz),
    % B is the bandwidth of interest, G is the stage's power gain and Na 
    % is the noise power added by the stage.
    %
    % Hence the PSD of added noise is given by:
    %
    %   Na/B = (F-1)*K*To*G
    Na_psd = (F{i}-1).*refnoise_psd.*G;
    
    % Noise propagated from previous stage (noise at input times gain)
    NiG_psd = (resp(i-1).noise_psd.*abs(freqresps{i})).^2;

    % Since the propagated noise and the stage own noise are uncorrelated,
    % their PSD are summed to give the total stage noise PSD
    resp(i).noise_psd = NiG_psd + Na_psd;
    
    [noise_freq_amp, ~, noise_freq_ph] = fourierseries(randn(1, 2*length(f)-1)*sqrt(Fs), Fs);
    Na_noise_freq = noise_freq_amp'.*exp(1j*noise_freq_ph').*sqrt(Na_psd);
    Na_noise_time = fourierseries2time(abs(Na_noise_freq), angle(Na_noise_freq), f, 2*length(f)-1)';
    
    NiG_noise_freq = resp(i-1).noise_freq.*sqrt(G);
    NiG_noise_time = fourierseries2time(abs(NiG_noise_freq), angle(NiG_noise_freq), f, 2*length(f)-1)';

    resp(i).noise_time = Na_noise_time + NiG_noise_time;
    
    [amp, ~ , ph] = fourierseries(resp(i).noise_time, Fs);
    resp(i).noise_freq = (amp.*exp(1j*ph))';
    
    resp(i).noise_Vrms = sqrt(resp(i).noise_psd*R0*df);
end