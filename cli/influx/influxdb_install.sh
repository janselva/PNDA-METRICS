echo "*******************************************************************************"
echo "                         Influx Db installation started"
echo "*******************************************************************************"
cd /tmp
mirror_path=$MIRROR_PATH
influxdb_version=$INFLUXDB_VERSION
mirror_path=$mirror_path"/mirror_metrics/"

if [[ -z "$mirror_path" ]];then
        echo ERROR: Mirror path not found
        echo "       ********* Influx Db installation FAILED"
        exit 1
fi

influx -version | grep $influxdb_version &> /dev/null
if [ $? -ne 0 ]; then
    file_name="influxdb""-"$influxdb_version".x86_64.rpm"
    echo Downloading influxdb package $file_name
    curl --fail -O $mirror_path$file_name
    if [ 0 -ne $? ]; then
        echo "error: Failed to download download package from" $mirror_path$file_name
        echo "       ********* Influx Db installation FAILED"
        exit 1;
    fi;
    sudo rpm -i $file_name &> /dev/null
    if [ $? != 0 ]; then
        echo influxdb installation failed
        echo "       ********* Influx Db installation FAILED"
        exit 1;
    else
        echo "influxdb installed successfully"
    fi;
else
    echo influxdb Version $influxdb_version is already installed
fi
 
echo "Checking /etc/influxdb/influxdb.conf config file"

diff_file=`diff /tmp/influxdb.conf /etc/influxdb/influxdb.conf  |  wc -l`
if [ $diff_file != 0 ]; then
   echo "Taking backup of influxdb config file"
   sudo cp /etc/influxdb/influxdb.conf /etc/influxdb/influxdb.conf.bkp
   sudo cp /tmp/influxdb.conf /etc/influxdb/influxdb.conf
   echo "Restarting the inflexdb service"
   sudo service influxdb restart
   sleep 5
fi;
   
service_status=`ps -ef | grep -v grep | grep influxdb | wc -l`
if [ $service_status > 0 ]; then
  echo "influxdb Service running"
else
  echo "influxdb Service not running"
  echo "       ********* Influx Db installation FAILED"
  exit 1
fi;
echo "Verify telegraf database available in influxdb"

list_databases=`influx -execute 'show databases'`
check_database=`echo $list_databases | grep -c telegraf`
if [ $check_database == 0 ]; then
    echo Creating telegraf database
    influx -execute 'create database telegraf';
fi

list_databases=`influx -execute 'show databases'`
check_database=`echo $list_databases | grep -c telegraf`
if [ $check_database == 0 ]; then
   echo "FAIL: Database telgraf failed to create"
   echo "       ********* Influx Db installation FAILED"
   exit 1
else
   echo "Database telgraf created successfully"
fi

echo "*******************************************************************************"
echo "                         Influx Db retention policy"
echo "*******************************************************************************"
policy="create retention policy $INFLUX_RETENTION_POLICY_NAME on telegraf Duration  $INFLUX_RETENTION_POLICY_VALUE Replication 1 DEFAULT"
retention_policy=`influx -execute "$policy"`
check_retention_policy=`influx -database 'telegraf' -execute 'SHOW RETENTION POLICIES' | grep -c "$INFLUX_RETENTION_POLICY_NAME .* true"`
if [ $check_retention_policy == 0 ]; then
   echo "FAIL: IN Database telgraf Retention policy creation failed"
   echo "       ********* Influx Db installation FAILED"
   exit 1
else
   echo "Database telgraf created successfully"
fi

echo "*******************************************************************************"
echo "                         Influx Db installation Completed Successfully"
echo "*******************************************************************************"
