from flask import Flask, request, jsonify
from flask_cors import CORS
import matlab.engine
import os

# Version v0.19.0

app = Flask(__name__)
CORS(app)

print("Starting MATLAB Engine... (please wait)")
try:
    eng = matlab.engine.start_matlab()
    engine_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'engine'))
    eng.cd(engine_path)
    print(f"MATLAB ready. Working directory: {engine_path}")
except Exception as e:
    print(f"Failed to start MATLAB Engine: {e}")

# --- INPUT VALIDATION HELPER ---
# NOTE: Backend validation messages are English-only on purpose. The frontend runs
# the same checks first (with full TR/EN i18n), so these only surface on direct API calls.
def validate_inputs(data):
    errors = []

    def rng(val, mn, mx, label):
        try:
            v = float(val)
            if v < mn or v > mx:
                errors.append(f"{label}: value {v} is outside the range [{mn}, {mx}].")
        except (TypeError, ValueError):
            errors.append(f"{label}: not a valid number.")

    rng(data.get('t_water'),        25,   60,   'Boiler water temperature (C)')
    rng(data.get('r_insulation'),   0.5,  5.0,  'Sub-insulation R-value')
    rng(data.get('dist_main'),      1,    50,   'Boiler->Manifold distance (m)')
    rng(data.get('altitude'),       0,    3000, 'Altitude (m)')
    rng(data.get('rh'),             10,   100,  'Relative humidity (%)')
    rng(data.get('hours'),          500,  8760, 'Annual operating hours')
    rng(data.get('co2_factor'),     0.05, 2.0,  'CO2 factor (kg/kWh)')
    rng(data.get('pipe_material'),  1,    4,    'Pipe material (1-4)')
    rng(data.get('delta_T_water'),  2,    20,   'Water temperature difference (dT) (C)')

    heat_source = int(float(data.get('heat_source', 1)))
    if heat_source == 1:
        rng(data.get('cop'), 1.0, 7.0, 'COP (Heat Pump)')
    else:
        rng(data.get('cop'), 0.1, 1.0, 'Boiler/System efficiency')

    rooms = data.get('rooms', [])
    for i, room in enumerate(rooms):
        name = f"Room {i+1}"
        rng(room.get('room_area'),         2,    200,  f'{name} - Gross area (m2)')
        rng(room.get('t_room'),            15,   30,   f'{name} - Indoor temperature (C)')
        rng(room.get('spacing'),           0.05, 0.30, f'{name} - Pipe spacing (m)')
        rng(room.get('dist_to_collector'), 1, 30,      f'{name} - Distance to manifold (m)')
        rng(room.get('active_area'),       10,   100,  f'{name} - Active area (%)')
        rng(room.get('ext_wall_len'),      0,    30,   f'{name} - Facade length (m)')
        rng(room.get('room_height'),       2.2,  5.0,  f'{name} - Room height (m)')
        rng(room.get('window_area'),       0,    50,   f'{name} - Window area (m2)')

        # Cross-check: window area > gross wall area
        try:
            gross_wall = float(room.get('ext_wall_len', 0)) * float(room.get('room_height', 0))
            window = float(room.get('window_area', 0))
            if gross_wall > 0 and window > gross_wall:
                errors.append(f"{name} - Window area ({window}m2) cannot exceed gross wall area ({gross_wall:.1f}m2).")
        except (TypeError, ValueError):
            pass

        # Cross-check: indoor temperature >= boiler return water
        try:
            t_water = float(data.get('t_water', 999))
            delta_t = float(data.get('delta_T_water', 5))
            t_return = t_water - delta_t
            if float(room.get('t_room', 0)) >= t_return:
                errors.append(f"{name} - Return water temperature ({t_return}C) cannot be lower than or equal to the indoor temperature (heating impossible).")
        except (TypeError, ValueError):
            pass

    return errors

@app.route('/api/calculate', methods=['POST'])
def calculate():
    data = request.json
    
    # Backend validation
    validation_errors = validate_inputs(data)
    if validation_errors:
        return jsonify({"status": "error", "message": " | ".join(validation_errors)}), 400


    t_water =       float(data.get('t_water', 40.0))
    r_insulation =  float(data.get('r_insulation', 0.85))
    dist_main =     float(data.get('dist_main', 5.0))
    d_out_main =    float(data.get('d_out_main', 0.025))
    
    base_temp =     float(data.get('climate_zone', -5.0))
    altitude =      float(data.get('altitude', 0.0))
    wind_factor =   float(data.get('wind_factor', 1.0))
    t_out_real =    base_temp - (altitude * 0.0065)
    
    rh =            float(data.get('rh', 50.0))
    glycol =        float(data.get('glycol', 0.0))
    pipe_material = float(data.get('pipe_material', 1.0))

    cop =           float(data.get('cop', 3.5))
    hours =         float(data.get('hours', 2000.0))
    co2_factor =    float(data.get('co2_factor', 0.4))
    heat_source =   float(data.get('heat_source', 1.0))
    delta_T_water = float(data.get('delta_T_water', 5.0))

    rooms = data.get('rooms', [])
    if not rooms:
        return jsonify({"status": "error", "message": "You must add at least one room."}), 400

    t_room_list       = [float(r['t_room']) for r in rooms]
    spacing_list      = [float(r['spacing']) for r in rooms]
    r_cover_list      = [float(r['r_cover']) for r in rooms]
    area_list         = [float(r['room_area']) for r in rooms]
    dist_list         = [float(r['dist_to_collector']) for r in rooms]
    t_below_list      = [float(r['t_below']) for r in rooms] 
    
    ventilation_list  = [float(r['ventilation']) for r in rooms]
    active_area_list  = [float(r['active_area']) for r in rooms]
    
    ext_wall_len_list = [float(r['ext_wall_len']) for r in rooms]
    room_height_list  = [float(r['room_height']) for r in rooms]
    window_area_list  = [float(r['window_area']) for r in rooms]
    u_wall_list       = [float(r['u_wall']) for r in rooms]
    u_window_list     = [float(r['u_window']) for r in rooms]
    layout_type_list  = [float(r.get('layout_type', 1.0)) for r in rooms]
    u_ceiling_list    = [float(r.get('u_ceiling', 0.0)) for r in rooms]

    try:
        q_flux_arr, t_surf_arr, q_down_arr, q_total_arr, len_per_zone_arr, p_drop_arr, room_energy_arr, room_co2_arr, q_loss_arr, num_zones_arr, flow_lpm_arr, fin_eff_arr, re_arr, coverage_ratio_arr, surplus_watt_arr, t_dew_arr, rad_ratio_arr, sys_total_heat, sys_max_pressure, main_p_drop, sys_pump_power, sys_total_energy, sys_total_co2, sys_t_mean, sys_co2_reduction, e_building_arr, psi_r_arr, sys_psi_r, sys_eta_I, e_supply, m_param_arr = eng.floor_heating_model(
            t_water, matlab.double(t_below_list), r_insulation, dist_main, d_out_main, cop, hours, co2_factor, 
            t_out_real, wind_factor, rh, altitude, glycol, matlab.double(ventilation_list), matlab.double(active_area_list), 
            matlab.double(t_room_list), matlab.double(spacing_list),
            matlab.double(r_cover_list), matlab.double(area_list), matlab.double(dist_list),
            matlab.double(ext_wall_len_list), matlab.double(room_height_list), matlab.double(window_area_list),
            matlab.double(u_wall_list), matlab.double(u_window_list), pipe_material,
            matlab.double(layout_type_list), heat_source, delta_T_water,
            matlab.double(u_ceiling_list),
            nargout=31
        )
        
        def to_list(matlab_val):
            if isinstance(matlab_val, float): return [matlab_val]
            return list(matlab_val[0])

        return jsonify({
            "status": "success",
            "calculated_t_out":  t_out_real,
            "q_flux":            to_list(q_flux_arr),
            "t_surf":            to_list(t_surf_arr),
            "q_down":            to_list(q_down_arr),
            "q_total":           to_list(q_total_arr),
            "len_per_zone":      to_list(len_per_zone_arr), 
            "p_drop":            to_list(p_drop_arr),
            "room_energy":       to_list(room_energy_arr),
            "room_co2":          to_list(room_co2_arr),
            "q_loss":            to_list(q_loss_arr), 
            "num_zones":         to_list(num_zones_arr), 
            "flow_lpm":          to_list(flow_lpm_arr), 
            "fin_eff":           to_list(fin_eff_arr), 
            "reynolds":          to_list(re_arr),     
            "coverage_ratio":    to_list(coverage_ratio_arr), 
            "surplus_watt":      to_list(surplus_watt_arr),
            "t_dew":             to_list(t_dew_arr),         
            "rad_ratio":         to_list(rad_ratio_arr), 
            "sys_total_heat":    sys_total_heat,
            "sys_max_pressure":  sys_max_pressure,
            "main_p_drop":       main_p_drop,
            "sys_pump_power":    sys_pump_power,
            "sys_total_energy":  sys_total_energy,
            "sys_total_co2":     sys_total_co2,
            "sys_t_mean":        sys_t_mean,
            "sys_co2_reduction": sys_co2_reduction,
            "e_building":        to_list(e_building_arr),
            "psi_r":             to_list(psi_r_arr),
            "sys_psi_r":         sys_psi_r,
            "sys_eta_I":         sys_eta_I,
            "e_supply":          e_supply,
            "m_param":           to_list(m_param_arr)
        })
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    app.run(debug=True, port=5000)