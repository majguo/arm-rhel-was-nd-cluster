# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

# Create dynamic cluster
properties = ('[-membershipPolicy "node_nodegroup = \'${NODE_GROUP_NAME}\'" '
'-dynamicClusterProperties "[[operationalMode automatic][minInstances 1][maxInstances -1][numVerticalInstances 1][serverInactivityTime 1440]]" '
'-clusterProperties "[[preferLocal false][createDomain false][templateName default][coreGroup ${CORE_GROUP_NAME}]]"]')
AdminTask.createDynamicCluster('${CLUSTER_NAME}', properties)

# Save changes and synchronize to active nodes
AdminConfig.save()
AdminNodeManagement.syncActiveNodes()