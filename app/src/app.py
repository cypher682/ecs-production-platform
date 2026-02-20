from flask import Flask, jsonify, request
from models import Database
import os

app = Flask(__name__)
app.config.from_object('config.Config')

# Initialize database connection (lazy)
db = None

def get_db():
    """Get database connection (singleton pattern)"""
    global db
    if db is None:
        db = Database()
        if db.connect():
            db.create_tables()
    return db

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint for ALB target group"""
    return jsonify({
        'status': 'healthy',
        'service': 'flask-app',
        'version': '2.0.0',
        'deployment': 'green'
    }), 200

@app.route('/db-check', methods=['GET'])
def db_check():
    """Database connectivity check"""
    database = get_db()
    
    if not database or not database.conn:
        return jsonify({
            'status': 'error',
            'message': 'Database connection failed'
        }), 503
    
    version = database.get_version()
    
    if version:
        return jsonify({
            'status': 'connected',
            'database': 'postgresql',
            'version': version
        }), 200
    else:
        return jsonify({
            'status': 'error',
            'message': 'Could not query database'
        }), 503

@app.route('/items', methods=['GET'])
def get_items():
    """Get all items"""
    database = get_db()
    
    if not database or not database.conn:
        return jsonify({'error': 'Database not available'}), 503
    
    items = database.get_all_items()
    return jsonify({
        'count': len(items),
        'items': items
    }), 200

@app.route('/items', methods=['POST'])
def create_item():
    """Create a new item"""
    database = get_db()
    
    if not database or not database.conn:
        return jsonify({'error': 'Database not available'}), 503
    
    data = request.get_json()
    
    if not data or 'name' not in data:
        return jsonify({'error': 'Name is required'}), 400
    
    item = database.insert_item(data['name'])
    
    if item:
        return jsonify({
            'status': 'created',
            'item': item
        }), 201
    else:
        return jsonify({'error': 'Failed to create item'}), 500

@app.route('/', methods=['GET'])
def root():
    """Root endpoint"""
    return jsonify({
        'message': 'ECS Production Platform API',
        'version': '2.0.0',
        'deployment': 'GREEN DEPLOYMENT',
        'endpoints': {
            'health': '/health',
            'db_check': '/db-check',
            'items': '/items (GET, POST)'
        },
        'features': [
            'Blue-Green Deployment Tested',
            'Zero Downtime Switching',
            'Automatic Rollback on Failure'
        ]
    }), 200

if __name__ == '__main__':
    # This is for local development only
    # In production, use gunicorn
    app.run(host='0.0.0.0', port=8000, debug=False)