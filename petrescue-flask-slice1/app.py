from flask import Flask, jsonify

import domain_adoption.models as adoption_models
import domain_medical.models as medical_models
import domain_shelter.models as shelter_models
from database import engine, SessionLocal
from domain_adoption.routes import adoption_bp
from domain_medical.routes import medical_bp
from domain_shelter.routes import shelter_bp
from toggles import s1_optimized, s2_optimized, s3_optimized, s4_optimized, s5_optimized

app = Flask(__name__)

medical_models.Base.metadata.create_all(bind=engine)
adoption_models.Base.metadata.create_all(bind=engine)
shelter_models.Base.metadata.create_all(bind=engine)

app.register_blueprint(shelter_bp)
app.register_blueprint(adoption_bp)
app.register_blueprint(medical_bp)


@app.teardown_appcontext
def shutdown_session(exception=None):
    SessionLocal.remove()

@app.route('/health', methods=['GET'])
def get_status():
    return jsonify({
        "status": "ok",
        "toggles": {
            "S1_Optimized": s1_optimized(),
            "S2_Optimized": s2_optimized(),
            "S3_Optimized": s3_optimized(),
            "S4_Optimized": s4_optimized(),
            "S5_Optimized": s5_optimized(),
        }
    }), 200


if __name__ == '__main__':
    app.run()
