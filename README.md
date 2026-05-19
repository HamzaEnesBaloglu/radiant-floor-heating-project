# Radiant Floor Heating Solver

A web-based, advanced thermodynamic and exergy simulator for radiant floor heating systems. This project bridges a custom-built MATLAB mathematical engine with a Python (Flask) backend and a highly interactive HTML/JS frontend to provide real-time thermal, hydraulic, and ecological analysis for multi-zone heating projects.

## Features

* Advanced Thermodynamics: Calculates surface temperatures, heat fluxes, and heat losses using dynamic physical properties of water and glycol mixtures.
* Exergy & Eco-Metrics: Integrates Bejan's exergy demand models and evaluates the system's environmental impact (CO2 footprint, COP, annual energy consumption).
* Multi-Zone Hydraulic Analysis: Computes mass flow rates, Reynolds numbers, flow regimes (Laminar/Transitional/Turbulent), and dynamic pressure drops (kPa) using Colebrook-White and Swamee-Jain approximations.
* EN 1264 Compliance & Dew Point Risk: Automatically checks surface temperatures against EN 1264 standards (e.g., max 29°C for living areas) and calculates Magnus formula dew points to warn against condensation.
* Interactive Visualizations: Generates real-time vertical temperature gradients (from water to room air) and horizontal surface temperature ripple charts.

## Architecture

The simulator operates on a 3-tier architecture:
1. Frontend (UI): Vanilla HTML, CSS, and JavaScript. Provides an interactive dashboard for site data, architectural parameters, and dynamic charts.
2. Backend: Python with Flask. Serves as the API bridge (/api/calculate) and handles cross-origin requests (CORS).
3. Engine: MATLAB. Executes the heavy floor_heating_model.m script to process arrays of room data and returns structural, thermal, and hydraulic metrics.

## Prerequisites

To run this project locally, you must have the following software installed:
* MATLAB: A licensed installation of MATLAB (R2024a or newer is recommended for Python 3.12 support).
* Python 3.12: Ensure Python 3.12 is installed and added to your system PATH. 
* Git (Optional): For cloning the repository.

## Installation and Usage Guide

Follow these steps carefully to set up the environment using your Command Prompt (CMD).

1. Clone the Repository:
   Open your Command Prompt (CMD) and clone the project:
   ```cmd
   git clone [https://github.com/your-username/radiant-floor-heating-project.git](https://github.com/your-username/radiant-floor-heating-project.git)
   cd radiant-floor-heating-project


2. Set Up Python Environment (Optional but recommended):
Create a virtual environment to keep dependencies clean:
python -m venv venv
venv\Scripts\activate

3. Install MATLAB Engine for Python:
The backend relies on the official MATLAB Engine API to execute the .m scripts. Since you are using Python 3.12, install the engine via PyPI:
python -m pip install matlabengine
(Note: The matlabengine package requires your MATLAB installation to be present on your system. If you encounter issues, ensure your MATLAB version officially supports Python 3.12, e.g., MATLAB R2024a).

4. Install Python Dependencies:
Install Flask and Flask-CORS which are required by the backend:
pip install Flask flask-cors

5. Start the Backend Server:
Ensure you are in the root directory of the project and run:
python backend\app.py

You should see a message indicating that the MATLAB Engine is starting, followed by "MATLAB hazır." (MATLAB is ready), and the Flask server will start on http://127.0.0.1:5000.

6. Open the Frontend UI:
Leave the CMD window open and running. Open your preferred web browser and navigate to the local UI file (e.g., file:///C:/path/to/your/radiant-floor-heating-project/ui/index.html) or double-click the index.html file in your file explorer.

7. Run a Simulation:
Adjust the environmental, boiler, and room parameters on the web interface and click "Tüm Sistemi Analiz Et" (Analyze Entire System) to see the thermodynamic dashboard and charts.

License
This project is licensed under the GNU Affero General Public License v3.0 (AGPL-3.0) - see the LICENSE file for details.
