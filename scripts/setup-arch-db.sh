#!/bin/bash

# PostgreSQL Setup Script for Arch Linux WSL
# This script installs and configures PostgreSQL for the logistics website

set -e

echo "🐘 Setting up PostgreSQL on Arch Linux..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Generate random password
generate_password() {
    tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c 16
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_warning "Running as root. This is fine for WSL environments."
else
   print_error "This script requires root privileges. Please run with sudo."
   exit 1
fi

# Generate secure passwords
DB_PASSWORD=$(generate_password)
ADMIN_PASSWORD=$(generate_password)
NEXTAUTH_SECRET=$(openssl rand -base64 32 2>/dev/null || date +%s | sha256sum | base64 | head -c 32)

print_status "Generated secure passwords for database and admin user"

# Update system packages
print_status "Updating system packages..."
pacman -Syu --noconfirm

# Install PostgreSQL
print_status "Installing PostgreSQL..."
pacman -S --noconfirm postgresql

# Initialize database cluster if it doesn't exist
if [ ! -d "/var/lib/postgres/data" ]; then
    print_status "Initializing PostgreSQL database cluster..."
    mkdir -p /var/lib/postgres/data
    chown -R postgres:postgres /var/lib/postgres
    sudo -u postgres initdb -D /var/lib/postgres/data
else
    print_warning "Database cluster already exists at /var/lib/postgres/data"
fi

# Enable and start PostgreSQL service
print_status "Enabling and starting PostgreSQL service..."
systemctl enable postgresql
systemctl start postgresql

# Wait for PostgreSQL to start
print_status "Waiting for PostgreSQL to start..."
for i in {1..10}; do
    if systemctl is-active --quiet postgresql; then
        break
    fi
    sleep 2
    if [ $i -eq 10 ]; then
        print_error "PostgreSQL failed to start"
        systemctl status postgresql
        exit 1
    fi
done

# Create database and user using sudo -u postgres
print_status "Creating database and user..."

# Create user if not exists
sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='logistics_user'" | grep -q 1 || \
sudo -u postgres psql -c "CREATE USER logistics_user WITH PASSWORD '${DB_PASSWORD}';"

# Create database if not exists
sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='logistics_db'" | grep -q 1 || \
sudo -u postgres psql -c "CREATE DATABASE logistics_db;"

# Grant privileges
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE logistics_db TO logistics_user;"

# Connect to the database and grant schema privileges
sudo -u postgres psql -d logistics_db -c "
GRANT ALL ON SCHEMA public TO logistics_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO logistics_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO logistics_user;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO logistics_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO logistics_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO logistics_user;
"

print_success "PostgreSQL setup completed!"

# Test connection
print_status "Testing database connection..."
if PGPASSWORD="${DB_PASSWORD}" psql -h localhost -U logistics_user -d logistics_db -c "SELECT version();" > /dev/null 2>&1; then
    print_success "Database connection test passed!"
else
    print_error "Database connection test failed!"
    exit 1
fi

# Create .env file
print_status "Creating .env file..."
cat > .env << EOF
# PostgreSQL Database Configuration
DATABASE_URL="postgresql://logistics_user:${DB_PASSWORD}@localhost:5432/logistics_db"

# Next.js Configuration
NEXTAUTH_SECRET="${NEXTAUTH_SECRET}"
NEXTAUTH_URL="http://localhost:3000"

# Admin Configuration
ADMIN_EMAIL="admin@blacksea-star.com"
ADMIN_PASSWORD="${ADMIN_PASSWORD}"

# API Configuration
API_BASE_URL="http://localhost:3000/api"
EOF

# Set secure permissions for .env file
chmod 600 .env

print_success ".env file created with secure permissions!"

# Create database management scripts
print_status "Creating database management scripts..."

# db-start script
cat > /usr/local/bin/db-start.sh << 'EOF'
#!/bin/bash
systemctl start postgresql
echo "PostgreSQL started"
EOF

# db-stop script
cat > /usr/local/bin/db-stop.sh << 'EOF'
#!/bin/bash
systemctl stop postgresql
echo "PostgreSQL stopped"
EOF

# db-restart script
cat > /usr/local/bin/db-restart.sh << 'EOF'
#!/bin/bash
systemctl restart postgresql
echo "PostgreSQL restarted"
EOF

# db-status script
cat > /usr/local/bin/db-status.sh << 'EOF'
#!/bin/bash
systemctl status postgresql
EOF

# Make scripts executable
chmod +x /usr/local/bin/db-*.sh

print_success "Database management scripts created!"

# Display connection information
echo ""
print_success "🎉 PostgreSQL setup completed successfully!"
echo ""
echo "📋 Database Connection Details:"
echo "   Host: localhost"
echo "   Port: 5432"
echo "   Database: logistics_db"
echo "   Username: logistics_user"
echo "   Password: ${DB_PASSWORD}"
echo ""
echo "🔐 Admin Login Details:"
echo "   Email: admin@blacksea-star.com"
echo "   Password: ${ADMIN_PASSWORD}"
echo ""
echo "🔧 Available Commands:"
echo "   db-start.sh     # Start PostgreSQL service"
echo "   db-stop.sh      # Stop PostgreSQL service"
echo "   db-restart.sh   # Restart PostgreSQL service"
echo "   db-status.sh    # Check PostgreSQL status"
echo ""
echo "⚠️  IMPORTANT SECURITY NOTES:"
echo "   - Passwords have been generated randomly and stored in .env file"
echo "   - .env file has secure permissions (600)"
echo "   - Change the admin password after first login"
echo "   - Keep the .env file secure and never commit to version control"
echo ""
echo "🚀 Next Steps:"
echo "   1. Run your database schema setup script"
echo "   2. Run your application"
echo "   3. Access admin panel at: http://localhost:3000/admin/login"
echo "   4. Login with the credentials shown above"
echo ""
echo "💾 Database connection string:"
echo "   postgresql://logistics_user:${DB_PASSWORD}@localhost:5432/logistics_db"
echo ""

# Save credentials to a secure file
cat > postgres_credentials.txt << EOF
PostgreSQL Credentials (SAVE THIS SECURELY):
============================================
Database: logistics_db
Username: logistics_user
Password: ${DB_PASSWORD}

Admin Login:
Email: admin@blacksea-star.com
Password: ${ADMIN_PASSWORD}

Connection URL:
postgresql://logistics_user:${DB_PASSWORD}@localhost:5432/logistics_db

Generated on: $(date)
EOF

chmod 600 postgres_credentials.txt
print_warning "Credentials saved to postgres_credentials.txt (secure file)"
print_warning "Please store this file securely and delete it after noting the credentials"
