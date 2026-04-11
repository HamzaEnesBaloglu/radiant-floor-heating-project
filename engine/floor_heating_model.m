function [q_flux, t_surf, x_vals, t_ripple] = floor_heating_model(t_room, t_water, spacing, r_cover)
    % THERMAL_SOLVER - Kılkış Yerden Isıtma Algoritması Çekirdeği
    % Girdiler:
    %   t_room  : Oda iç sıcaklığı (C)
    %   t_water : Boru içi ortalama su sıcaklığı (C)
    %   spacing : Boru aralığı (m)
    %   r_cover : Üst katman ısıl direnci (m^2K/W)
    
    % 1. Sabitler ve Kabuller (Gelecekte excel'den güncellenecek)
    h_conv_rad = 10.8; % Kombine taşınım ve ışınım katsayısı (W/m^2K)
    r_concrete = 0.03; % Şap direnci (m^2K/W)
    
    % 2. Toplam Isıl Direnç (R_total)
    % R_total = Yukarı yönlü şap + kaplama + yüzey film direnci
    r_up = r_concrete + r_cover;
    r_total = r_up + (1 / h_conv_rad);
    
    % 3. Isı Akısı (q) ve Ortalama Yüzey Sıcaklığı (Ts)
    % Basitleştirilmiş 1D sürekli rejim (Sistemi ayağa kaldırmak için)
    q_flux = (t_water - t_room) / r_total;
    t_surf = t_room + (q_flux / h_conv_rad);
    
    % 4. Sıcaklık Dağılımı / Ripple Efekti (Boru aralığı boyunca)
    % Kanat modeli (Fin Efficiency) için geçici dalga fonksiyonu
    % İleride buraya Kılkış'ın hiperbolik kosinüs (cosh) formülleri eklenecek.
    num_points = 20;
    x_vals = linspace(0, spacing, num_points)';
    
    % Dalga genliği (Boru aralığı arttıkça genlik büyür)
    amplitude = spacing * 10; 
    
    % Kosinüs fonksiyonu ile boru üstü(sıcak) ve arası(soğuk) modellemesi
    t_ripple = t_surf + amplitude * cos((x_vals / spacing) * 2 * pi);
    
end