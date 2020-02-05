def getObjectCustomProperty(object_id, propname):
    x = AdminConfig.showAttribute(object_id,'properties')
    if len(x) == 0:
        return None

    if x.startswith("["):
        propsidlist = x[1:-1].split(' ')
    else:
        propsidlist = [x]
    for id in propsidlist:
        name = AdminConfig.showAttribute(id, 'name')
        if name == propname:
            return AdminConfig.showAttribute(id, 'value')
    return None

import sys
cellName = sys.argv[0]
propName = sys.argv[1]

cell = AdminConfig.getid('/Cell:%s/' % cellName)
propValue = getObjectCustomProperty(cell, propName)
print '[{0}:{1}]'.format(propName, propValue)