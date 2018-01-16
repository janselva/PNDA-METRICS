echo "*******************************************************************************"
echo "                         Telegraf installation started"
echo "*******************************************************************************"
cd /tmp
mirror_path=$MIRROR_PATH
telegraf_version=$TELEGRAF_VERSION
mirror_path=$mirror_path"/mirror_metrics/"
JMX_SERVER_LIST="$(tr -d "\"\`'\]\[" <<<$JMX_SERVER_LIST| tr "," "\n")"

if [[ -z "$mirror_path" ]];then
        echo error: Mirror path not found
        exit 1
fi
#file_name="telegraf-1.5.0-1.x86_64.rpm"    
file_name="telegraf""-"$telegraf_version".x86_64.rpm"

telegraf_version_1=$(echo $telegraf_version| cut -d'-' -f 1)


telegraf -version | grep $telegraf_version_1 &> /dev/null
if [ $? -ne 0 ]; then
    echo downloading telegraf package $file_name
    curl --fail -O $mirror_path$file_name
    if [ 0 -ne $? ]; then
        echo "error: Failed to download telegraf package from" $mirror_path$file_name
        exit 1;
    fi;
    
    sudo rpm -i $file_name &> /dev/null
else
  echo "telegraf already installed"
fi

echo "" > /tmp/telegraf.conf
while read LINE  
do
   if [ "{{JMX_CONFIG}}" == "$LINE" ]; then
       for jmx_server in $JMX_SERVER_LIST
       do
       echo '[[inputs.jolokia2_proxy.target]]' >> /tmp/telegraf.conf
       echo "url = \"service:jmx:rmi:///jndi/rmi://$jmx_server/jmxrmi\""$'\n' >> /tmp/telegraf.conf
       done
   elif [ "{{KAFKA_OUTPUT_PLUGIN}}" == "$LINE" ]; then
       echo '[[outputs.kafka]]'$'\n' >> /tmp/telegraf.conf
       echo "   brokers = $KAFKA_BROKERS_LIST" >> /tmp/telegraf.conf
       echo "   topic = \"$KAFKA_TOPIC\"" >> /tmp/telegraf.conf

   elif [ "{{MBEAN_CONFIG}}" == "$LINE" ]; then
       cat /tmp/telegraf_mbean.conf >> /tmp/telegraf.conf
   else
       echo $LINE >> /tmp/telegraf.conf
   fi
done < /tmp/telegraf.conf_tmpl

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

