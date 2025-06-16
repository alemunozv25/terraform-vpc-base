#!/bin/bash

set -euo pipefail

# Install Docker
yum update -y
yum install docker -y
service docker start
# usermod -a -G docker ec2-user
docker ps
chkconfig docker on

# Add web user (optional, but recommended for production)
# useradd web

# Pull nginxdemos/hello container image and run it as a service
# docker pull ${APP_IMAGE_URL}
docker pull nginxdemos/hello
# docker run -d --name hello_app --restart always web nginx:stable-html
docker run -d -p 80:80 nginxdemos/hello

# Expose port 80
# iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-ports 6969 -m comment --comment "MyApp"
# iptables-save > /etc/sysconfig/iptables
# service iptables start
# chkconfig iptables on