function SOC_next = battery_model(SOC, P_bat, C_bat, Ts)
    % الحساب الصحيح لتغير SOC
    SOC_delta = (P_bat * Ts) / (C_bat * 3600);  % التحويل من واط-ثانية إلى واط-ساعة
    SOC_next = SOC + SOC_delta;
    
    % تطبيق الحدود
    SOC_next = max(0.2, min(0.98, SOC_next));
end