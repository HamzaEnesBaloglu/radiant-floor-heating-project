from flask import Flask, request, jsonify
from flask_cors import CORS
import matlab.engine
import os

app = Flask(__name__)
CORS(app)

print("MATLAB Motoru başlatılıyor... (Lütfen bekleyin)")
try:
    eng = matlab.engine.start_matlab()
    engine_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'engine'))
    eng.cd(engine_path)
    print(f"MATLAB hazır. Çalışma dizini: {engine_path}")
except Exception as e:
    print(f"MATLAB Engine başlatılamadı: {e}")

@app.route('/api/calculate', methods=['POST'])
def calculate():
    data = request.json
    
    # Global Sistem Verileri
    t_water = float(data.get('t_water', 40.0))
    t_below = float(data.get('t_below', 15.0))
    r_insulation = float(data.get('r_insulation', 0.85))
    dist_main = float(data.get('dist_main', 5.0))
    d_out_main = float(data.get('d_out_main', 0.025))
    
    # YENİ: MAKROKLİMA VE MİKROKLİMA
    base_temp = float(data.get('climate_zone', -5.0)) # Deniz seviyesi sıcaklığı
    altitude = float(data.get('altitude', 0.0))       # Rakım
    wind_factor = float(data.get('wind_factor', 1.0)) # Rüzgar çarpanı
    
    # Toroslar Mantığı: Her 100 metrede sıcaklık 0.65 derece düşer
    t_out_real = base_temp - (altitude * 0.0065)

    # ECO Parametreleri
    cop = float(data.get('cop', 3.5))
    hours = float(data.get('hours', 2000.0))
    co2_factor = float(data.get('co2_factor', 0.4))

    rooms = data.get('rooms', [])
    if not rooms:
        return jsonify({"status": "error", "message": "En az bir oda eklemelisiniz."}), 400

    # Oda Verileri
    t_room_list = [float(r['t_room']) for r in rooms]
    spacing_list = [float(r['spacing']) for r in rooms]
    r_cover_list = [float(r['r_cover']) for r in rooms]
    area_list = [float(r['room_area']) for r in rooms]
    dist_list = [float(r['dist_to_collector']) for r in rooms]
    
    ext_wall_len_list = [float(r['ext_wall_len']) for r in rooms]
    room_height_list = [float(r['room_height']) for r in rooms]
    window_area_list = [float(r['window_area']) for r in rooms]
    u_wall_list = [float(r['u_wall']) for r in rooms]
    u_window_list = [float(r['u_window']) for r in rooms]

    try:
        # MATLAB fonksiyonuna rüzgar faktörünü ve gerçek dış sıcaklığı yolluyoruz
        q_flux_arr, t_surf_arr, q_down_arr, q_total_arr, pipe_len_arr, p_drop_arr, room_energy_arr, room_co2_arr, q_loss_arr, sys_total_heat, sys_max_pressure, main_p_drop, sys_pump_power, sys_total_energy, sys_total_co2 = eng.floor_heating_model(
            t_water, t_below, r_insulation, dist_main, d_out_main, cop, hours, co2_factor, 
            t_out_real, wind_factor, # GÜNCELLENDİ
            matlab.double(t_room_list), matlab.double(spacing_list),
            matlab.double(r_cover_list), matlab.double(area_list), matlab.double(dist_list),
            matlab.double(ext_wall_len_list), matlab.double(room_height_list), matlab.double(window_area_list),
            matlab.double(u_wall_list), matlab.double(u_window_list),
            nargout=15
        )
        
        def to_list(matlab_val):
            if isinstance(matlab_val, float): return [matlab_val]
            return list(matlab_val[0])

        return jsonify({
            "status": "success",
            "calculated_t_out": t_out_real, # Arayüzde göstermek için geri yolluyoruz
            "q_flux": to_list(q_flux_arr),
            "t_surf": to_list(t_surf_arr),
            "q_down": to_list(q_down_arr),
            "q_total": to_list(q_total_arr),
            "pipe_len": to_list(pipe_len_arr),
            "p_drop": to_list(p_drop_arr),
            "room_energy": to_list(room_energy_arr),
            "room_co2": to_list(room_co2_arr),
            "q_loss": to_list(q_loss_arr), 
            "sys_total_heat": sys_total_heat,
            "sys_max_pressure": sys_max_pressure,
            "main_p_drop": main_p_drop,
            "sys_pump_power": sys_pump_power,
            "sys_total_energy": sys_total_energy,
            "sys_total_co2": sys_total_co2
        })
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    app.run(debug=True, port=5000)