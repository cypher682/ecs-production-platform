# Random suffix for unique DB identifier
resource "random_id" "db_suffix" {
  byte_length = 4
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier        = "${var.project_name}-db-${random_id.db_suffix.hex}"
  engine            = "postgres"
  engine_version    = "15.12"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"
  
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 5432
  
  # Network
  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = [var.rds_security_group_id]
  publicly_accessible    = false
  
  # Backup & Maintenance
  backup_retention_period   = 7
  backup_window            = "03:00-04:00"  # UTC
  maintenance_window       = "mon:04:00-mon:05:00"  # UTC
  skip_final_snapshot      = true  # For testing - set to false in production
  delete_automated_backups = true
  
  # Free tier optimization
  multi_az               = false  # Single-AZ for free tier
  storage_encrypted      = true
  deletion_protection    = false  # Allow Terraform destroy
  
  # Performance Insights (optional, free for 7 days retention)
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  
  tags = {
    Name = "${var.project_name}-database"
  }
}