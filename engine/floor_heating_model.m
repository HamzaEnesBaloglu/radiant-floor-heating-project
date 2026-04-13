function [q_flux, t_surf_avg, x_vals, t_ripple, q_down, q_total, pipe_length, pressure_drop] = floor_heating_model(t_room, t_water, spacing, r_cover, t_below, r_insulation, room_area)
    % 1D ANALYTICAL FIN EFFICIENCY & FLUID DYNAMICS MODEL

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
    q_down = (t_water - t_below) / r_insulation;
    q_total = q_flux + q_down;

    % 7. AKIŞKANLAR MEKANİĞİ VE BASINÇ KAYBI
    % room_area artık Python'dan parametre olarak geliyor.
    
    % Suyun ve Borunun Fiziksel Özellikleri
    rho = 992;          % Suyun yoğunluğu (kg/m^3)
    cp = 4179;          % Suyun özgül ısısı (J/kgK)
    mu = 0.000653;      % Dinamik viskozite (Pa.s)
    
    d_out = 0.016;      % PEX Boru dış çapı (16 mm)
    t_pipe = 0.002;     % Et kalınlığı (2 mm)
    d_in = d_out - (2 * t_pipe); % İç çap (12 mm -> 0.012 m)
    
    % Toplam Boru Metrajı (L)
    pipe_length = room_area / spacing;
    
    % Odanın İhtiyacı Olan Toplam Enerji (Watt)
    total_heat_watt = q_total * room_area;
    
    % Debinin Hesaplanması (Suyun 5 derece soğuyarak döndüğü varsayımıyla)
    delta_T_water = 5; 
    mass_flow = total_heat_watt / (cp * delta_T_water); % kg/s
    vol_flow = mass_flow / rho; % m^3/s
    
    % Boru İçi Su Hızı (m/s)
    cross_area = pi * (d_in^2) / 4;
    velocity = vol_flow / cross_area;
    
    % Reynolds Sayısı (Akış Tipi: Laminer veya Türbülanslı)
    Re = (rho * velocity * d_in) / mu;
    
    % Sürtünme Katsayısı (f) - PEX boru (Blasius)
    if Re < 2300
        f = 64 / Re;
    else
        f = 0.3164 / (Re^0.25);
    end
    
    % Darcy-Weisbach Basınç Kaybı (kPa cinsine çevrilmiş)
    delta_p_pascal = f * (pipe_length / d_in) * (rho * velocity^2) / 2;
    pressure_drop = delta_p_pascal / 1000; % kPa
end