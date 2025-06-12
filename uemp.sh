Copyright (c) 2025 Aaron A. Dennis

Licensed under the MIT License. See LICENSE file for details.

#!/bin/bash

# Exit on error
set -e

# Check for and install dialog if not present
if ! command -v dialog &>/dev/null; then
    echo "Dialog is not installed. Installing..."
    sudo apt update
    sudo apt install -y dialog
fi

# Dialog-based user input
HOSTNAME=$(dialog --inputbox "Enter the hostname:" 10 60 "yourhostname" 3>&1 1>&2 2>&3)
DOMAIN=$(dialog --inputbox "Enter the domain:" 10 60 "yourdomain.com" 3>&1 1>&2 2>&3)
DB_NAME=$(dialog --inputbox "Enter the WordPress database name:" 10 60 "wordpress" 3>&1 1>&2 2>&3)
DB_USER=$(dialog --inputbox "Enter the WordPress database user:" 10 60 "wpuser" 3>&1 1>&2 2>&3)
DB_PASS=$(dialog --inputbox "Enter the WordPress database password:" 10 60 "securepassword" 3>&1 1>&2 2>&3)
PHP_VERSION=$(dialog --inputbox "Enter the PHP version:" 10 60 "php8.1" 3>&1 1>&2 2>&3)
SSHPORT=$(dialog --inputbox "Enter the SSH port:" 10 60 "2222" 3>&1 1>&2 2>&3)

# Update and upgrade system
echo "Updating and upgrading the system..."
sudo apt update && sudo apt upgrade -y

# Set hostname
echo "Setting hostname to $HOSTNAME..."
sudo hostnamectl set-hostname "$HOSTNAME"
echo "$HOSTNAME" | sudo tee /etc/hostname

# Install necessary packages
echo "Installing required packages..."
sudo apt install -y \
  nginx \
  mariadb-server \
  mariadb-client \
  fail2ban \
  certbot python3-certbot-nginx \
  curl wget unzip \
  $PHP_VERSION-fpm \
  $PHP_VERSION-mysql \
  $PHP_VERSION-cli \
  $PHP_VERSION-curl \
  $PHP_VERSION-gd \
  $PHP_VERSION-mbstring \
  $PHP_VERSION-xml \
  $PHP_VERSION-xmlrpc \
  $PHP_VERSION-soap \
  $PHP_VERSION-intl \
  $PHP_VERSION-zip \
  ufw \
  dialog

# Configure UFW firewall
echo "Configuring UFW firewall..."
sudo ufw allow OpenSSH
sudo ufw allow $SSHPORT/tcp
sudo ufw allow 'Nginx Full'
sudo ufw enable

# Configure SSH
echo "Configuring SSH to use port $SSHPORT..."
sudo sed -i "s/^#Port 22/Port $SSHPORT/" /etc/ssh/sshd_config
sudo systemctl restart sshd

# Configure Fail2Ban
echo "Configuring Fail2Ban..."
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo sed -i "s/^#ssh/ssh/" /etc/fail2ban/jail.local
sudo sed -i "s/^port = ssh/port = $SSHPORT/" /etc/fail2ban/jail.local
sudo systemctl restart fail2ban

# Configure MariaDB
echo "Securing MariaDB..."
sudo mysql_secure_installation

# Create WordPress database and user
echo "Creating WordPress database and user..."
sudo mysql -u root -p <<MYSQL_SCRIPT
CREATE DATABASE $DB_NAME;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# Download and configure WordPress
echo "Downloading and configuring WordPress..."
cd /tmp
wget https://wordpress.org/latest.tar.gz
tar -xvzf latest.tar.gz
sudo cp -R wordpress /var/www/
sudo chown -R www-data:www-data /var/www/wordpress
sudo chmod -R 755 /var/www/wordpress

# Configure WordPress wp-config.php
echo "Configuring WordPress wp-config.php..."
cd /var/www/wordpress
cp wp-config-sample.php wp-config.php
sed -i "s/database_name_here/$DB_NAME/" wp-config.php
sed -i "s/username_here/$DB_USER/" wp-config.php
sed -i "s/password_here/$DB_PASS/" wp-config.php

# Configure Nginx for WordPress
echo "Configuring Nginx for WordPress..."
sudo bash -c "cat > /etc/nginx/sites-available/wordpress <<EOL
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    root /var/www/wordpress;

    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/$PHP_VERSION-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL"

sudo ln -s /etc/nginx/sites-available/wordpress /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# Obtain SSL certificate from Let's Encrypt
echo "Obtaining SSL certificate from Let's Encrypt..."
sudo certbot --nginx -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos --email your-email@example.com

# Set up cron job for SSL renewal
echo "Setting up cron job for SSL certificate renewal..."
(crontab -l 2>/dev/null; echo "0 0 * * * certbot renew --quiet && systemctl reload nginx") | crontab -

# Set up daily MariaDB database flush
echo "Setting up daily MariaDB database flush..."
echo "@daily /usr/bin/mysqlcheck -Aos --auto-repair > /dev/null 2>&1" | crontab -

# Enable and start Fail2Ban
echo "Starting and enabling Fail2Ban..."
sudo systemctl start fail2ban
sudo systemctl enable fail2ban

# Final message
echo "WordPress setup is complete. Please complete the installation by visiting https://$DOMAIN."

