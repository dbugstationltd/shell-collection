#!/bin/bash
echo "Enter Application ID"
read -r APP_ID
echo "Enter Remote Repo URL"
read -r REPO_URL
echo "Enter Deployment Branch"
read -r REPO_BRANCH
echo "Enter Domain"
read -r APP_DOMAIN
APP_PARENT_DIR=/var/www
APP_POST_DEPLOY_COMMAND="php artisan migrate"

echo "<-------------------Installing  PHP 8.1, Extensions And Others------------------->"
sudo apt install software-properties-common && sudo add-apt-repository ppa:ondrej/php -y
sudo apt update
sudo apt upgrade -y
sudo apt install curl -y
sudo apt install git -y
sudo apt install nginx -y
sudo apt install supervisor -y
sudo apt install redis-server -y
sudo apt install php8.1 -y
sudo apt install php8.1-bcmath -y
sudo apt install php8.1-bz2 -y
sudo apt install php8.1-cli -y
sudo apt install php8.1-common -y
sudo apt install php8.1-curl -y
sudo apt install php8.1-dev -y
sudo apt install php8.1-gd -y
sudo apt install php8.1-igbinary -y
sudo apt install php8.1-imagick -y
sudo apt install php8.1-imap -y
sudo apt install php8.1-intl -y
sudo apt install php8.1-json -y
sudo apt install php8.1-mbstring -y
sudo apt install php8.1-memcached -y
sudo apt install php8.1-msgpack -y
sudo apt install php8.1-mysql -y
sudo apt install php8.1-opcache -y
sudo apt install php8.1-pgsql -y
sudo apt install php8.1-readline -y
sudo apt install php8.1-redis -y
sudo apt install php8.1-ssh2 -y
sudo apt install php8.1-tidy -y
sudo apt install php8.1-xml -y
sudo apt install php8.1-xmlrpc -y
sudo apt install php8.1-zip -y
sudo apt install php8.1-swoole -y
echo "Checking PHP Version"
php -v
echo "Verify Swoole is loaded"
php -m | grep swoole

echo "<-------------------Installing Composer------------------->"
cd /tmp
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php -r "if (hash_file('sha384', 'composer-setup.php') === '55ce33d7678c5a611085589f1f3ddf8b3c52d662cd01d4ba75c0ee0459970c2200a51f492d557530c71c15d8dba01eae') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
php composer-setup.php
php -r "unlink('composer-setup.php');"
sudo mv composer.phar /usr/local/bin/composer

#echo "<-------------------Installing NVM And Node------------------->"
#cd /tmp
#curl https://raw.githubusercontent.com/creationix/nvm/master/install.sh | bash
#source ~/.profile
#nvm install 16.15.1
#echo "Check Node And Npm Version"
#node -v
#npm -v
#echo "install pm2 for inertia ssr"
#npm install pm2@latest -g
#sudo pm2 startup

echo "<-------------------Application Setup------------------->"
echo "Adding current user to www-data group"
sudo usermod -a -G www-data "$USER"
echo "Making Directories If Not Exists"
sudo mkdir -p $APP_PARENT_DIR
sudo chown -R www-data:www-data $APP_PARENT_DIR
sudo chmod -R 775 $APP_PARENT_DIR

echo "Clone And Checkout Git"
cd $APP_PARENT_DIR
git clone $REPO_URL $APP_ID
cd $APP_ID
git checkout $REPO_BRANCH
git pull origin $REPO_BRANCH

cp .env.$REPO_BRANCH .env
source .env
composer install --optimize-autoloader
npm install

echo "<-------------------Installing DB------------------->"
if [ "$DB_CONNECTION" == "mysql" ]; then
  curl -LO https://dev.mysql.com/get/mysql-apt-config_0.8.20-1_all.deb
  sudo dpkg -i mysql-apt-config_0.8.20-1_all.deb
  echo "Checking mysql-server is available"
  sudo apt-cache policy mysql-server
  sudo apt install mysql-server -y
  apt-cache policy mysql-server
  echo "Mysql Secure Installing"
  sudo mysql_secure_installation
  echo "Enable auto-start"
  sudo systemctl enable mysql
  source /etc/mysql/debian.cnf
  SQL1="CREATE DATABASE IF NOT EXISTS ${DB_DATABASE};"
  SQL2="CREATE USER '${DB_USERNAME}'@'%' IDENTIFIED BY '${DB_PASSWORD}';"
  SQL3="GRANT ALL PRIVILEGES ON ${DB_DATABASE}.* TO '${DB_USERNAME}'@'%';"
  SQL4="FLUSH PRIVILEGES;"
  mysql -h ${DB_HOST} -u ${user} -p${password} -e "${SQL1}${SQL2}${SQL3}${SQL4}"
fi

echo "<-------------------Redis Setup------------------->"
echo "Configure Redis"
sudo nano /etc/redis/redis.conf
sudo systemctl restart redis.service

echo "<-------------------Web Server And Process Setup------------------->"
echo "Verify And Setup supervisor installation"
supervisord -v
sudo bash -c "cat <<EOF >/etc/supervisor/conf.d/octane-worker.conf
[program:octane-worker]
process_name=%(program_name)s_%(process_num)02d
command=php ${APP_PARENT_DIR}/${APP_ID}/artisan octane:start --server=swoole --max-requests=1000 --workers=4 --task-workers=12 --port=8089
autostart=true
autorestart=true
user=www-data
redirect_stderr=true
stdout_logfile=${APP_PARENT_DIR}/${APP_ID}/public/octane-worker.log
stopwaitsecs=3600
EOF"
sudo bash -c "cat <<EOF >/etc/supervisor/conf.d/queue-worker.conf
[program:queue-worker]
process_name=%(program_name)s_%(process_num)02d
command=php ${APP_PARENT_DIR}/${APP_ID}/artisan queue:listen
autostart=true
autorestart=true
user=www-data
numprocs=1
redirect_stderr=true
stdout_logfile=${APP_PARENT_DIR}/${APP_ID}/public/queue-worker.log
EOF"
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl restart all
echo "Setup Laravel Scheduler"
(crontab -l; echo "* * * * * php ${APP_PARENT_DIR}/${APP_ID}/artisan schedule:run >> /dev/null 2>&1") | sort -u | crontab -
#echo "Setup SSR Compilation"
#pm2 start "${APP_PARENT_DIR}/${APP_ID}/public/js/ssr.js" --name="${APP_ID}"

echo "Setup Nginx"
nginx -v
sudo rm /etc/nginx/sites-available/default
sudo rm /etc/nginx/sites-enabled/default
sudo bash -c "cat <<EOF >/etc/nginx/sites-available/${APP_DOMAIN}
server {
    listen 80;
    server_name ${APP_DOMAIN} www.${APP_DOMAIN};
    root ${APP_PARENT_DIR}/${APP_ID}/public;
    index index.html index.htm index.php;
    error_page 404 /index.php;
    location / {
        proxy_pass    http://127.0.0.1:8089;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF"
sudo ln -s /etc/nginx/sites-available/${APP_DOMAIN} /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
echo "Enable SSL"
sudo snap install core; sudo snap refresh core
sudo apt remove certbot
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
sudo ufw status
sudo ufw allow 'Nginx Full'
sudo ufw delete allow 'Nginx HTTP'
sudo ufw status
sudo certbot --nginx -d "$APP_DOMAIN" -d "www.${APP_DOMAIN}"
sudo certbot renew --dry-run

echo "<----------------------Post Deploy----------------------->"
cd "${APP_PARENT_DIR}/${APP_ID}"
bash -c "$APP_POST_DEPLOY_COMMAND"

echo "<----------------------Cleaning----------------------->"
sudo apt autoremove

