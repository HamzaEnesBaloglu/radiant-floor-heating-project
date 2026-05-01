function [q_flux_arr, t_surf_arr, q_down_arr, q_total_arr, len_per_zone_arr, p_drop_arr, room_energy_arr, room_co2_arr, q_loss_arr, num_zones_arr, flow_lpm_arr, fin_eff_arr, re_arr, coverage_ratio_arr, surplus_watt_arr, t_dew_arr, rad_ratio_arr, sys_total_heat, sys_max_pressure, main_p_drop, sys_pump_power, sys_total_energy, sys_total_co2, sys_t_mean, sys_co2_reduction] = floor_heating_model(t_water, t_below_arr, r_insulation, dist_main, d_out_main, cop, hours, co2_factor, t_out, wind_factor, rh, altitude, glycol_percent, ventilation_arr, active_area_arr, t_room_arr, spacing_arr, r_cover_arr, area_arr, dist_arr, ext_wall_len_arr, room_height_arr, window_area_arr, u_wall_arr, u_window_arr, pipe_material)
    % MULTI-ZONE HYDRAULIC, ECO & ACADEMIC THERMODYNAMICS SOLVER (V0.14.0)

    num_rooms = length(t_room_arr);
    q_flux_arr = zeros(1, num_rooms);
    t_surf_arr = zeros(1, num_rooms);
    q_down_arr = zeros(1, num_rooms);
    q_total_arr = zeros(1, num_rooms);
    len_per_zone_arr = zeros(1, num_rooms);
    p_drop_arr = zeros(1, num_rooms);
    room_energy_arr = zeros(1, num_rooms);
    room_co2_arr = zeros(1, num_rooms);
    q_loss_arr = zeros(1, num_rooms);
    num_zones_arr = zeros(1, num_rooms);
    flow_lpm_arr = zeros(1, num_rooms);
    fin_eff_arr = zeros(1, num_rooms); 
    re_arr = zeros(1, num_rooms);      
    coverage_ratio_arr = zeros(1, num_rooms);
    surplus_watt_arr = zeros(1, num_rooms);
    
    % Çiğlenme Noktası ve Radyant Oran Dizileri
    t_dew_arr = zeros(1, num_rooms);
    rad_ratio_arr = zeros(1, num_rooms);

    k_concrete = 1.4; t_concrete = 0.05;
    r_concrete = t_concrete / k_concrete; 
    
    % YENİ: DİNAMİK SU VE GLİKOL ÖZELLİKLERİ (Ampirik Yaklaşımlar)
    % %0 Glikol (Saf Su) -> rho: 992, cp: 4179, mu: 0.000653
    rho = 992 + (glycol_percent * 0.44); 
    cp = 4179 - (glycol_percent * 5.79);
    mu = 0.000653 * (1 + (glycol_percent * 0.04));
    
    delta_T_water = 5; 
    t_mean_water = t_water - (delta_T_water / 2); 
    sys_t_mean = t_mean_water; 

    % BORU MALZEMESİ TABLOSU: [d_out(m), t_pipe(m), k_pipe(W/mK), epsilon(m)]
    % 1=PEX-a, 2=PEX-AL-PEX, 3=PE-RT, 4=PE-Xa, 5=Bakır
    pipe_table = [0.016, 0.002, 0.40,  0.000007;   % PEX-a
                  0.016, 0.002, 0.45,  0.0000015;  % PEX-AL-PEX
                  0.016, 0.002, 0.40,  0.000007;   % PE-RT
                  0.017, 0.002, 0.38,  0.000007;   % PE-Xa
                  0.015, 0.001, 380.0, 0.0000015]; % Bakır
    pm = max(1, min(5, round(pipe_material)));
    d_out_room   = pipe_table(pm, 1);
    t_pipe_room  = pipe_table(pm, 2);
    k_pipe       = pipe_table(pm, 3);
    epsilon_room = pipe_table(pm, 4);
    d_in_room  = d_out_room - (2 * t_pipe_room);
    cross_area_room = pi * (d_in_room^2) / 4;

    sys_total_heat = 0; 
    total_vol_flow = 0; 
    max_loop_length = 100; 
    
    % F1 Rakım Düzeltmesi
    p_ratio = (1 - 2.25577e-5 * altitude)^5.25588;
    F1 = sqrt(p_ratio);

    for i = 1:num_rooms
        t_room = t_room_arr(i);
        spacing = spacing_arr(i);
        r_cover = r_cover_arr(i);
        room_area = area_arr(i);
        dist_to_coll = dist_arr(i); 
        t_below = t_below_arr(i); 

        % Çiğlenme Noktası (Magnus Formülü)
        alpha = (17.625 * t_room) / (243.04 + t_room) + log(rh/100);
        t_dew = (243.04 * alpha) / (17.625 - alpha);
        t_dew_arr(i) = t_dew;

        % F2 (Aktif Alan Oranı)
        F2 = active_area_arr(i) / 100;
        active_room_area = room_area * F2; 

        % 1. ISI KAYBI HESABI
        ext_wall_len = ext_wall_len_arr(i);
        room_height = room_height_arr(i);
        window_area = window_area_arr(i);
        u_wall = u_wall_arr(i);
        u_window = u_window_arr(i);

        a_wall_gross = ext_wall_len * room_height;
        a_wall_net = max(0, a_wall_gross - window_area);
        q_loss_watt = (a_wall_net * u_wall * wind_factor + window_area * u_window * wind_factor) * (t_room - t_out);
        q_loss_arr(i) = max(0, q_loss_watt); 

        % Dinamik Isı Transfer Katsayıları ve F3 (Hibrit Havalandırma)
        F3 = ventilation_arr(i);
        h_rad = 5.5;
        h_conv = 5.3 * F1 * F3;
        h_total_dynamic = h_rad + h_conv;
        rad_ratio_arr(i) = (h_rad / h_total_dynamic) * 100;

        % 2. TERMAL HESAPLAR VE KANAT VERİMİ
        r_up = r_concrete + r_cover;
        r_total = r_up + (1 / h_total_dynamic);
        u_surface = 1 / (r_cover + (1 / h_total_dynamic));
        m_param = sqrt(u_surface / (k_concrete * t_concrete));
        L = spacing / 2;
        
        fin_efficiency = tanh(m_param * L) / (m_param * L);
        fin_eff_arr(i) = fin_efficiency; 

        q_flux = ((t_mean_water - t_room) / r_total) * fin_efficiency;
        q_flux_arr(i) = q_flux;
        
        t_surf_arr(i) = t_room + (q_flux / h_total_dynamic);
        
        q_down = (t_mean_water - t_below) / r_insulation; 
        q_down_arr(i) = q_down;
        q_total = q_flux + q_down; 
        q_total_arr(i) = q_total;

        total_heat_supplied_watt = q_flux * active_room_area;
        sys_total_heat = sys_total_heat + (q_total * active_room_area); 
        
        % 3. ISIL YARGIÇ
        surplus_watt_arr(i) = total_heat_supplied_watt - max(0, q_loss_watt);
        if q_loss_watt > 0
            coverage_ratio_arr(i) = (total_heat_supplied_watt / q_loss_watt) * 100;
        else
            coverage_ratio_arr(i) = 100; 
        end

        % 4. ZONLAMA VE DEBİ
        total_pipe_length = (active_room_area / spacing) + (2 * dist_to_coll);
        num_zones = ceil(max(total_pipe_length, 1e-5) / max_loop_length);
        num_zones_arr(i) = num_zones;
        len_per_zone = total_pipe_length / num_zones;
        len_per_zone_arr(i) = len_per_zone;

        % Dinamik cp ve rho burada işin içine girer:
        mass_flow = (q_total * active_room_area) / (cp * delta_T_water); 
        vol_flow = mass_flow / rho; 
        total_vol_flow = total_vol_flow + vol_flow; 
        
        vol_flow_per_zone = vol_flow / num_zones; 
        flow_lpm_arr(i) = vol_flow_per_zone * 60000; 
        
        velocity = vol_flow_per_zone / cross_area_room;
        Re = (rho * velocity * d_in_room) / mu;
        re_arr(i) = Re; 

        if Re < 2300
            f = 64 / max(Re, 1e-5);
        elseif Re < 4000
            f = 0.3164 / (Re^0.25);  % Geçiş bölgesi
        else
            % Colebrook-White (Swamee-Jain yaklaşımı) — pürüzlülük dahil
            f = 0.25 / (log10(epsilon_room / (3.7 * d_in_room) + 5.74 / (Re^0.9)))^2;
        end
        delta_p_pascal = f * (len_per_zone / d_in_room) * (rho * velocity^2) / 2;
        p_drop_arr(i) = delta_p_pascal / 1000; 

        % 5. ECO-METRİKLER (Aktif alan bazlı)
        room_energy_kwh = ((q_total * active_room_area) / 1000 * hours) / cop;
        room_energy_arr(i) = room_energy_kwh;
        room_co2_arr(i) = room_energy_kwh * co2_factor;
    end

    % 6. ANA HAT VE POMPA HESABI
    t_pipe_main = 0.0034; 
    d_in_main = d_out_main - (2 * t_pipe_main);
    cross_area_main = pi * (d_in_main^2) / 4;
    main_velocity = total_vol_flow / cross_area_main;
    
    Re_main = (rho * main_velocity * d_in_main) / mu;
    % Ana hat: PEX-AL-PEX veya bakır bağımsız olarak epsilon_room kullan
    if Re_main < 2300
        f_main = 64 / max(Re_main, 1e-5);
    elseif Re_main < 4000
        f_main = 0.3164 / (Re_main^0.25);
    else
        f_main = 0.25 / (log10(epsilon_room / (3.7 * d_in_main) + 5.74 / (Re_main^0.9)))^2;
    end
    
    main_p_pascal = f_main * ((dist_main * 2) / d_in_main) * (rho * main_velocity^2) / 2;
    main_p_drop = main_p_pascal / 1000; 

    sys_max_pressure = max(p_drop_arr) + main_p_drop;
    sys_max_pressure_pa = sys_max_pressure * 1000;
    sys_pump_power = (total_vol_flow * sys_max_pressure_pa) / 0.6; 
    
    pump_energy_kwh = (sys_pump_power / 1000) * hours;
    sys_total_energy = sum(room_energy_arr) + pump_energy_kwh;
    sys_total_co2 = sys_total_energy * co2_factor;

    % YENİ: CO2 AZALTMA YÜZDESİ (Referans Değer 1.25 kg/kWh)
    reference_co2_factor = 1.25;
    sys_co2_reduction = (1 - (co2_factor / reference_co2_factor)) * 100;
    if sys_co2_reduction < 0
        sys_co2_reduction = 0;
    end
end