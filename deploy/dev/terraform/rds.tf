# RDS Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-rds-subnet-group"
  subnet_ids = [data.aws_subnet.private_1.id, data.aws_subnet.private_2.id]

  tags = {
    Name = "${var.project_name}-rds-subnet-group"
  }
}

# RDS PostgreSQL Instance
resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-postgres"
  
  # Engine configuration
  engine         = "postgres"
  engine_version = "16.4"
  instance_class = "db.t3.micro"
  
  # Storage configuration
  allocated_storage     = 20
  storage_type         = "gp2"
  storage_encrypted    = true
  
  # Database configuration
  db_name  = "authentik_dev"
  username = "authentik"
  password = random_password.rds_password.result
  
  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  
  # Backup configuration
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  # High availability
  multi_az = false
  
  # Deletion configuration
  deletion_protection = false
  skip_final_snapshot = true
  
  tags = {
    Name = "${var.project_name}-postgres"
  }

  lifecycle {
    ignore_changes = [
      engine_version
    ]
  }
}
