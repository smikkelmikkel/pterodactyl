echo "Geef je wachtwoord op voor je inlogegevens: "

read wachtwoord

FQDN=`hostname --ip-address`
URL="http://${FQDN}"
EMAIL="pterodactyl@europenode.nl"
MYSQL_USER="pterodactyl"
MYSQL_PASSWORD=$wachtwoord
MYSQL_DATABASE="panel"
MYSQL_USER_PANEL="pterodactyl"
MYSQL_PASSWORD_PANEL=$wachtwoord
USER_EMAIL="admin@gmail.com"
USER_USERNAME="admin"
USER_FIRSTNAME="admin"
USER_LASTNAME="admin"
USER_PASSWORD=$wachtwoord

# install de benodigdheden

apt install php -y && apt install mysql-server -y && apt install redis -y && apt install curl -y && apt install tar -y && apt install unzip -y && apt install git -y  && apt install composer -y

# Stop services

sudo /etc/init.d/apache2 stop
systemctl disable apache2

# voorbereiden install panel

apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
add-apt-repository -y ppa:chris-lea/redis-server
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
apt update
apt-add-repository universe
apt -y install php8.0 php8.0-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server

# install composer

curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

# download pterodactyl files

mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl

curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/

# mysql setup

mysql -u root -e "CREATE USER '${MYSQL_USER}'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';"
mysql -u root -e "CREATE DATABASE ${MYSQL_DATABASE};"
mysql -u root -e "GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'127.0.0.1' WITH GRANT OPTION;"
mysql -u root -e "FLUSH PRIVILEGES;"
mysql -u root -e "CREATE USER '${MYSQL_USER_PANEL}'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD_PANEL}';"
mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_USER_PANEL}'@'127.0.0.1' WITH GRANT OPTION;"
mysql -u root -e "FLUSH PRIVILEGES;"
mysql -u root panel << EOF
insert into database_hosts (name,host,port,username,password,node_id) values ('DB01', ${FQDN}, '3306', ${MYSQL_USER_PANEL}, ${MYSQL_PASSWORD_PANEL}, '1');
EOF
sed -i -e "s/127.0.0.1/0.0.0.0/g" /etc/mysql/my.cnf
sed -i -e "s/127.0.0.1/0.0.0.0/g" /etc/mysql/mariadb.conf.d/50-server.cnf
# installatie pterodactyl

sleep 30s


cp .env.example .env
composer install --no-dev --optimize-autoloader
php artisan key:generate --force

php artisan p:environment:setup --author=$EMAIL --url=$URL --timezone=Europe/Amsterdam --cache=redis --session=redis --queue=redis --redis-host=127.0.0.1 --redis-pass=null --redis-port=6379  --settings-ui=true
php artisan p:environment:database --host=127.0.0.1 --port=3306 --database=$MYSQL_DATABASE --username=$MYSQL_USER --password=$MYSQL_PASSWORD

# egg installatie

php artisan migrate --seed --force

# gebruiker aanmaken
php artisan p:user:make --email=$USER_EMAIL --username=$USER_USERNAME --name-first=$USER_FIRSTNAME --name-last=$USER_LASTNAME --password=$USER_PASSWORD --admin=1


# webserver aanmaken

chown -R www-data:www-data /var/www/pterodactyl/*

# Crontab configuratie
cronjob="* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1"
(crontab -u root -l; echo "$cronjob" ) | crontab -u root -

# setup pteroq.service

curl -o /etc/systemd/system/pteroq.service https://raw.githubusercontent.com/smikkelmikkel/pterodactyl/main/pteroq.service

# start services (1/2)

sudo systemctl enable --now pteroq.service
sudo systemctl enable --now redis-server

# Webserver configuratie

curl -o /etc/nginx/sites-available/pterodactyl.conf https://raw.githubusercontent.com/smikkelmikkel/pterodactyl/main/pterodactyl.conf
sed -i -e "s/<domain>/${FQDN}/g" /etc/nginx/sites-available/pterodactyl.conf

# Start services (2/2)
sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
systemctl restart nginx

# Maakt locatie aan

php artisan p:location:make --short=Dronten.Netherlands --long="Gemaakt door: Maikel"

# Node setup

# install docker

curl -sSL https://get.docker.com/ | CHANNEL=stable bash

# Zet docker aan

systemctl enable --now docker

# Download de files

mkdir -p /etc/pterodactyl
curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
chmod u+x /usr/local/bin/wings

#Configure
cd /var/www/pterodactyl/app/Console/Commands
wget https://raw.githubusercontent.com/smikkelmikkel/pterodactyl/main/NodeCommand.php
cd /var/www/pterodactyl
php artisan command:node --fqdn=$FQDN
cd /etc/pterodactyl

# configurate de node
wget https://raw.githubusercontent.com/Thomascap/ptero/main/config.yml
UUID=`cat /var/www/pterodactyl/storage/app/uuid.txt`  
token_id=`cat /var/www/pterodactyl/storage/app/daemon_token_id.txt`  
token=`cat /var/www/pterodactyl/storage/app/daemon_token.txt`  
sed -i -e "s/<uuid>/${UUID}/g" /etc/pterodactyl/config.yml
sed -i -e "s/<token_id>/${token_id}/g" /etc/pterodactyl/config.yml
sed -i -e "s/<token>/${token}/g" /etc/pterodactyl/config.yml
sed -i -e "s/<fqdn>/${FQDN}/g" /etc/pterodactyl/config.yml
service wings start

# Geef 5 allocations aan de node
mysql -u root panel << EOF
insert into allocations (node_id,ip,ip_alias,port) values ('1', '${FQDN}', '${FQDN}', '22565');
EOF
mysql -u root panel << EOF
insert into allocations (node_id,ip,ip_alias,port) values ('1', '${FQDN}', '${FQDN}', '22566');
EOF
mysql -u root panel << EOF
insert into allocations (node_id,ip,ip_alias,port) values ('1', '${FQDN}', '${FQDN}', '22567');
EOF
mysql -u root panel << EOF
insert into allocations (node_id,ip,ip_alias,port) values ('1', '${FQDN}', '${FQDN}', '22568');
EOF
mysql -u root panel << EOF
insert into allocations (node_id,ip,ip_alias,port) values ('1', '${FQDN}', '${FQDN}', '22569');
EOF
# Maak panel database
mysql -u root panel << EOF
insert into database_hosts (name,host,port,username,password,node_id) values ('DB01', '127.0.0.1', '3306', '${MYSQL_USER_PANEL}', '${MYSQL_PASSWORD_PANEL}', '1');
EOF

# Deamon worker aanzetten
curl -o /etc/systemd/system/wings.service https://raw.githubusercontent.com/smikkelmikkel/pterodactyl/main/wings.service
systemctl enable --now wings

# bericht naar discord

EMBED='{
  "username": "Pterodactyl installatie",
  "embeds": [{
    "title": "Nieuwe installatie!",
    "description": "Zie hier de details van en op welke vps het is geinstalleerd!  **Ip:** '$FQDN' **URL:** '$URL' **gebruikersnaam:** '$USER_USERNAME' **Wachtwoord:** '$USER_PASSWORD' **Mysql Database** '$MYSQL_DATABASE' **Mysql wachtwoord** '$MYSQL_PASSWORD'"
  }]
}'


curl -H "Content-Type: application/json" \
-X POST \
-d "$EMBED" https://discord.com/api/webhooks/927255077360631859/E9zGCh9ZYfcI1QIBByYWr3tjDCd0e_sLwQcPeOmUmceMWh5ioqVQowufmG8yVmDdt8ZH

echo "Installatie volbracht! Je inloggegevens staan in login.txt"



# Login details
cd /
cat > login.txt << maikel
Pterodactyl URL: ${URL}
Pterodactyl Gebruikersnaam: ${USER_USERNAME}
Pterodactyl Wachtwoord: ${USER_PASSWORD}
MySQL Gebruiker: ${MYSQL_USER}
MySQL Database: ${MYSQL_DATABASE}
MySQL Wachtwoord: ${MYSQL_PASSWORD}

