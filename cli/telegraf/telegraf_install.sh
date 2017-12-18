echo "*******************************************************************************"
echo "                         Telegraf installation started"
echo "*******************************************************************************"
cd /tmp
mirror_path=$MIRROR_PATH
telegraf_version=$TELEGRAF_VERSION
mirror_path=$mirror_path"/mirror_metrics/"
KAFKA_SERVER_LIST="$(tr -d "\"\`'\]\[" <<<$KAFKA_SERVER_LIST| tr "," "\n")"

if [[ -z "$mirror_path" ]];then
        echo error: Mirror path not found
        exit 1
fi
file_name="telegraf.gz"

telegraf -version | grep $telegraf_version &> /dev/null
if [ $? -ne 0 ]; then
    echo downloading telegraf package $file_name
    curl --fail -O $mirror_path$file_name
    if [ 0 -ne $? ]; then
        echo "error: Failed to download telegraf package from" $tar_file_path
        exit 1;
    fi;
    
    gzip -d  $file_name 
    sudo chmod +x /tmp/telegraf
    sudo mv /tmp/telegraf /usr/bin/telegraf
    sudo mkdir -p /etc/telegraf/telegraf.d
else
  echo "telegraf already installed"
fi

sudo cp /tmp/telegraf.service /usr/lib/systemd/system/

echo "" > /tmp/telegraf.conf
while read LINE  
do
   if [ "{{KAFKA_CONFIG}}" == "$LINE" ]; then
       for kafka in $KAFKA_SERVER_LIST
       do
       echo '[[inputs.jolokia2_proxy.target]]' >> /tmp/telegraf.conf
       echo "url = \"service:jmx:rmi:///jndi/rmi://$kafka:9050/jmxrmi\""$'\n' >> /tmp/telegraf.conf
       done

   else
       echo $LINE >> /tmp/telegraf.conf
   fi
done < /tmp/telegraf.conf_tmp

sudo sed -i -e 's/{{INFLUXDB_IP}}/'$INFLUXDB_IP'/g' /tmp/telegraf.conf
sudo sed -i -e 's/{{INFLUXDB_PORT}}/'$INFLUXDB_PORT'/g' /tmp/telegraf.conf
sudo sed -i -e 's/{{JETTY_IP}}/'$JETTY_IP'/g' /tmp/telegraf.conf
sudo sed -i -e 's/{{JETTY_PORT}}/'$JETTY_PORT'/g' /tmp/telegraf.conf
sudo sed -i -e 's/{{TELEGRAF_SOCKET_LISTENER_PORT}}/'$TELEGRAF_SOCKET_LISTENER_PORT'/g' /tmp/telegraf.conf

sudo cp /tmp/telegraf.conf /etc/telegraf/
sudo useradd telegraf
sudo systemctl stop telegraf
sleep 5
sudo systemctl daemon-reload
sleep 5
sudo systemctl start telegraf
sleep 5


service_status=`ps -ef | grep -v grep | grep telegraf | wc -l`
if [ $service_status -ne 0 ]; then
    echo service telegraf is running
else
    echo service telegraf is not running
    exit 1
fi;
echo "*******************************************************************************"
echo "                         Telegraf installation completed"
echo "*******************************************************************************"

