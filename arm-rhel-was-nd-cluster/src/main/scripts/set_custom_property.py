def setCustomPropertyOnObject(object_id, propname, propvalue):
    propsidlist = AdminConfig.showAttribute(object_id,'properties')[1:-1].split(' ')
    for id in propsidlist:
        name = AdminConfig.showAttribute(id, 'name')
        if name == propname:
            AdminConfig.remove(id)
            AdminConfig.modify(object_id, [['properties', [[['name', propname], ['value', propvalue]]]]])
            return
    AdminConfig.modify(object_id, [['properties', [[['name', propname], ['value', propvalue]]]]])

import sys
cellName = sys.argv[0]
propName = sys.argv[1]
propValue = sys.argv[2]

cell = AdminConfig.getid('/Cell:%s/' % cellName)
setCustomPropertyOnObject(cell, propName, propValue)
AdminConfig.save()
AdminNodeManagement.syncActiveNodes()