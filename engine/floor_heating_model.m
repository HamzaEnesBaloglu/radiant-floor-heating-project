function [q_flux_arr, t_surf_arr, q_down_arr, q_total_arr, len_per_zone_arr, p_drop_arr, room_energy_arr, room_co2_arr, q_loss_arr, num_zones_arr, flow_lpm_arr, fin_eff_arr, re_arr, coverage_ratio_arr, surplus_watt_arr, t_dew_arr, rad_ratio_arr, sys_total_heat, sys_max_pressure, main_p_drop, sys_pump_power, sys_total_energy, sys_total_co2, sys_t_mean, sys_co2_reduction, e_building_arr, psi_r_arr, sys_psi_r, sys_eta_I, e_supply, m_param_arr] = floor_heating_model(t_water, t_below_arr, r_insulation, dist_main, d_out_main, cop, hours, co2_factor, t_out, wind_factor, rh, altitude, glycol_percent, ventilation_arr, active_area_arr, t_room_arr, spacing_arr, r_cover_arr, area_arr, dist_arr, ext_wall_len_arr, room_height_arr, window_area_arr, u_wall_arr, u_window_arr, pipe_material, layout_type_arr, heat_source, delta_T_water, u_ceiling_arr)
    % MULTI-ZONE HYDRAULIC, ECO & ACADEMIC THERMODYNAMICS SOLVER (v0.19.0)

    num_rooms          = length(t_room_arr);
    q_flux_arr         = zeros(1, num_rooms);
    t_surf_arr         = zeros(1, num_rooms);
    q_down_arr         = zeros(1, num_rooms);
    q_total_arr        = zeros(1, num_rooms);
    len_per_zone_arr   = zeros(1, num_rooms);
    p_drop_arr         = zeros(1, num_rooms);
    room_energy_arr    = zeros(1, num_rooms);
    room_co2_arr       = zeros(1, num_rooms);
    q_loss_arr         = zeros(1, num_rooms);
    num_zones_arr      = zeros(1, num_rooms);
    flow_lpm_arr       = zeros(1, num_rooms);
    fin_eff_arr        = zeros(1, num_rooms); 
    re_arr             = zeros(1, num_rooms);      
    coverage_ratio_arr = zeros(1, num_rooms);
    surplus_watt_arr   = zeros(1, num_rooms);
    
    % Dew Point and Radiant Ratio arrays
    t_dew_arr     = zeros(1, num_rooms);
    rad_ratio_arr = zeros(1, num_rooms);
    m_param_arr   = zeros(1, num_rooms);

    % Exergy arrays
    e_building_arr = zeros(1, num_rooms);
    psi_r_arr      = zeros(1, num_rooms);

    k_concrete = 1.4; t_concrete = 0.05;

    % EXERGY SUPPLY CALCULATION (based on heat source)
    % heat_source: 1=Heat Pump, 2=Natural Gas, 3=Electric Resistance, 4=Solar
    T0_K            = t_out + 273.15;
    T_water_K       = t_water + 273.15;

    switch heat_source
        case 1  % Heat Pump
            e_supply = 1 / cop;
        case 2  % Natural Gas Boiler (boiler efficiency arrives via the 'cop' variable from the UI)
            eta_boiler = cop;
            e_supply = max(0, (1 - T0_K / T_water_K) / eta_boiler);
        case 3  % Electric Resistance (equivalent to COP=1)
            e_supply = max(0, 1 - T0_K / T_water_K);
        case 4  % Solar
            % Solar exergy factor: Petela (1964) - T_sun ~ 5778 K
            T_sun = 5778;
            eta_solar = 0.15; % Typical panel efficiency
            e_supply = max(0, eta_solar * (1 - T0_K / T_sun));
        otherwise
            e_supply = 1 / cop;
    end

    r_concrete = t_concrete / k_concrete;
    
    % DYNAMIC WATER & GLYCOL PROPERTIES (empirical approximations)
    % 0% Glycol (pure water) -> rho: 992, cp: 4179, mu: 0.000653
    rho = 992 + (glycol_percent * 0.44); 
    cp = 4179 - (glycol_percent * 5.79);
    mu = 0.000653 * (1 + (glycol_percent * 0.04));
    
    t_mean_water = t_water - (delta_T_water / 2); 
    sys_t_mean = t_mean_water; 

    % PIPE MATERIAL TABLE: [d_out(m), t_pipe(m), k_pipe(W/mK), epsilon(m)]
    % 1=PEX-a, 2=PEX-AL-PEX, 3=PE-RT, 4=PE-Xa17
    pipe_table = [0.016, 0.002, 0.40,  0.000007;   % 1: PEX-a 16mm
                  0.016, 0.002, 0.45,  0.0000015;  % 2: PEX-AL-PEX 16mm
                  0.016, 0.002, 0.40,  0.000007;   % 3: PE-RT 16mm
                  0.017, 0.002, 0.38,  0.000007];   % 4: PE-Xa 17mm

    pm = max(1, min(4, round(pipe_material)));
    d_out_room   = pipe_table(pm, 1);
    t_pipe_room  = pipe_table(pm, 2);
    k_pipe       = pipe_table(pm, 3);
    epsilon_room = pipe_table(pm, 4);
    d_in_room  = d_out_room - (2 * t_pipe_room);
    cross_area_room = pi * (d_in_room^2) / 4;

    % FLOOR PATTERN TABLE (Koschenz & Lehmann 2000, Schnabel & Schlegel 1996)
    % layout_type: 1=Meander, 2=Spiral, 3=Double Meander
    % Columns: [length_factor, eta_layout]
    % length_factor : corner-allowance pipe length multiplier
    % eta_layout    : heat distribution uniformity coefficient
    layout_table = [1.00, 0.95;   % Meander
                    1.06, 1.00;   % Spiral
                    1.03, 0.97];  % Double Meander

    sys_total_heat = 0; 
    total_vol_flow = 0; 
    max_loop_length = 100; 
    
    % F1 Altitude correction
    p_ratio = (1 - 2.25577e-5 * altitude)^5.25588;
    F1 = sqrt(p_ratio);

    for i = 1:num_rooms
        t_room = t_room_arr(i);
        spacing = spacing_arr(i);
        r_cover = r_cover_arr(i);
        room_area = area_arr(i);
        dist_to_coll = dist_arr(i); 
        t_below = t_below_arr(i); 

        % Dew Point (Magnus formula)
        alpha = (17.625 * t_room) / (243.04 + t_room) + log(rh/100);
        t_dew = (243.04 * alpha) / (17.625 - alpha);
        t_dew_arr(i) = t_dew;

        % F2 (Active Area Ratio)
        F2 = active_area_arr(i) / 100;
        active_room_area = room_area * F2; 

        % 1. HEAT LOSS CALCULATION
        ext_wall_len = ext_wall_len_arr(i);
        room_height = room_height_arr(i);
        window_area = window_area_arr(i);
        u_wall = u_wall_arr(i);
        u_window = u_window_arr(i);

        a_wall_gross = ext_wall_len * room_height;
        a_wall_net = max(0, a_wall_gross - window_area);

        q_trans = (a_wall_net * u_wall * wind_factor + window_area * u_window * wind_factor) * (t_room - t_out);
        q_loss_ceiling = u_ceiling_arr(i) * room_area * wind_factor * (t_room - t_out);

        room_vol = room_area * room_height;
        q_vent = 0.34 * 0.5 * room_vol * (t_room - t_out);

        q_loss_watt = q_trans + max(0, q_loss_ceiling) + max(0, q_vent);
        q_loss_arr(i) = max(0, q_loss_watt); 

        % Dynamic heat transfer coefficients and F3 (hybrid ventilation)
        % ISO 11855-2 correction factor approach:
        % r_total is computed at standard conditions, F1 and F3 are applied to the result
        F3 = ventilation_arr(i);
        h_rad = 5.5;
        h_conv_std     = 5.3;                    % Standard condition (sea level, natural ventilation)
        h_total_std    = h_rad + h_conv_std;     % Standard total coefficient
        h_total_dynamic = h_rad + (5.3 * F1 * F3); % Actual condition (for radiant ratio)
        rad_ratio_arr(i) = (h_rad / h_total_dynamic) * 100;

        % 2. THERMAL CALCULATIONS AND FIN EFFICIENCY
        r_pipe = spacing * log(d_out_room / d_in_room) / (2 * pi * k_pipe); 
        r_up = r_pipe + r_concrete + r_cover;
        r_total = r_up + (1 / h_total_dynamic);
        u_surface = 1 / (r_cover + (1 / h_total_std)); % u_surface at standard condition
        m_param = sqrt(u_surface / (k_concrete * t_concrete));
        
        % FLOOR PATTERN - select layout per room
        lt = max(1, min(3, round(layout_type_arr(i))));
        length_factor = layout_table(lt, 1);
        eta_layout    = layout_table(lt, 2);

        % Koschenz & Lehmann (2000) Eq. 2.13 - asymmetric fin model
        L_fin = spacing / 2;
        if lt == 1  % Meander, asymmetric boundary condition
            mL  = m_param * L_fin;
            mL2 = m_param * (L_fin / 2);
            eta_symmetric  = tanh(mL) / mL;
            delta_t_ratio  = delta_T_water / (2 * max(t_mean_water - t_room, 0.1));
            eta_asymmetry  = 1 - delta_t_ratio * (tanh(mL2) / tanh(mL));
            fin_efficiency = eta_symmetric * eta_asymmetry;
        else
            % Spiral & Double Meander - symmetric fin analogy
            fin_efficiency = tanh(m_param * L_fin) / (m_param * L_fin);
        end

        fin_eff_arr(i) = fin_efficiency;
        m_param_arr(i) = m_param;

        q_flux = ((t_mean_water - t_room) / r_total) * fin_efficiency * eta_layout;

        q_flux_arr(i) = q_flux;
        
        t_surf_arr(i) = t_room + (q_flux / h_total_dynamic);

        % ROOM EXERGY DEMAND (Bejan 1996 - Carnot factor)
        % t_surf_arr(i) is computed above and used here
        T_surf_K          = t_surf_arr(i) + 273.15;
        e_building        = max(0, 1 - T0_K / T_surf_K);
        e_building_arr(i) = e_building;

        % ROOM psi_R
        if e_supply > 0
            psi_r_arr(i) = min(1, e_building / e_supply);
        else
            psi_r_arr(i) = 0;
        end
        
        q_down = (t_mean_water - t_below) / r_insulation; 
        q_down_arr(i) = q_down;
        q_total = q_flux + q_down; 
        q_total_arr(i) = q_total;

        total_heat_supplied_watt = q_flux * active_room_area;
        sys_total_heat = sys_total_heat + (q_total * active_room_area); 
        
        % 3. THERMAL JUDGE
        surplus_watt_arr(i) = total_heat_supplied_watt - max(0, q_loss_watt);
        if q_loss_watt > 0
            coverage_ratio_arr(i) = (total_heat_supplied_watt / q_loss_watt) * 100;
        else
            coverage_ratio_arr(i) = 100; 
        end

        % 4. ZONING AND FLOW RATE
        room_base_length = (active_room_area / spacing) * length_factor;
        num_zones = ceil(max(room_base_length, 1e-5) / max_loop_length);
        num_zones_arr(i) = num_zones;
        len_per_zone = (room_base_length / num_zones) + (2 * dist_to_coll);
        len_per_zone_arr(i) = len_per_zone;

        % Dynamic cp and rho come into play here:
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
            f = 0.3164 / (Re^0.25);  % Transitional region
        else
            % Colebrook-White (Swamee-Jain approximation) - roughness included
            f = 0.25 / (log10(epsilon_room / (3.7 * d_in_room) + 5.74 / (Re^0.9)))^2;
        end
        delta_p_pascal = f * (len_per_zone / d_in_room) * (rho * velocity^2) / 2;
        p_drop_arr(i) = delta_p_pascal / 1000; 

        % 5. ECO METRICS (active-area based)
        room_energy_kwh = (q_total * active_room_area / 1000 * hours) / cop;
        room_energy_arr(i) = room_energy_kwh;
        room_co2_arr(i) = room_energy_kwh * co2_factor;
    end

    % SYSTEM-WIDE EXERGY METRICS
    % Weighted average - weight: each room's heat flux x active area
    weights = q_flux_arr .* (area_arr .* (active_area_arr / 100));
    total_weight = sum(weights);

    if total_weight > 0
        sys_psi_r = sum(psi_r_arr .* weights) / total_weight;
    else
        sys_psi_r = 0;
    end

    % eta_I = (1/COP) x distribution efficiency (0.85 constant)
    eta_dist  = 0.85;
    sys_eta_I = cop * eta_dist;

    % 6. MAIN LINE AND PUMP CALCULATION
    t_pipe_main = 0.0034;
    d_in_main = d_out_main - (2 * t_pipe_main);
    cross_area_main = pi * (d_in_main^2) / 4;
    main_velocity = total_vol_flow / cross_area_main;
    
    Re_main = (rho * main_velocity * d_in_main) / mu;
    % Main line: use epsilon_room regardless of PEX-AL-PEX or copper
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

    % CO2 REDUCTION PERCENTAGE (reference: COP=0.9 natural gas system, factor=0.22 kg/kWh)
    % How much CO2 would we emit if the total heat demand were met with natural gas?
    ref_energy_kwh = (sys_total_heat / 1000 * hours) / 0.90;
    ref_total_co2 = ref_energy_kwh * 0.22;

    if ref_total_co2 > 0
        sys_co2_reduction = (1 - (sys_total_co2 / ref_total_co2)) * 100;
    else
        sys_co2_reduction = 0;
    end

    if sys_co2_reduction < 0
        sys_co2_reduction = 0;
    end
end