import os
import boto3

class Config:
    """Application configuration"""
    
    # Flask
    SECRET_KEY = os.environ.get('SECRET_KEY', 'dev-secret-key-change-in-prod')
    
    # Database
    DB_HOST = os.environ.get('DB_HOST', 'localhost')
    DB_PORT = os.environ.get('DB_PORT', '5432')
    DB_NAME = os.environ.get('DB_NAME', 'app_db')
    DB_USER = os.environ.get('DB_USER', 'postgres')
    
    # Database password from SSM Parameter Store
    @staticmethod
    def get_db_password():
        """Fetch DB password from SSM Parameter Store"""
        ssm_param = os.environ.get('DB_PASSWORD_SSM_PARAM')
        if not ssm_param:
            # Local development fallback
            return os.environ.get('DB_PASSWORD', 'devpassword')
        
        try:
            ssm = boto3.client('ssm', region_name='us-east-1')
            response = ssm.get_parameter(Name=ssm_param, WithDecryption=True)
            return response['Parameter']['Value']
        except Exception as e:
            print(f"Error fetching password from SSM: {e}")
            return None
    
    # Server
    HOST = '0.0.0.0'
    PORT = 8000