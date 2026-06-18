#!/bin/bash
apt update
echo "#################################### install dotnet ####################################"
apt install -y aspnetcore-runtime-8.0 # for run only
#apt install -y dotnet-sdk-6.0 #for build and run
#apt install unzip -y

# Install aws CodeDeploy agent
cd /tmp
echo "#################################### install codedeploy ####################################"
apt install -y ruby-full wget
wget https://aws-codedeploy-{region}.s3.{region}.amazonaws.com/latest/install
chmod +x ./install
./install auto

echo "#################################### start codedeploy ####################################"
systemctl start codedeploy-agent

