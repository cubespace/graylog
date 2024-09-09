#!/bin/bash

# Nhập hostname và password từ người dùng
read -p "Enter DNS name: " hostname
echo 
IP=$(hostname -I | awk '{print $1}')

# Hàm cài đặt Nginx với SSL
function install_nginx_ssl {
    # Tạo chứng chỉ SSL tự ký
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
EOF
    openssl x509 -req -in localhost.csr -CA CA.pem -CAkey CA.key -CAcreateserial -days 365 -sha256 -extfile localhost.ext -out localhost.crt

    # Tạo thư mục lưu trữ chứng chỉ SSL và di chuyển các tệp chứng chỉ vào đó
    sudo mkdir -p /etc/nginx/ssl-certificate
    sudo mv localhost.crt localhost.key /etc/nginx/ssl-certificate

    # Kiểm tra nếu file cấu hình đã tồn tại
    if [ -f /etc/nginx/sites-available/graylog.conf ]; then
        echo "File /etc/nginx/sites-available/graylog.conf already exists. Backup and update the file."
        sudo mv /etc/nginx/sites-available/graylog.conf /etc/nginx/sites-available/graylog.conf.bak
    fi

    # Tạo cấu hình Nginx mới
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

    # Tạo liên kết biểu thị và khởi động lại Nginx
    sudo ln -s /etc/nginx/sites-available/graylog.conf /etc/nginx/sites-enabled/
    sudo systemctl restart nginx
}

# Mở các cổng trên tường lửa
sudo ufw allow 443/tcp

# Gọi hàm cài đặt Nginx với SSL
install_nginx_ssl

echo "Graylog and Nginx have been installed and configured."
echo "Access Graylog at https://$hostname (SSL is enabled)."
