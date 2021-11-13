#!/bin/bash
hostingfolder='/web'
project="$1"

test -z $project && {
	echo "Usage: ./aahosting.sh <domain>"
	exit 0
}

myip=
myip=$(dig +short myip.opendns.com @resolver1.opendns.com)
test -z $myip && myip=$(curl -s https://ip8.com/ip)

## make sure hostname resolves to our ip address
host "$project" 8.8.8.8 | grep -q "$myip" ||  {
	echo "$project must resolve to ip $myip"
	exit 1;
}


dir="$hostingfolder/$project"
html="$dir/html"
test -e "$dir" || mkdir -p "$dir"
test -e "$html" || mkdir -p "$html"
echo "$project is ready" >> "$html/index.php"


tee "/etc/apache2/sites-enabled/$project.conf" <<EOF
<VirtualHost *:80>
        ServerName $project
        HostNameLookups Off
        DocumentRoot /opt/$project/html
        Errorlog ${APACHE_LOG_DIR}/$project.error.log
        CustomLog ${APACHE_LOG_DIR}/$project.access.log combined
</VirtualHost>
EOF

systemctl restart apache2


curl -s "http://$project" | grep -q "$project" || {
  echo "could not verify project hosting"
  exit 1
}
echo "Apache hosting is verified for $project"

test -e "/etc/letsencrypt/live/$project/fullchain.pem" || {
  echo "Creating ssl cert for $project"
  certbot certonly -d "$project"  --webroot --webroot-path "$html"
}
test -e "/etc/letsencrypt/live/$project/fullchain.pem" || {
  echo "Error creating ssl certs"
  exit 1
}
echo "SSL Certs created for $project"
tee "/etc/apache2/sites-enabled/$project.ssl.conf" <<EOF
<IfModule mod_ssl.c>
SSLProtocol all -SSLv3 -SSLv2
SSLCipherSuite EECDH+ECDSA+AESGCM:EECDH+aRSA+AESGCM:EECDH+ECDSA+SHA384:EECDH+ECDSA+SHA256:EECDH+aRSA+SHA384:EECDH+aRSA+SHA256:EECDH+aRSA+RC4:EECDH:EDH+aRSA:!aNULL:!eNULL:!LOW:!3DES:!MD5:!EXP:!PSK:!SRP:!DSS:!RC4
<VirtualHost _default_:443>
        ServerName $project
        AddDefaultCharset UTF-8
        DocumentRoot $html
        Errorlog \${APACHE_LOG_DIR}/$project.ssl.error.log
        CustomLog \${APACHE_LOG_DIR}/$project.ssl.access.log combined
        BrowserMatch "gvfs/*" redirect-carefully
        SSLEngine On
        SSLOptions +StrictRequire
        SSLCertificateChainFile /etc/letsencrypt/live/$project/fullchain.pem
        SSLCertificateFile  /etc/letsencrypt/live/$project/cert.pem
        SSLCertificateKeyFile /etc/letsencrypt/live/$project/privkey.pem
        <Files ~ "\.(cgi|shtml|phtml|php3?)\$">
                SSLOptions +StdEnvVars
        </Files>
</VirtualHost>
</IfModule>
EOF

systemctl restart apache2


curl -s "https://$project" | grep -q "$project" || {
  echo "could not verify ssl project hosting"
  exit 1
}
echo "Apache ssl hosting is verified for $project"