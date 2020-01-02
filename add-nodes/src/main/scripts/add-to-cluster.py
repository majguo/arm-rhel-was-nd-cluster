# Get cluster id
cluster = AdminConfig.getid('/ServerCluster:${CLUSTER_NAME}/')

# Add node as cluster member
node = AdminConfig.getid('/Node:${NODE_NAME}/')
AdminConfig.createClusterMember(cluster, node, [['memberName', '${CLUSTER_MEMBER_NAME}']])
AdminConfig.save()
AdminNodeManagement.syncActiveNodes()