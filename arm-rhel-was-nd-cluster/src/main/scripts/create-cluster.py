# Create cluster
s1 = AdminConfig.getid('/Cell:${CELL_NAME}/')
cluster = AdminConfig.create('ServerCluster', s1, '[[name ${CLUSTER_NAME}]]')

# Add cluster members
nodes = [${NODES_STRING}]
for node in nodes:
  id = AdminConfig.getid('/Node:%s/' % node)
  clusterMemberName = '${CLUSTER_NAME}_%s' % node
  AdminConfig.createClusterMember(cluster, id, [['memberName', clusterMemberName]])
  server = AdminConfig.getid('/Server:%s/' % clusterMemberName)
  mp = AdminConfig.list('MonitoringPolicy', server)
  AdminConfig.modify(mp, '[[nodeRestartState RUNNING]]')
AdminConfig.save()
AdminNodeManagement.syncActiveNodes()

# Start cluster
clusterMgr = AdminControl.completeObjectName('cell=${CELL_NAME},type=ClusterMgr,*')
AdminControl.invoke(clusterMgr, 'retrieveClusters')
cluster = AdminControl.completeObjectName('cell=${CELL_NAME},type=Cluster,name=${CLUSTER_NAME},*')
AdminControl.invoke(cluster, 'start')