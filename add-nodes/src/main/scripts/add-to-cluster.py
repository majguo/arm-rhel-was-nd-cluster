# Get cluster id
cluster = AdminConfig.getid('/ServerCluster:${CLUSTER_NAME}/')

# Add node as cluster member
node = AdminConfig.getid('/Node:${NODE_NAME}/')
AdminConfig.createClusterMember(cluster, node, [['memberName', '${CLUSTER_MEMBER_NAME}']])
AdminConfig.save()
AdminNodeManagement.syncActiveNodes()

# Start server
AdminControl.startServer('${CLUSTER_MEMBER_NAME}', '${NODE_NAME}')

# Restart node agent
na = AdminControl.queryNames('type=NodeAgent,node=${NODE_NAME},*')
AdminControl.invoke(na, 'restart', 'true true')