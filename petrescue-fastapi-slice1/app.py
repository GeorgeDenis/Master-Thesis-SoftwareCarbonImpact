from flask import Flask

import domain_adoption.models as adoption_models
import domain_medical.models as medical_models
import domain_shelter.models as shelter_models
from database import engine, SessionLocal
from domain_adoption.routes import adoption_bp
from domain_medical.routes import medical_bp
from domain_shelter.routes import shelter_bp
from tracker_router import tracker_bp

app = Flask(__name__)

medical_models.Base.metadata.create_all(bind=engine)
adoption_models.Base.metadata.create_all(bind=engine)
shelter_models.Base.metadata.create_all(bind=engine)

app.register_blueprint(shelter_bp)
app.register_blueprint(adoption_bp)
app.register_blueprint(medical_bp)
app.register_blueprint(tracker_bp)


@app.teardown_appcontext
def shutdown_session(exception=None):
    SessionLocal.remove()

@app.route('/health', methods=['GET'])
def get_status():
    return {"status": "ok"}, 200


if __name__ == '__main__':
    app.run()
