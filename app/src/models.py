import psycopg2
from psycopg2.extras import RealDictCursor
from config import Config

class Database:
    """Database connection manager"""
    
    def __init__(self):
        self.conn = None
    
    def connect(self):
        """Establish database connection"""
        try:
            password = Config.get_db_password()
            if not password:
                raise Exception("Database password not available")
            
            self.conn = psycopg2.connect(
                host=Config.DB_HOST,
                port=Config.DB_PORT,
                dbname=Config.DB_NAME,
                user=Config.DB_USER,
                password=password,
                cursor_factory=RealDictCursor,
                connect_timeout=5
            )
            return True
        except Exception as e:
            print(f"Database connection error: {e}")
            return False
    
    def close(self):
        """Close database connection"""
        if self.conn:
            self.conn.close()
    
    def create_tables(self):
        """Create application tables if they don't exist"""
        if not self.conn:
            return False
        
        try:
            cursor = self.conn.cursor()
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS items (
                    id SERIAL PRIMARY KEY,
                    name VARCHAR(255) NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            self.conn.commit()
            cursor.close()
            return True
        except Exception as e:
            print(f"Error creating tables: {e}")
            return False
    
    def get_version(self):
        """Get PostgreSQL version"""
        if not self.conn:
            return None
        
        try:
            cursor = self.conn.cursor()
            cursor.execute("SELECT version()")
            version = cursor.fetchone()
            cursor.close()
            return version['version'] if version else None
        except Exception as e:
            print(f"Error getting version: {e}")
            return None
    
    def insert_item(self, name):
        """Insert a new item"""
        if not self.conn:
            return None
        
        try:
            cursor = self.conn.cursor()
            cursor.execute(
                "INSERT INTO items (name) VALUES (%s) RETURNING id, name, created_at",
                (name,)
            )
            item = cursor.fetchone()
            self.conn.commit()
            cursor.close()
            return dict(item) if item else None
        except Exception as e:
            print(f"Error inserting item: {e}")
            self.conn.rollback()
            return None
    
    def get_all_items(self):
        """Get all items"""
        if not self.conn:
            return []
        
        try:
            cursor = self.conn.cursor()
            cursor.execute("SELECT id, name, created_at FROM items ORDER BY created_at DESC")
            items = cursor.fetchall()
            cursor.close()
            return [dict(item) for item in items]
        except Exception as e:
            print(f"Error fetching items: {e}")
            return []