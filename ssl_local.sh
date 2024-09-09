#!/bin/bash

# Nhập hostname và password từ người dùng
read -p "Enter DNS name: " hostname
echo 
read -s -p "Enter password opensearch (not use @): " password_opensearch
echo
read -s -p "Enter password graylog: " password_graylog
echo
#IP=$(hostname -I | awk '{print $1}')
# Tạo mật khẩu secret
password_secret=$(</dev/urandom tr -dc A-Z-a-z-0-9 | head -c${1:-96};echo)
# Tạo hash SHA-256 từ mật khẩu người dùng đã nhập
root_password_sha2=$(echo -n "$password_graylog" | sha256sum | cut -d" " -f1)
# Đường dẫn tới file cấu hình
config_file="/etc/graylog/server/server.conf"

# Hỏi người dùng xem họ có muốn cấu hình SSL không
read -p "Do you want to configure SSL for Nginx? (y/n): " ssl_choice

# Đặt múi giờ
timedatectl set-timezone Asia/Ho_Chi_Minh
sudo apt-get update
sudo apt install curl wget apt-transport-https -y
sudo apt install openjdk-17-jre-headless -y

# Hàm cài đặt MongoDB
function install_mongod {
    sudo apt-get install gnupg curl -y
    curl -fsSL https://pgp.mongodb.com/server-6.0.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/mongodb-server-6.0.gpg
    echo "deb [ arch=amd64,arm64 signed-by=/etc/apt/trusted.gpg.d/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list
    sudo apt-get update
    sudo apt-get install -y mongodb-org
    sudo systemctl daemon-reload
    sudo systemctl start mongod
    sudo systemctl enable mongod
    sudo apt-mark hold mongodb-org
}

function install_opensearch {
    sudo apt-get update && sudo apt-get -y install lsb-release ca-certificates curl gnupg2
    curl -o- https://artifacts.opensearch.org/publickeys/opensearch.pgp | sudo gpg --dearmor --batch --yes -o /usr/share/keyrings/opensearch-keyring
    echo "deb [signed-by=/usr/share/keyrings/opensearch-keyring] https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/apt stable main" | sudo tee /etc/apt/sources.list.d/opensearch-2.x.list
    sudo apt-get update
    sudo env OPENSEARCH_INITIAL_ADMIN_PASSWORD="$password_opensearch" apt-get install opensearch=2.15.0
    echo "cluster.name: graylog" >> /etc/opensearch/opensearch.yml
    echo "node.name: ${hostname}" >> /etc/opensearch/opensearch.yml
    echo "discovery.type: single-node" >> /etc/opensearch/opensearch.yml
    echo "network.host: 0.0.0.0" >> /etc/opensearch/opensearch.yml
    echo "action.auto_create_index: false" >> /etc/opensearch/opensearch.yml
    echo "plugins.security.disabled: true" >> /etc/opensearch/opensearch.yml
    sudo systemctl daemon-reload
    sudo systemctl enable opensearch.service
    sudo systemctl start opensearch.service
}

# Hàm cài đặt Graylog
function install_graylog {
    wget https://packages.graylog2.org/repo/packages/graylog-6.0-repository_latest.deb
    sudo dpkg -i graylog-6.0-repository_latest.deb
    sudo apt-get update && sudo apt-get install graylog-server
    apt-mark hold graylog-server
    # Thay thế giá trị trong file cấu hình
    sed -i "s|password_secret *=.*|password_secret = $password_secret|" $config_file
    sed -i "s|root_password_sha2 *=.*|root_password_sha2 = $root_password_sha2|" $config_file
    #elasticsearch_host="http://opensearch:${password_opensearch}@$IP:9200"
    #sed -i "s|#elasticsearch_hosts *=.*|elasticsearch_hosts = http://127.0.0.1:9200|" $config_file
    sudo sed -i 's/#http_bind_address = 127.0.0.1.*/http_bind_address = 0.0.0.0:9000/g' $config_file
    sed -i "s|#http_publish_uri = http://192.168.1.1:9000/|http_publish_uri = http://$IP:9000/|" $config_file
	#sed -i 's/#message_journal_max_size = 5gb/message_journal_max_size = 2gb/' $config_file
    sed -i 's/#root_timezone = UTC/root_timezone = Asia\/Ho_Chi_Minh/' $config_file
    sudo systemctl daemon-reload
    sudo systemctl enable graylog-server.service
    sudo systemctl start graylog-server.service
}

# Hàm cài đặt Nginx với SSL
function install_nginx_ssl {
    apt install nginx -y
    openssl genrsa -out CA.key 2048
    openssl req -x509 -sha256 -new -nodes -days 3650 -key CA.key -out CA.pem
    openssl genrsa -out localhost.key 2048
    openssl req -new -key localhost.key -out localhost.csr
    sudo tee localhost.ext > /dev/null <<EOF
authorityKeyIdentifier = keyid,issuer
basicConstraints = CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = $hostname
#IP.1 = $IP
EOF
    openssl x509 -req -in localhost.csr -CA CA.pem -CAkey CA.key -CAcreateserial -days 365 -sha256 -extfile localhost.ext -out localhost.crt
    mkdir /etc/nginx/ssl-certificate
    mv localhost.crt localhost.key /etc/nginx/ssl-certificate
    sudo tee /etc/nginx/sites-available/graylog.conf > /dev/null <<EOF
server {
        listen 80;
        listen [::]:80;
        server_name $hostname;
        return 301 https://\$host\$request_uri;
}

server {
        listen 443 ssl;
        listen [::]:443 ssl;
        server_name $hostname;
        # root /var/www/html;
        index index.html index.htm index.nginx-debian.html;
        # SSL Configuration
        ssl_certificate     /etc/nginx/ssl-certificate/localhost.crt;
        ssl_certificate_key /etc/nginx/ssl-certificate/localhost.key;
        # Logs Locations
        access_log  /var/log/nginx/graylog_access.log;
        error_log  /var/log/nginx/graylog_error.log;
        location / {
                    proxy_set_header Host \$http_host;
                    proxy_set_header X-Forwarded-Host \$host;
                    proxy_set_header X-Forwarded-Server \$host;
                    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
                    proxy_set_header X-Graylog-Server-URL https://\$server_name/;
                    proxy_pass       http://127.0.0.1:9000;
        }
}
EOF
    ln -s /etc/nginx/sites-available/graylog.conf /etc/nginx/sites-enabled/
    systemctl start nginx
    systemctl restart nginx
    systemctl enable nginx
}

# Hàm cài đặt Nginx không có SSL
function install_nginx_no_ssl {
    apt install nginx -y
    sudo tee /etc/nginx/sites-available/graylog.conf > /dev/null <<EOF
server {
        listen 80;
        listen [::]:80;
        server_name $hostname;
        # root /var/www/html;
        index index.html index.htm index.nginx-debian.html;
        location / {
                    proxy_set_header Host \$http_host;
                    proxy_set_header X-Forwarded-Host \$host;
                    proxy_set_header X-Forwarded-Server \$host;
                    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
                    proxy_set_header X-Graylog-Server-URL http://\$server_name/;
                    proxy_pass       http://127.0.0.1:9000;
        }
}
EOF
    ln -s /etc/nginx/sites-available/graylog.conf /etc/nginx/sites-enabled/
    systemctl start nginx
    systemctl restart nginx
    systemctl enable nginx
}

# Gọi các hàm cài đặt
install_mongod
install_opensearch
install_graylog

# Chọn cấu hình Nginx dựa trên lựa chọn của người dùng
if [[ "$ssl_choice" == "y" || "$ssl_choice" == "Y" ]]; then
    install_nginx_ssl
else
    install_nginx_no_ssl
fi
sleep 60
sudo systemctl restart opensearch.service
# Mở các cổng trên tường lửa
sudo ufw allow 9000/tcp
sudo ufw allow 9200/tcp
sudo ufw allow 443/tcp
sudo ufw allow 80/tcp
sudo ufw reload
echo "Graylog and Nginx have been installed and configured."
echo "Access Graylog at http://$hostname or https://$hostname (if SSL is enabled)."
echo "Login with username: admin and your provided password."
