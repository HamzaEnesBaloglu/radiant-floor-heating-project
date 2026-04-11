from flask import Flask, request, jsonify
from flask_cors import CORS
import matlab.engine
import os

app = Flask(__name__)
CORS(app) # Frontend'in API'ye erişimine izin verir

# MATLAB Motorunu Başlat (Server kalkarken 1 kez çalışır)
print("MATLAB Motoru başlatılıyor... (Lütfen bekleyin)")
try:
    eng = matlab.engine.start_matlab()
    # MATLAB'ın çalışma dizinini 'engine' klasörüne ayarla
    engine_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'engine'))
    eng.cd(engine_path)
    print(f"MATLAB hazır. Çalışma dizini: {engine_path}")
except Exception as e:
    print(f"MATLAB Engine başlatılamadı: {e}")

@app.route('/api/calculate', methods=['POST'])
def calculate():
    data = request.json
    
    # HTML'den gelen verileri al
    t_room = float(data.get('t_room', 20.0))
    t_water = float(data.get('t_water', 40.0))
    spacing = float(data.get('spacing', 0.15))
    r_cover = float(data.get('r_cover', 0.05))

    # MATLAB fonksiyonunu çağır
    # thermal_solver(T_room, T_water, spacing, R_cover)
    # MATLAB'dan dönen veriler: [q_flux, t_surface, x_array, ripple_array]
    try:
        q_flux, t_surf, x_vals, t_ripple = eng.floor_heating_model(t_room, t_water, spacing, r_cover, nargout=4)
        
        # MATLAB listelerini Python listelerine çevir
        x_vals_list = [x[0] for x in x_vals]
        t_ripple_list = [t[0] for t in t_ripple]

        return jsonify({
            "status": "success",
            "q_flux": q_flux,
            "t_surface": t_surf,
            "x_vals": x_vals_list,
            "t_ripple": t_ripple_list
        })
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    print("Flask Sunucusu http://127.0.0.1:5000 adresinde çalışıyor.")
    app.run(debug=True, port=5000)