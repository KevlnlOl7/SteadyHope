function x = gen_ram(n_cycles, f_ram, amp, tremor_amp, decrement, rhythm_jit, speed, seed)
% GEN_RAM  合成 RAM(快速輪替動作)角速度 — 共用於 dtw_features.m / gating_classifier.m
%   以「固定週期數」產生: speed 只改快慢(長度), 不改來回次數(公平做 DTW 速度不變性)。
%   rhythm_jit=節律不規則、decrement=振幅衰減(bradykinesia)、疊加 5 Hz 靜止性震顫。
    rng(seed); FS = 100;
    f_inst = f_ram*speed;
    n = round(n_cycles/f_inst*FS); t = (0:n-1)/FS; dur = n/FS;
    phi = 0; x = zeros(1,n);
    for k = 1:n
        f = f_inst*(1 + rhythm_jit*sin(2*pi*0.7*t(k)) + rhythm_jit*0.3*randn);
        phi = phi + 2*pi*f/FS;
        a = amp*(1 - decrement*t(k)/dur);                 % 振幅衰減 (bradykinesia)
        x(k) = a*sin(phi) + tremor_amp*sin(2*pi*5*t(k));  % 輪替 + 靜止性震顫
    end
end
