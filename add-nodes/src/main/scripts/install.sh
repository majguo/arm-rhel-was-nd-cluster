#!/bin/sh

add_node() {
    profileName=$1
    nodeName=$2
    userName=$3
    password=$4    
    dmgrHostName=$5
    dmgrPort=${6:-8879}
    nodeGroupName=${7:-DefaultNodeGroup}
    coreGroupName=${8:-DefaultCoreGroup}
    
    curl $dmgrHostName:$dmgrPort >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "dmgr is not available, exiting now..."
        exit 1
    fi
    echo "dmgr is ready to add nodes"

    /opt/IBM/WebSphere/ND/V9/bin/manageprofiles.sh -create -profileName $profileName -nodeName $nodeName \
        -profilePath /opt/IBM/WebSphere/ND/V9/profiles/$profileName -templatePath /opt/IBM/WebSphere/ND/V9/profileTemplates/managed
    output=$(/opt/IBM/WebSphere/ND/V9/bin/addNode.sh $dmgrHostName $dmgrPort -username $userName -password $password \
        -nodegroupname "$nodeGroupName" -coregroupname "$coreGroupName" -profileName $profileName 2>&1)
    while echo $output | grep -qv "has been successfully federated"
    do
        sleep 10
        echo "adding node failed, retry it later..."
        output=$(/opt/IBM/WebSphere/ND/V9/bin/addNode.sh $dmgrHostName $dmgrPort -username $userName -password $password \
            -nodegroupname "$nodeGroupName" -coregroupname "$coreGroupName" -profileName $profileName 2>&1)
    done
    echo $output
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

add_to_cluster() {
    profileName=$1
    nodeName=$2
    clusterName=${3:-MyCluster}

    # Validation check 
    output=$(/opt/IBM/WebSphere/ND/V9/profiles/${profileName}/bin/wsadmin.sh -lang jython -c "AdminConfig.getid('/DynamicCluster:${clusterName}')" 2>&1)
    if echo $output | grep -q "/dynamicclusters/${clusterName}|"; then
        echo "${clusterName} is a dynamic cluster, no further operation is required"
        exit 0
    fi

    output=$(/opt/IBM/WebSphere/ND/V9/profiles/${profileName}/bin/wsadmin.sh -lang jython -c "AdminConfig.getid('/ServerCluster:${clusterName}')" 2>&1)
    if echo $output | grep -qv "/clusters/${clusterName}|"; then
        echo "${clusterName} is not a valid cluster, quit"
        exit 1
    fi

    # Add node to cluster
    cp add-to-cluster.py add-to-cluster.py.bak
    sed -i "s/\${NODE_NAME}/${nodeName}/g" add-to-cluster.py
    sed -i "s/\${CLUSTER_NAME}/${clusterName}/g" add-to-cluster.py
    /opt/IBM/WebSphere/ND/V9/profiles/${profileName}/bin/wsadmin.sh -lang jython -f add-to-cluster.py
   
    # Start cluster member server
    /opt/IBM/WebSphere/ND/V9/profiles/${profileName}/bin/startServer.sh server_${nodeName}
    echo "Node ${nodeName} is successfully added to cluster ${clusterName}"
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

copy_db2_drivers() {
    wasRootPath=/opt/IBM/WebSphere/ND/V9
    jdbcDriverPath="$wasRootPath"/db2/java

    mkdir -p "$jdbcDriverPath"
    find "$wasRootPath" -name "db2jcc*.jar" | xargs -I{} cp {} "$jdbcDriverPath"
}

while getopts "l:u:p:m:c:s:d:r:h:o:" opt; do
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
        s)
            clusterName=$OPTARG #Name of the existing cluster
        ;;
        d)
            nodeGroupName=$OPTARG #Name of the existing node group created in deployment manager server
        ;;
        r)
            coreGroupName=$OPTARG #Name of the existing core group created in deployment manager server
        ;;
        h)
            dmgrHostName=$OPTARG #Host name of the existing deployment manager server
        ;;
        o)
            dmgrPort=$OPTARG #Port number of the existing deployment manager server
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

# Add nodes to existing cluster
add_node Custom $(hostname)Node01 "$adminUserName" "$adminPassword" "$dmgrHostName" "$dmgrPort" "$nodeGroupName" "$coreGroupName"
add_admin_credentials_to_soap_client_props Custom "$adminUserName" "$adminPassword"
add_to_cluster Custom $(hostname)Node01 "$clusterName"
create_systemd_service was_nodeagent "IBM WebSphere Application Server ND Node Agent" Custom nodeagent
copy_db2_drivers
