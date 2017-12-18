echo "*******************************************************************************"
echo "                         JAVA installation started"
echo "*******************************************************************************"
cd /tmp
mirror_path=$MIRROR_PATH
jetty_version=$JETTY_VERSION
jetty_port=$JETTY_PORT
java_version="1.8"
jolokia_version=$JOLOKIA_VERSION

if [[ -z "$mirror_path" ]];then
	echo error: mirror path not found
	exit 1
fi

if [[ -z "jetty_version" ]];then
        echo error: environment variable not set for jetty version
	exit 1
fi

if [[ -z "jetty_port" ]];then
        echo error: environment variable not set for jetty port
	exit 1
fi

if [[ -z "jolokia_version" ]];then
        echo error: environment variable not set for jolokia version
	exit 1
fi

#Download Java tar file from mirror server path
java_file_name=jdk-8u131-linux-x64.tar.gz
java_file_path=$mirror_path"/mirror_misc/"$java_file_name
echo downloading java package $java_file_name
sudo curl --fail -O $java_file_path
if [ 0 -ne $? ]; then
        echo "       ********* JAVA installation FAILED"
	echo "error: Failed to download java package from " $java_file_path
	exit 1;
fi;

sudo tar -C /usr/lib/jvm -xzf $java_file_name --no-same-owner
sudo sed -i "\$aexport JAVA_HOME=/usr/lib/jvm/jdk1.8.0_131/jre/bin" /etc/profile
export JAVA_HOME=/usr/lib/jvm/jdk1.8.0_131/jre/bin

echo "*******************************************************************************"
echo "                         JAVA installation Completed Successfully"
echo "*******************************************************************************"

echo "*******************************************************************************"
echo "                         JETTY webserver installation started"
echo "*******************************************************************************"

jetty_file_name=jetty-distribution-$jetty_version.v20170914.tar.gz
jetty_file_path=$mirror_path"/mirror_metrics/"$jetty_file_name
echo downloading Jetty package $jetty_file_name
curl --fail -O $jetty_file_path
if [ 0 -ne $? ]; then
    echo "error: failed to download jetty package from " $jetty_file_path
fi;
echo configuring jetty
sudo tar zxvf $jetty_file_name -C /opt/
sudo mv /opt/jetty-distribution-$jetty_version.v20170914/ /opt/jetty
sudo mv  /opt/jetty/start.ini  /opt/jetty/start.ini_backup
sudo cp /tmp/start.ini /opt/jetty/start.ini
sudo sed -i -e 's/{{JETTY_PORT}}/'$jetty_port'/g' /opt/jetty/start.ini
sudo useradd -m jetty
sudo chown -R jetty:jetty /opt/jetty/
sudo ln -s /opt/jetty/bin/jetty.sh /etc/init.d/jetty
sudo chkconfig --add jetty
sudo chkconfig --level 345 jetty on

sudo chown -R jetty:jetty /opt/jetty/
sudo mkdir -p /var/run/jetty
sudo chown jetty:jetty /var/run/jetty
echo "JETTY_HOME=/opt/jetty" >> /tmp/jetty_default
echo "JETTY_USER=jetty" >>/tmp/jetty_default
echo "JETTY_PORT="$jetty_port >> /tmp/jetty_default
echo "JETTY_HOST=localhost" >> /tmp/jetty_default
echo "JETTY_LOGS=/opt/jetty/logs/" >> /tmp/jetty_default

sudo mv /tmp/jetty_default /etc/default/jetty

echo "*******************************************************************************"
echo "                         JETTY webserver installation completed"
echo "*******************************************************************************"
echo "                         Jolokia installation started"
echo "*******************************************************************************"

#Download Java tar file from mirror server path
#jolokia-1.3.7-bin.tar.gz
jolokia_file_name=jolokia-$jolokia_version-bin.tar.gz
jolokia_file_path=$mirror_path"/mirror_metrics/"$jolokia_file_name
echo downloading Jetty package $jolokia_file_name
curl --fail -O $jolokia_file_path
if [ 0 -ne $? ]; then
    echo "error: failed to download jetty package from " $jolokia_file_path
fi;

tar zxvf $jolokia_file_name 
sudo cp jolokia-$jolokia_version/agents/jolokia.war /opt/jetty/webapps/jolokia.war; 
sudo chown jetty:jetty /opt/jetty/webapps/jolokia.war
echo "                         Restarting jetty webserver"
sudo service jetty stop
sleep 5
echo starting jetty server
sudo service jetty start
sleep 5

result=`curl -sL -w "%{http_code}\\n" "http://localhost:$jetty_port/jolokia/" -o /dev/null`
if [ $result == 200 ]; then
   echo jetty successfully install and configured
   echo jolokia successfully configured
else
   echo Failed to installed and configured jetty and jolokia 
   exit 1
fi
echo "*******************************************************************************"
echo "                         Jolokia installation completed"
echo "*******************************************************************************"
