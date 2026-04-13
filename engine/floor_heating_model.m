function [q_flux_arr, t_surf_arr, q_down_arr, q_total_arr, pipe_len_arr, p_drop_arr, room_energy_arr, room_co2_arr, sys_total_heat, sys_max_pressure, main_p_drop, sys_pump_power, sys_total_energy, sys_total_co2] = floor_heating_model(t_water, t_below, r_insulation, dist_main, d_out_main, cop, hours, co2_factor, t_room_arr, spacing_arr, r_cover_arr, area_arr, dist_arr)
    % MULTI-ZONE HYDRAULIC & GREEN BUILDING ECO-SOLVER (V0.6.0)

    num_rooms = length(t_room_arr);
    q_flux_arr = zeros(1, num_rooms);
    t_surf_arr = zeros(1, num_rooms);
    q_down_arr = zeros(1, num_rooms);
    q_total_arr = zeros(1, num_rooms);
    pipe_len_arr = zeros(1, num_rooms);
    p_drop_arr = zeros(1, num_rooms);
    room_energy_arr = zeros(1, num_rooms);
    room_co2_arr = zeros(1, num_rooms);

    % Fiziksel Sabitler
    h_conv_rad = 10.8; k_concrete = 1.4; t_concrete = 0.05;
    r_concrete = t_concrete / k_concrete; 
    rho = 992; cp = 4179; mu = 0.000653; delta_T_water = 5; 
    
    d_out_room = 0.016; t_pipe_room = 0.002; 
    d_in_room = d_out_room - (2 * t_pipe_room);
    cross_area_room = pi * (d_in_room^2) / 4;

    sys_total_heat = 0; 
    total_vol_flow = 0; % Pompa gücü için toplam debi (m^3/s)

    for i = 1:num_rooms
        t_room = t_room_arr(i);
        spacing = spacing_arr(i);
        r_cover = r_cover_arr(i);
        room_area = area_arr(i);
        dist_to_coll = dist_arr(i); 

        % Termal Hesaplar
        r_up = r_concrete + r_cover;
        r_total = r_up + (1 / h_conv_rad);
        u_surface = 1 / (r_cover + (1 / h_conv_rad));
        m_param = sqrt(u_surface / (k_concrete * t_concrete));
        L = spacing / 2;
        fin_efficiency = tanh(m_param * L) / (m_param * L);

        q_flux = ((t_water - t_room) / r_total) * fin_efficiency;
        q_flux_arr(i) = q_flux;
        t_surf_arr(i) = t_room + (q_flux / h_conv_rad);
        q_down = (t_water - t_below) / r_insulation;
        q_down_arr(i) = q_down;
        q_total = q_flux + q_down;
        q_total_arr(i) = q_total;

        total_pipe_length = (room_area / spacing) + (2 * dist_to_coll);
        pipe_len_arr(i) = total_pipe_length;

        total_heat_watt = q_total * room_area;
        sys_total_heat = sys_total_heat + total_heat_watt;
        
        mass_flow = total_heat_watt / (cp * delta_T_water); 
        vol_flow = mass_flow / rho; 
        total_vol_flow = total_vol_flow + vol_flow; % Evin toplam debisine ekle
        
        velocity = vol_flow / cross_area_room;
        Re = (rho * velocity * d_in_room) / mu;
        if Re < 2300
            f = 64 / max(Re, 1e-5);
        else
            f = 0.3164 / (Re^0.25);
        end
        delta_p_pascal = f * (total_pipe_length / d_in_room) * (rho * velocity^2) / 2;
        p_drop_arr(i) = delta_p_pascal / 1000; 

        % ECO-METRİKLER (Lokal - Oda Bazında)
        % Odanın Yıllık Tüketimi (kWh) = (Isı Yükü kW * Saat) / COP
        room_energy_kwh = (total_heat_watt / 1000 * hours) / cop;
        room_energy_arr(i) = room_energy_kwh;
        % Odanın Yıllık CO2 Salınımı (kg)
        room_co2_arr(i) = room_energy_kwh * co2_factor;
    end

    % ANA HAT VE POMPA HESABI
    t_pipe_main = 0.0034; 
    d_in_main = d_out_main - (2 * t_pipe_main);
    cross_area_main = pi * (d_in_main^2) / 4;
    main_velocity = total_vol_flow / cross_area_main;
    
    Re_main = (rho * main_velocity * d_in_main) / mu;
    if Re_main < 2300
        f_main = 64 / max(Re_main, 1e-5);
    else
        f_main = 0.3164 / (Re_main^0.25);
    end
    
    main_p_pascal = f_main * ((dist_main * 2) / d_in_main) * (rho * main_velocity^2) / 2;
    main_p_drop = main_p_pascal / 1000; 

    sys_max_pressure = max(p_drop_arr) + main_p_drop;

    % ECO-METRİKLER (Global - Tüm Sistem)
    % Pompa Gücü (Watt) = (Debi * Basınç Pa) / Verim(0.6)
    sys_max_pressure_pa = sys_max_pressure * 1000;
    sys_pump_power = (total_vol_flow * sys_max_pressure_pa) / 0.6; 
    
    % Evin Toplam Yıllık Tüketimi (Isıtma + Pompanın Elektriği)
    pump_energy_kwh = (sys_pump_power / 1000) * hours;
    sys_total_energy = sum(room_energy_arr) + pump_energy_kwh;
    
    % Evin Toplam Karbon Ayak İzi
    sys_total_co2 = sys_total_energy * co2_factor;
end