#!/bin/sh

create_dmgr_profile() {
    profileName=$1
    nodeName=$2
    cellName=$3
    adminUserName=$4
    adminPassword=$5

    /opt/IBM/WebSphere/ND/V9/bin/manageprofiles.sh -create -profileName ${profileName} \
        -templatePath /opt/IBM/WebSphere/ND/V9/profileTemplates/management -serverType DEPLOYMENT_MANAGER \
        -nodeName ${nodeName} -cellName ${cellName} -enableAdminSecurity true -adminUserName ${adminUserName} -adminPassword ${adminPassword}
}

add_admin_credentials_to_soap_client_props() {
    profileName=$1
    adminUserName=$2
    adminPassword=$3
    soapClientProps=/opt/IBM/WebSphere/ND/V9/profiles/${profileName}/properties/soap.client.props

    # Add admin credentials
    sed -i "s/com.ibm.SOAP.securityEnabled=false/com.ibm.SOAP.securityEnabled=true/g" "$soapClientProps"
    sed -i "s/com.ibm.SOAP.loginUserid=/com.ibm.SOAP.loginUserid=${adminUserName}/g" "$soapClientProps"
    sed -i "s/com.ibm.SOAP.loginPassword=/com.ibm.SOAP.loginPassword=${adminPassword}/g" "$soapClientProps"

    # Encrypt com.ibm.SOAP.loginPassword
    /opt/IBM/WebSphere/ND/V9/profiles/${profileName}/bin/PropFilePasswordEncoder.sh "$soapClientProps" com.ibm.SOAP.loginPassword
}

create_systemd_service() {
    srvName=$1
    srvDescription=$2
    profileName=$3
    serverName=$4
    srvPath=/etc/systemd/system/${srvName}.service

    # Add systemd unit file
    echo "[Unit]" > "$srvPath"
    echo "Description=${srvDescription}" >> "$srvPath"
    echo "[Service]" >> "$srvPath"
    echo "Type=forking" >> "$srvPath"
    echo "ExecStart=/opt/IBM/WebSphere/ND/V9/profiles/${profileName}/bin/startServer.sh ${serverName}" >> "$srvPath"
    echo "ExecStop=/opt/IBM/WebSphere/ND/V9/profiles/${profileName}/bin/stopServer.sh ${serverName}" >> "$srvPath"
    echo "PIDFile=/opt/IBM/WebSphere/ND/V9/profiles/${profileName}/logs/${serverName}/${serverName}.pid" >> "$srvPath"
    echo "SuccessExitStatus=143 0" >> "$srvPath"
    echo "[Install]" >> "$srvPath"
    echo "WantedBy=default.target" >> "$srvPath"
    chmod a+x "$srvPath"

    # Enable service
    systemctl daemon-reload
    systemctl enable "$srvName"
}

create_cluster() {
    profileName=$1
    dmgrNode=$2
    cellName=$3
    clusterName=$4
    members=$5

    nodes=( $(/opt/IBM/WebSphere/ND/V9/profiles/${profileName}/bin/wsadmin.sh -lang jython -c "AdminConfig.list('Node')" \
        | grep -Po "(?<=\/nodes\/)[^|]*(?=|.*)" | grep -v $dmgrNode | sed 's/^/"/;s/$/"/') )
    while [ ${#nodes[@]} -ne $members ]
    do
        sleep 5
        echo "adding more nodes..."
        nodes=( $(/opt/IBM/WebSphere/ND/V9/profiles/${profileName}/bin/wsadmin.sh -lang jython -c "AdminConfig.list('Node')" \
            | grep -Po "(?<=\/nodes\/)[^|]*(?=|.*)" | grep -v $dmgrNode | sed 's/^/"/;s/$/"/') )
    done
    sleep 60
    echo "all nodes are managed, creating cluster..."
    nodes_string=$( IFS=,; echo "${nodes[*]}" )

    cp create-cluster.py create-cluster.py.bak
    sed -i "s/\${CELL_NAME}/${cellName}/g" create-cluster.py
    sed -i "s/\${CLUSTER_NAME}/${clusterName}/g" create-cluster.py
    sed -i "s/\${NODES_STRING}/${nodes_string}/g" create-cluster.py

    /opt/IBM/WebSphere/ND/V9/profiles/${profileName}/bin/wsadmin.sh -lang jython -f create-cluster.py
    echo "cluster \"${clusterName}\" is successfully created!"
}

create_data_source() {
    profileName=$1
    clusterName=$2
    db2ServerName=$3
    db2ServerPortNumber=$4
    db2DBName=$5
    db2DBUserName=$6
    db2DBUserPwd=$7
    db2DSJndiName=${8:-jdbc/Sample}
    jdbcDriverPath=/opt/IBM/WebSphere/ND/V9/db2/java

    if [ -z "$db2ServerName" ] || [ -z "$db2ServerPortNumber" ] || [ -z "$db2DBName" ] || [ -z "$db2DBUserName" ] || [ -z "$db2DBUserPwd" ]; then
        echo "quit due to DB2 connectoin info is not provided"
        exit 0
    fi

    # Get jython file template & replace placeholder strings with user-input parameters
    cp create-ds.py create-ds.py.bak
    sed -i "s/\${CLUSTER_NAME}/${clusterName}/g" create-ds.py
    sed -i "s#\${DB2UNIVERSAL_JDBC_DRIVER_PATH}#${jdbcDriverPath}#g" create-ds.py
    sed -i "s/\${DB2_DATABASE_USER_NAME}/${db2DBUserName}/g" create-ds.py
    sed -i "s/\${DB2_DATABASE_USER_PASSWORD}/${db2DBUserPwd}/g" create-ds.py
    sed -i "s/\${DB2_DATABASE_NAME}/${db2DBName}/g" create-ds.py
    sed -i "s/\${DB2_DATASOURCE_JNDI_NAME}/${db2DSJndiName}/g" create-ds.py
    sed -i "s/\${DB2_SERVER_NAME}/${db2ServerName}/g" create-ds.py
    sed -i "s/\${PORT_NUMBER}/${db2ServerPortNumber}/g" create-ds.py

    # Create JDBC provider and data source using jython file
    /opt/IBM/WebSphere/ND/V9/profiles/${profileName}/bin/wsadmin.sh -lang jython -f create-ds.py
    echo "DB2 JDBC provider and data source are successfully created!"
}

create_custom_profile() {
    profileName=$1
    dmgrHostName=$2
    dmgrPort=$3
    dmgrAdminUserName=$4
    dmgrAdminPassword=$5
    
    curl $dmgrHostName:$dmgrPort >/dev/null 2>&1
    while [ $? -ne 0 ]
    do
        sleep 5
        echo "dmgr is not ready"
        curl $dmgrHostName:$dmgrPort >/dev/null 2>&1
    done
    sleep 60
    echo "dmgr is ready to add nodes"

    output=$(/opt/IBM/WebSphere/ND/V9/bin/manageprofiles.sh -create -profileName $profileName \
        -profilePath /opt/IBM/WebSphere/ND/V9/profiles/$profileName -templatePath /opt/IBM/WebSphere/ND/V9/profileTemplates/managed \
        -dmgrHost $dmgrHostName -dmgrPort $dmgrPort -dmgrAdminUserName $dmgrAdminUserName -dmgrAdminPassword $dmgrAdminPassword 2>&1)
    while echo $output | grep -qv "SUCCESS"
    do
        sleep 10
        echo "adding node failed, retry it later..."
        rm -rf /opt/IBM/WebSphere/ND/V9/profiles/$profileName
        output=$(/opt/IBM/WebSphere/ND/V9/bin/manageprofiles.sh -create -profileName $profileName \
            -profilePath /opt/IBM/WebSphere/ND/V9/profiles/$profileName -templatePath /opt/IBM/WebSphere/ND/V9/profileTemplates/managed \
            -dmgrHost $dmgrHostName -dmgrPort $dmgrPort -dmgrAdminUserName $dmgrAdminUserName -dmgrAdminPassword $dmgrAdminPassword 2>&1)
    done
    echo $output
}

copy_db2_drivers() {
    wasRootPath=/opt/IBM/WebSphere/ND/V9
    jdbcDriverPath="$wasRootPath"/db2/java

    mkdir -p "$jdbcDriverPath"
    find "$wasRootPath" -name "db2jcc*.jar" | xargs -I{} cp {} "$jdbcDriverPath"
}

while getopts "l:u:p:m:c:f:h:r:n:t:d:i:s:j:" opt; do
    case $opt in
        l)
            imKitLocation=$OPTARG #SAS URI of the IBM Installation Manager install kit in Azure Storage
        ;;
        u)
            userName=$OPTARG #IBM user id for downloading artifacts from IBM web site
        ;;
        p)
            password=$OPTARG #password of IBM user id for downloading artifacts from IBM web site
        ;;
        m)
            adminUserName=$OPTARG #User id for admimistrating WebSphere Admin Console
        ;;
        c)
            adminPassword=$OPTARG #Password for administrating WebSphere Admin Console
        ;;
        f)
            dmgr=$OPTARG #Flag indicating whether to install deployment manager
        ;;
        h)
            dmgrHostName=$OPTARG #Host name of deployment manager server
        ;;
        r)
            members=$OPTARG #Number of cluster members
        ;;
        n)
            db2ServerName=$OPTARG #Host name/IP address of IBM DB2 Server
        ;;
        t)
            db2ServerPortNumber=$OPTARG #Server port number of IBM DB2 Server
        ;;
        d)
            db2DBName=$OPTARG #Database name of IBM DB2 Server
        ;;
        i)
            db2DBUserName=$OPTARG #Database user name of IBM DB2 Server
        ;;
        s)
            db2DBUserPwd=$OPTARG #Database user password of IBM DB2 Server
        ;;
        j)
            db2DSJndiName=$OPTARG #Datasource JNDI name
        ;;
    esac
done

# Variables
imKitName=agent.installer.linux.gtk.x86_64_1.9.0.20190715_0328.zip
repositoryUrl=http://www.ibm.com/software/repositorymanager/com.ibm.websphere.ND.v90
wasNDTraditional=com.ibm.websphere.ND.v90_9.0.5001.20190828_0616
ibmJavaSDK=com.ibm.java.jdk.v8_8.0.5040.20190808_0919

# Turn off firewall
systemctl stop firewalld
systemctl disable firewalld

# Create installation directories
mkdir -p /opt/IBM/InstallationManager/V1.9 && mkdir -p /opt/IBM/WebSphere/ND/V9 && mkdir -p /opt/IBM/IMShared

# Install IBM Installation Manager
wget -O "$imKitName" "$imKitLocation"
mkdir im_installer
unzip -q "$imKitName" -d im_installer
./im_installer/userinstc -log log_file -acceptLicense -installationDirectory /opt/IBM/InstallationManager/V1.9

# Install IBM WebSphere Application Server Network Deployment V9 using IBM Instalation Manager
/opt/IBM/InstallationManager/V1.9/eclipse/tools/imutilsc saveCredential -secureStorageFile storage_file \
    -userName "$userName" -userPassword "$password" -url "$repositoryUrl"
/opt/IBM/InstallationManager/V1.9/eclipse/tools/imcl install "$wasNDTraditional" "$ibmJavaSDK" -repositories "$repositoryUrl" \
    -installationDirectory /opt/IBM/WebSphere/ND/V9/ -sharedResourcesDirectory /opt/IBM/IMShared/ \
    -secureStorageFile storage_file -acceptLicense -showProgress

# Create cluster by creating deployment manager, node agent & add nodes to be managed
if [ "$dmgr" = True ]; then
    create_dmgr_profile Dmgr001 Dmgr001Node Dmgr001NodeCell "$adminUserName" "$adminPassword"
    add_admin_credentials_to_soap_client_props Dmgr001 "$adminUserName" "$adminPassword"
    create_systemd_service was_dmgr "IBM WebSphere Application Server ND Deployment Manager" Dmgr001 dmgr
    /opt/IBM/WebSphere/ND/V9/profiles/Dmgr001/bin/startServer.sh dmgr
    create_cluster Dmgr001 Dmgr001Node Dmgr001NodeCell MyCluster $members
    create_data_source Dmgr001 MyCluster "$db2ServerName" "$db2ServerPortNumber" "$db2DBName" "$db2DBUserName" "$db2DBUserPwd" "$db2DSJndiName"
else
    create_custom_profile Custom $dmgrHostName 8879 "$adminUserName" "$adminPassword"
    add_admin_credentials_to_soap_client_props Custom "$adminUserName" "$adminPassword"
    create_systemd_service was_nodeagent "IBM WebSphere Application Server ND Node Agent" Custom nodeagent
    copy_db2_drivers
fi
