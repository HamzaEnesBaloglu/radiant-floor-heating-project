function [q_flux, t_surf_avg, x_vals, t_ripple, q_down, q_total] = floor_heating_model(t_room, t_water, spacing, r_cover, t_below, r_insulation)
    % 1D ANALYTICAL FIN EFFICIENCY MODEL (Termodinamik Çözücü)

    % 1. Fiziksel Sabitler
    h_conv_rad = 10.8;       
    k_concrete = 1.4;        
    t_concrete = 0.05;       
    r_concrete = t_concrete / k_concrete; 

    r_up = r_concrete + r_cover;
    r_total = r_up + (1 / h_conv_rad);

    % 2. Kanat (Fin) Parametresi 'm' Hesaplaması
    u_surface = 1 / (r_cover + (1 / h_conv_rad));
    m_param = sqrt(u_surface / (k_concrete * t_concrete));

    % 3. Kanat Verimi (Fin Efficiency - \eta)
    L = spacing / 2;
    fin_efficiency = tanh(m_param * L) / (m_param * L);

    % 4. Ortalama Isı Akısı (q_up) ve Yüzey Sıcaklığı
    q_flux = ((t_water - t_room) / r_total) * fin_efficiency;
    t_surf_avg = t_room + (q_flux / h_conv_rad);

    % 5. Dalgalanma (Ripple) Çözümü
    num_points = 50; 
    x_vals = linspace(0, spacing, num_points)';
    t_base_surf = t_room + ((t_water - t_room) / r_total) * (1 / h_conv_rad);
    
    t_ripple = zeros(num_points, 1);
    for i = 1:num_points
        x = x_vals(i);
        if x <= L
            dist_from_center = L - x;
        else
            dist_from_center = x - L;
        end
        t_ripple(i) = t_room + (t_base_surf - t_room) * (cosh(m_param * dist_from_center) / cosh(m_param * L));
    end

    % 6. AŞAĞI YÖNLÜ ISI KAYBI (Downward Heat Loss)
    % Alt kat sıcaklığı ve yalıtım direnci artık Python API üzerinden arayüzden alınıyor.

    % Aşağıya kaçan ısı akısı (W/m^2)
    q_down = (t_water - t_below) / r_insulation;

    % Kazanın üretmesi gereken TOPLAM GÜÇ (Odaya giden + Aşağı kaçan)
    q_total = q_flux + q_down;
end